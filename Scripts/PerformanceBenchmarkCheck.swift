import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var availableVersion: String?
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    func checkForUpdates() {}
}

private struct BenchmarkResourceSample {
    let cpuTicks: UInt64
    let wakeups: UInt64
    let residentBytes: UInt64
    let footprintBytes: UInt64
    let privateBytes: UInt64
    let timestamp: Date
}

private struct BenchmarkWindowResult: Codable {
    let durationSeconds: Double
    let processCPUAveragePercent: Double
    let processCPUPeakPercent: Double
    let wholeMachineCPUAveragePercent: Double
    let wholeMachineCPUPeakPercent: Double
    let wakeupsAveragePerSecond: Double
    let wakeupsPeakPerSecond: Double
    let residentAverageBytes: UInt64
    let residentPeakBytes: UInt64
    let footprintAverageBytes: UInt64
    let footprintPeakBytes: UInt64
    let privateAverageBytes: UInt64
    let privatePeakBytes: UInt64
    let observablePublications: Int
}

private struct BenchmarkReport: Codable {
    let label: String
    let version: String
    let build: String
    let activeProcessorCount: Int
    let sampleIntervalSeconds: Double
    let measurementSeconds: Double
    let hidden: BenchmarkWindowResult
    let visible: BenchmarkWindowResult
}

@MainActor
private final class PublicationCounter {
    private(set) var value = 0
    private var cancellable: AnyCancellable?

    init(monitor: PerformanceMonitor) {
#if PERFORMANCE_OPTIMIZED
        cancellable = monitor.panelProjection.objectWillChange.sink { [weak self] _ in
            self?.value += 1
        }
#else
        cancellable = monitor.objectWillChange.sink { [weak self] _ in
            self?.value += 1
        }
#endif
    }
}

@main
enum PerformanceBenchmarkCheck {
    @MainActor
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let label = value(after: "--label", in: arguments) ?? "benchmark"
        let outputPath = value(after: "--output", in: arguments)
        let measurementSeconds = Double(
            value(after: "--seconds", in: arguments) ?? "60"
        ) ?? 60
        let warmupSeconds = Double(
            value(after: "--warmup", in: arguments) ?? "10"
        ) ?? 10
        precondition(measurementSeconds > 0)
        precondition(warmupSeconds >= 0)

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let suiteName = "com.xipiyoung.ColdHot.performance-benchmark"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create benchmark defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = MonitorSettings(defaults: defaults)
        settings.applyPreset(.diagnostic)
        settings.sampleInterval = 2
        settings.completeOnboarding()
        settings.setPanelBackgroundEnabled(true)
        settings.setPanelBackgroundAudioEnabled(false)
        settings.setThresholdEnabled(true, for: .temperatureCPU)

        let monitor = PerformanceMonitor(settings: settings)
        let dockController = DockDelayController(defaults: defaults)
        let backgroundStore = PanelBackgroundStore()
        let playbackController = PanelBackgroundPlaybackController()
        let updateController = UpdateController()
        let publicationCounter = PublicationCounter(monitor: monitor)

        let hostingView = NSHostingView(
            rootView: DashboardView(
                monitor: monitor,
                settings: settings,
                dockController: dockController,
                panelBackgroundStore: backgroundStore,
                panelBackgroundPlaybackController: playbackController,
                updateController: updateController
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 370, height: 720)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        pumpRunLoop(seconds: 2)

        window.orderOut(nil)
        playbackController.pause()
#if PERFORMANCE_OPTIMIZED
        monitor.setPanelVisible(false)
#endif
        pumpRunLoop(seconds: warmupSeconds)
        let hiddenPublicationStart = publicationCounter.value
        let hidden = measure(
            seconds: measurementSeconds,
            publicationStart: hiddenPublicationStart,
            publicationCounter: publicationCounter
        )

#if PERFORMANCE_OPTIMIZED
        monitor.setPanelVisible(true)
#endif
        window.orderFront(nil)
        pumpRunLoop(seconds: warmupSeconds)
        let visiblePublicationStart = publicationCounter.value
        let visible = measure(
            seconds: measurementSeconds,
            publicationStart: visiblePublicationStart,
            publicationCounter: publicationCounter
        )
        window.orderOut(nil)
        playbackController.pause()

        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "source"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "source"
        let report = BenchmarkReport(
            label: label,
            version: version,
            build: build,
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            sampleIntervalSeconds: settings.sampleInterval,
            measurementSeconds: measurementSeconds,
            hidden: hidden,
            visible: visible
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        if let outputPath {
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    @MainActor
    private static func pumpRunLoop(seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.05)))
        }
    }

    @MainActor
    private static func measure(
        seconds: Double,
        publicationStart: Int,
        publicationCounter: PublicationCounter
    ) -> BenchmarkWindowResult {
        let start = resourceSample()
        var previous = start
        var processCPUPeak = 0.0
        var wakeupsPeak = 0.0
        var residentTotal: UInt64 = 0
        var footprintTotal: UInt64 = 0
        var privateTotal: UInt64 = 0
        var residentPeak: UInt64 = 0
        var footprintPeak: UInt64 = 0
        var privatePeak: UInt64 = 0
        var memorySampleCount: UInt64 = 0
        let deadline = Date().addingTimeInterval(seconds)

        while Date() < deadline {
            let intervalEnd = min(deadline, Date().addingTimeInterval(1))
            RunLoop.main.run(until: intervalEnd)
            let current = resourceSample()
            let interval = current.timestamp.timeIntervalSince(previous.timestamp)
            if interval > 0, current.cpuTicks >= previous.cpuTicks {
                processCPUPeak = max(
                    processCPUPeak,
                    ProcessCPUAccounting.current.cpuUsage(
                        deltaTicks: current.cpuTicks - previous.cpuTicks,
                        elapsedSeconds: interval
                    )
                )
                if current.wakeups >= previous.wakeups {
                    wakeupsPeak = max(
                        wakeupsPeak,
                        Double(current.wakeups - previous.wakeups) / interval
                    )
                }
            }
            residentTotal &+= current.residentBytes
            footprintTotal &+= current.footprintBytes
            privateTotal &+= current.privateBytes
            residentPeak = max(residentPeak, current.residentBytes)
            footprintPeak = max(footprintPeak, current.footprintBytes)
            privatePeak = max(privatePeak, current.privateBytes)
            memorySampleCount &+= 1
            previous = current
        }

        let end = resourceSample()
        let duration = max(end.timestamp.timeIntervalSince(start.timestamp), 0.001)
        let processCPUAverage = end.cpuTicks >= start.cpuTicks
            ? ProcessCPUAccounting.current.cpuUsage(
                deltaTicks: end.cpuTicks - start.cpuTicks,
                elapsedSeconds: duration
            )
            : 0
        let wholeMachineAverage = ProcessCPUAccounting.wholeMachineUsage(
            processUsage: processCPUAverage,
            logicalProcessorCount: ProcessInfo.processInfo.activeProcessorCount
        )
        let wholeMachinePeak = ProcessCPUAccounting.wholeMachineUsage(
            processUsage: processCPUPeak,
            logicalProcessorCount: ProcessInfo.processInfo.activeProcessorCount
        )
        let wakeupsAverage = end.wakeups >= start.wakeups
            ? Double(end.wakeups - start.wakeups) / duration
            : 0
        let divisor = max(memorySampleCount, 1)
        return BenchmarkWindowResult(
            durationSeconds: duration,
            processCPUAveragePercent: processCPUAverage,
            processCPUPeakPercent: processCPUPeak,
            wholeMachineCPUAveragePercent: wholeMachineAverage,
            wholeMachineCPUPeakPercent: wholeMachinePeak,
            wakeupsAveragePerSecond: wakeupsAverage,
            wakeupsPeakPerSecond: wakeupsPeak,
            residentAverageBytes: residentTotal / divisor,
            residentPeakBytes: residentPeak,
            footprintAverageBytes: footprintTotal / divisor,
            footprintPeakBytes: footprintPeak,
            privateAverageBytes: privateTotal / divisor,
            privatePeakBytes: privatePeak,
            observablePublications: publicationCounter.value - publicationStart
        )
    }

    private static func resourceSample() -> BenchmarkResourceSample {
        var usage = rusage_info_v4()
        let usageResult = withUnsafeMutablePointer(to: &usage) { pointer -> Int32 in
            pointer.withMemoryRebound(to: Optional<rusage_info_t>.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        precondition(usageResult == 0)

        var vmInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let vmResult = withUnsafeMutablePointer(to: &vmInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        precondition(vmResult == KERN_SUCCESS)
        return BenchmarkResourceSample(
            cpuTicks: usage.ri_user_time &+ usage.ri_system_time,
            wakeups: usage.ri_pkg_idle_wkups &+ usage.ri_interrupt_wkups,
            residentBytes: vmInfo.resident_size,
            footprintBytes: vmInfo.phys_footprint,
            privateBytes: vmInfo.internal &+ vmInfo.compressed,
            timestamp: Date()
        )
    }
}
