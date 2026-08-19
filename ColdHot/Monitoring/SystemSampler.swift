import Foundation
import Darwin
import CoreGraphics
import IOKit
import IOKit.ps
import Network
import SystemConfiguration

final class SystemSampler {
    private var previousCPUTicks: CPUTicks?
    private var previousCoreTicks: [CPUTicks] = []
    private var previousNetwork: NetworkCounterSample?
    private var previousDisk: DiskCounters?
    private var cachedDiskCapacity: (available: UInt64, total: UInt64)?
    private var diskCapacityDate: Date?
    private var previousProcessCounters: [pid_t: ProcessCounters] = [:]
    private var previousProcessDate: Date?
    private var cachedRankings = ProcessRankings()
    private var thermalState = ProcessInfo.processInfo.thermalState
    private var thermalStateSince = Date()
    private let processCPUAccounting = ProcessCPUAccounting.current
    private let latencyProbe = NetworkLatencyProbe()
    private let smcPowerReader = SMCPowerReader()
    private lazy var hidTemperatureReader = HIDTemperatureReader()

    func sample(request: SamplingRequest) -> PerformanceSnapshot {
        let now = Date()
        let cpu = request.includes(.cpu) ? readCPU(request: request) : CPUSnapshot()
        let gpu = request.includes(.gpu) ? readGPU(request: request) : GPUSnapshot()
        let memory = request.includes(.memory) ? readMemory(request: request) : MemorySnapshot()
        let network = request.includes(.network)
            ? readNetwork(at: now, request: request)
            : NetworkSnapshot()
        let disk = request.includes(.disk)
            ? readDisk(at: now, request: request)
            : DiskSnapshot()
        let fans = smcPowerReader?.readFans() ?? []
        let battery = request.includes(.battery) ? readBattery(request: request) : nil

        updateThermalState(at: now)
        let thermal = readThermal(request: request)

#if APP_STORE
        let rankings = ProcessRankings()
#else
        let needsProcesses = request.includes(.cpuProcesses)
            || request.includes(.cpuWakeups)
            || request.includes(.memoryProcesses)
            || request.includes(.diskProcesses)
        let rankings = needsProcesses ? readProcessesIfNeeded(at: now) : ProcessRankings()
#endif

        return PerformanceSnapshot(
            timestamp: now,
            cpu: cpu,
            gpu: gpu,
            memory: memory,
            network: network,
            disk: disk,
            thermal: thermal,
            fans: fans,
            battery: battery,
            topCPUProcesses: request.includes(.cpuProcesses) ? rankings.cpu : [],
            topWakeupProcesses: request.includes(.cpuWakeups) ? rankings.wakeups : [],
            topMemoryProcesses: request.includes(.memoryProcesses) ? rankings.memory : [],
            topDiskProcesses: request.includes(.diskProcesses) ? rankings.disk : []
        )
    }

    private func readCPU(request: SamplingRequest) -> CPUSnapshot {
        guard let ticks = readAggregateCPUTicks() else { return CPUSnapshot() }
        defer { previousCPUTicks = ticks }

        var snapshot = CPUSnapshot()
        if let previousCPUTicks {
            let totalDelta = ticks.total &- previousCPUTicks.total
            if totalDelta > 0 {
                snapshot.user = Double(ticks.user &- previousCPUTicks.user) / Double(totalDelta) * 100
                snapshot.system = Double(ticks.system &- previousCPUTicks.system) / Double(totalDelta) * 100
                snapshot.idle = Double(ticks.idle &- previousCPUTicks.idle) / Double(totalDelta) * 100
                snapshot.usage = max(0, 100 - snapshot.idle)
            }
        }

        if request.includes(.cpuLoad) {
            snapshot.loadAverage = readLoadAverage()
        }
        if request.includes(.cpuCores) {
            snapshot.perCore = readPerCoreUsage()
        }
        return snapshot
    }

    private func readAggregateCPUTicks() -> CPUTicks? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: UInt64(load.cpu_ticks.0),
            system: UInt64(load.cpu_ticks.1),
            idle: UInt64(load.cpu_ticks.2),
            nice: UInt64(load.cpu_ticks.3)
        )
    }

    private func readPerCoreUsage() -> [Double] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let stateCount = Int(CPU_STATE_MAX)
        var current: [CPUTicks] = []
        current.reserveCapacity(Int(cpuCount))
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * stateCount
            current.append(CPUTicks(
                user: UInt64(info[base + Int(CPU_STATE_USER)]),
                system: UInt64(info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt64(info[base + Int(CPU_STATE_NICE)])
            ))
        }

        defer { previousCoreTicks = current }
        guard previousCoreTicks.count == current.count else {
            return current.map { _ in 0 }
        }

        return zip(current, previousCoreTicks).map { now, old in
            let totalDelta = now.total &- old.total
            let idleDelta = now.idle &- old.idle
            guard totalDelta > 0 else { return 0 }
            return Double(totalDelta - idleDelta) / Double(totalDelta) * 100
        }
    }

    private func readLoadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        _ = getloadavg(&values, 3)
        return values
    }

    private func readGPU(request: SamplingRequest) -> GPUSnapshot {
#if APP_STORE
        GPUSnapshot()
#else
        var snapshot = GPUSnapshot()
        guard let matching = IOServiceMatching("AGXAccelerator") else { return snapshot }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return snapshot
        }
        defer { IOObjectRelease(iterator) }

        var deviceValues: [Double] = []
        var rendererValues: [Double] = []
        var tilerValues: [Double] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let statistics = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {
                if let value = statistics["Device Utilization %"] as? NSNumber {
                    deviceValues.append(value.doubleValue)
                }
                if request.includes(.gpuBreakdown),
                   let value = statistics["Renderer Utilization %"] as? NSNumber {
                    rendererValues.append(value.doubleValue)
                }
                if request.includes(.gpuBreakdown),
                   let value = statistics["Tiler Utilization %"] as? NSNumber {
                    tilerValues.append(value.doubleValue)
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        snapshot.usage = deviceValues.max()
        snapshot.renderer = rendererValues.max()
        snapshot.tiler = tilerValues.max()
        if request.includes(.gpuDisplays) {
            snapshot.displays = readDisplays()
        }
        return snapshot
#endif
    }

    private func readDisplays() -> [DisplaySnapshot] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var identifiers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &identifiers, &count) == .success else { return [] }

        return identifiers.prefix(Int(count)).compactMap { displayID in
            guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }
            let builtIn = CGDisplayIsBuiltin(displayID) != 0
            return DisplaySnapshot(
                id: displayID,
                name: builtIn ? "内建显示器" : "外接显示器",
                width: mode.width,
                height: mode.height,
                refreshRate: mode.refreshRate > 0 ? mode.refreshRate : nil
            )
        }
    }

    private func readMemory(request: SamplingRequest) -> MemorySnapshot {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return MemorySnapshot() }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        let accounting = MemoryAccounting(
            pageSize: page,
            physicalMemory: total
        ).calculate(
            internalPages: UInt64(info.internal_page_count),
            purgeablePages: UInt64(info.purgeable_count),
            wiredPages: UInt64(info.wire_count),
            compressedPages: UInt64(info.compressor_page_count),
            externalPages: UInt64(info.external_page_count)
        )
        var snapshot = MemorySnapshot(
            used: accounting.used,
            total: total,
            pressure: readMemoryPressure()
        )

        if request.includes(.memoryComposition) {
            snapshot.app = accounting.app
            snapshot.wired = accounting.wired
            snapshot.compressed = accounting.compressed
            snapshot.cached = accounting.cached
        }
        if request.includes(.memorySwap), let swap = readSwapUsage() {
            snapshot.swapUsed = swap.used
            snapshot.swapTotal = swap.total
        }
        return snapshot
    }

    private func readMemoryPressure() -> MemoryPressure {
        var value: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else {
            return .normal
        }
        if value >= 4 { return .critical }
        if value >= 2 { return .warning }
        return .normal
    }

    private func readSwapUsage() -> (used: UInt64, total: UInt64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return (usage.xsu_used, usage.xsu_total)
    }

    private func readNetwork(at now: Date, request: SamplingRequest) -> NetworkSnapshot {
        let interface = primaryNetworkInterface() ?? "en0"
        guard let counters = networkCounters(for: interface) else {
            return NetworkSnapshot(interface: interface, interfaceType: interfaceType(interface))
        }

        let current = NetworkCounterSample(counters: counters, date: now, identity: interface)
        defer { previousNetwork = current }

        var snapshot = NetworkSnapshot(
            interface: interface,
            interfaceType: interfaceType(interface),
            receivedBytes: counters.receivedBytes,
            sentBytes: counters.sentBytes,
            receivedPackets: counters.receivedPackets,
            sentPackets: counters.sentPackets,
            inputErrors: counters.inputErrors,
            outputErrors: counters.outputErrors,
            drops: counters.drops
        )

        if let previousNetwork, previousNetwork.identity == interface {
            let elapsed = now.timeIntervalSince(previousNetwork.date)
            if elapsed > 0 {
                snapshot.download = Double(counters.receivedBytes &- previousNetwork.counters.receivedBytes) / elapsed
                snapshot.upload = Double(counters.sentBytes &- previousNetwork.counters.sentBytes) / elapsed
            }
        }

        if request.includes(.networkLatency) {
            snapshot.latencyMilliseconds = latencyProbe.latestValue(startIfNeededAt: now)
        }
        return snapshot
    }

    private func primaryNetworkInterface() -> String? {
        guard let dictionary = SCDynamicStoreCopyValue(
            nil,
            "State:/Network/Global/IPv4" as CFString
        ) as? [String: Any] else { return nil }
        return dictionary[kSCDynamicStorePropNetPrimaryInterface as String] as? String
    }

    private func interfaceType(_ name: String) -> String {
        if name.hasPrefix("utun") { return "VPN 隧道" }
        if name.hasPrefix("en") { return "Wi-Fi / 以太网" }
        if name.hasPrefix("bridge") { return "网络桥接" }
        if name.hasPrefix("awdl") { return "Apple Wireless Direct Link" }
        return "网络接口"
    }

    private func networkCounters(for target: String) -> NetworkCounters? {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let firstAddress = addressList else { return nil }
        defer { freeifaddrs(addressList) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let address = cursor {
            let interface = address.pointee
            if String(cString: interface.ifa_name) == target,
               interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                return NetworkCounters(
                    receivedBytes: UInt64(data.ifi_ibytes),
                    sentBytes: UInt64(data.ifi_obytes),
                    receivedPackets: UInt64(data.ifi_ipackets),
                    sentPackets: UInt64(data.ifi_opackets),
                    inputErrors: UInt64(data.ifi_ierrors),
                    outputErrors: UInt64(data.ifi_oerrors),
                    drops: UInt64(data.ifi_iqdrops)
                )
            }
            cursor = interface.ifa_next
        }
        return nil
    }

    private func readDisk(at now: Date, request: SamplingRequest) -> DiskSnapshot {
        guard let counters = readDiskCounters(at: now) else { return DiskSnapshot() }
        defer { previousDisk = counters }

        var snapshot = DiskSnapshot(
            bytesRead: counters.bytesRead,
            bytesWritten: counters.bytesWritten
        )
        if let previousDisk {
            let elapsed = now.timeIntervalSince(previousDisk.date)
            if elapsed > 0 {
                snapshot.read = Double(counters.bytesRead &- previousDisk.bytesRead) / elapsed
                snapshot.write = Double(counters.bytesWritten &- previousDisk.bytesWritten) / elapsed
                snapshot.readIOPS = Double(counters.readOperations &- previousDisk.readOperations) / elapsed
                snapshot.writeIOPS = Double(counters.writeOperations &- previousDisk.writeOperations) / elapsed
            }
        }

        if request.includes(.diskCapacity), let capacity = diskCapacity(at: now) {
            snapshot.availableBytes = capacity.available
            snapshot.totalBytes = capacity.total
        }
        return snapshot
    }

    private func readDiskCounters(at now: Date) -> DiskCounters? {
#if APP_STORE
        nil
#else
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var result = DiskCounters(date: now)
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let statistics = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {
                result.bytesRead += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                result.bytesWritten += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
                result.readOperations += (statistics["Operations (Read)"] as? NSNumber)?.uint64Value ?? 0
                result.writeOperations += (statistics["Operations (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
#endif
    }

    private func readDiskCapacity() -> (available: UInt64, total: UInt64)? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return nil }
        return (UInt64(max(0, available)), UInt64(max(0, total)))
    }

    private func diskCapacity(at now: Date) -> (available: UInt64, total: UInt64)? {
        if let diskCapacityDate,
           now.timeIntervalSince(diskCapacityDate) < 30,
           let cachedDiskCapacity {
            return cachedDiskCapacity
        }
        let value = readDiskCapacity()
        cachedDiskCapacity = value
        diskCapacityDate = now
        return value
    }

    private func readBattery(request: SamplingRequest) -> BatterySnapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey as String] as? NSNumber,
                  let maximum = description[kIOPSMaxCapacityKey as String] as? NSNumber,
                  maximum.doubleValue > 0 else { continue }

            let state = description[kIOPSPowerSourceStateKey as String] as? String
            var snapshot = BatterySnapshot(
                percentage: current.doubleValue / maximum.doubleValue * 100,
                isCharging: (description[kIOPSIsChargingKey as String] as? NSNumber)?.boolValue ?? false,
                isOnACPower: state == (kIOPSACPowerValue as String),
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
            )

            if request.includes(.batteryRemaining) {
                snapshot.timeToEmptyMinutes = positiveInt(description[kIOPSTimeToEmptyKey as String])
                snapshot.timeToFullMinutes = positiveInt(description[kIOPSTimeToFullChargeKey as String])
            }
            if request.includes(.batteryHealth) {
                snapshot.health = description[kIOPSBatteryHealthKey as String] as? String
            }

#if !APP_STORE
            let needsController = request.includes(.batteryHealth)
                || request.includes(.batteryCycles)
                || request.includes(.batteryElectrical)
            if needsController, let properties = smartBatteryProperties() {
                if request.includes(.batteryCycles) {
                    snapshot.cycleCount = (properties["CycleCount"] as? NSNumber)?.intValue
                }
                if request.includes(.batteryHealth),
                   let design = (properties["DesignCapacity"] as? NSNumber)?.doubleValue,
                   let maximum = (properties["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue,
                   design > 0 {
                    snapshot.maximumCapacityPercent = min(max(maximum / design * 100, 0), 100)
                }
                if request.includes(.batteryElectrical) {
                    let voltage = (properties["Voltage"] as? NSNumber)?.doubleValue
                    let amperage = (properties["Amperage"] as? NSNumber)?.doubleValue
                    snapshot.voltageVolts = voltage.map { $0 / 1_000 }
                    snapshot.amperageAmps = amperage.map { $0 / 1_000 }
                    if let voltage, let amperage {
                        snapshot.estimatedBatteryPowerWatts = abs(voltage * amperage) / 1_000_000
                    }
                }
            }
            if request.includes(.batteryElectrical),
               let power = smcPowerReader?.readPower() {
                snapshot.systemPowerWatts = power.systemTotalWatts
                snapshot.dcInputPowerWatts = power.dcInputWatts
                snapshot.batteryPowerWatts = power.batteryWatts
            }
#endif
            return snapshot
        }
        return nil
    }

    private func positiveInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, number.intValue > 0 else { return nil }
        return number.intValue
    }

    private func readThermal(request: SamplingRequest) -> ThermalSnapshot {
        var snapshot = ThermalSnapshot(state: thermalState, stateSince: thermalStateSince)

        if request.includes(.thermalCPU) {
            let hidValues = hidTemperatureReader?.readTemperatures(for: .cpu) ?? []
            let smcValues = Array(smcPowerReader?.readTemperatures(for: .cpu).values ?? Dictionary<String, Double>().values)
            snapshot.temperatures.cpu = temperatureSummary(hidValues.isEmpty ? smcValues : hidValues)
        }
        if request.includes(.thermalGPU) {
            let hidValues = hidTemperatureReader?.readTemperatures(for: .gpu) ?? []
            let smcValues = Array(smcPowerReader?.readTemperatures(for: .gpu).values ?? Dictionary<String, Double>().values)
            snapshot.temperatures.gpu = temperatureSummary(hidValues.isEmpty ? smcValues : hidValues)
        }
        if request.includes(.thermalMemory) {
            let values = Array(smcPowerReader?.readTemperatures(for: .memory).values ?? Dictionary<String, Double>().values)
            snapshot.temperatures.memory = temperatureSummary(values)
        }
        if request.includes(.thermalStorage) {
            let smcValues = Array(smcPowerReader?.readTemperatures(for: .nand).values ?? Dictionary<String, Double>().values)
            let hidValues = hidTemperatureReader?.readTemperatures(for: .nand) ?? []
            snapshot.temperatures.nandCelsius = (smcValues.isEmpty ? hidValues : smcValues).max()
        }
        if request.includes(.thermalBattery) {
            let smcValues = Array(smcPowerReader?.readTemperatures(for: .battery).values ?? Dictionary<String, Double>().values)
            let hidValues = hidTemperatureReader?.readTemperatures(for: .battery) ?? []
            snapshot.temperatures.battery = temperatureSummary(smcValues.isEmpty ? hidValues : smcValues)
        }
        if request.includes(.thermalAirflow) {
            let values = smcPowerReader?.readTemperatures(for: .airflow) ?? [:]
            snapshot.temperatures.airflowLeftCelsius = values["TaLP"]
            snapshot.temperatures.airflowRightCelsius = values["TaRF"]
        }
        if request.includes(.thermalWireless) {
            snapshot.temperatures.wirelessCelsius = smcPowerReader?
                .readTemperatures(for: .wireless)
                .values
                .max()
        }
        if request.includes(.thermalPMU) {
            let values = hidTemperatureReader?.readTemperatures(for: .powerManagement) ?? []
            snapshot.temperatures.powerManagement = temperatureSummary(values)
        }

        return snapshot
    }

    private func temperatureSummary(_ values: [Double]) -> TemperatureSummary? {
        guard let maximum = values.max(), !values.isEmpty else { return nil }
        return TemperatureSummary(
            averageCelsius: values.reduce(0, +) / Double(values.count),
            maximumCelsius: maximum,
            sensorCount: values.count
        )
    }

#if !APP_STORE
    private func smartBatteryProperties() -> [String: Any]? {
        guard let matching = IOServiceMatching("AppleSmartBattery") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &properties,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS else { return nil }
        return properties?.takeRetainedValue() as? [String: Any]
    }
#endif

    private func updateThermalState(at now: Date) {
        let current = ProcessInfo.processInfo.thermalState
        if current != thermalState {
            thermalState = current
            thermalStateSince = now
        }
    }

#if !APP_STORE
    private func readProcessesIfNeeded(at now: Date) -> ProcessRankings {
        if let previousProcessDate, now.timeIntervalSince(previousProcessDate) < 3 {
            return cachedRankings
        }

        var pids = [pid_t](repeating: 0, count: 4096)
        let byteCount = pids.withUnsafeMutableBytes { bytes in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, bytes.baseAddress, Int32(bytes.count))
        }
        guard byteCount > 0 else { return cachedRankings }

        let elapsed = previousProcessDate.map { now.timeIntervalSince($0) }
        let processCount = min(Int(byteCount) / MemoryLayout<pid_t>.size, pids.count)
        var currentCounters: [pid_t: ProcessCounters] = [:]
        var activities: [ProcessActivity] = []

        for pid in pids.prefix(processCount) where pid > 0 {
            guard let usage = processResourceUsage(pid) else { continue }
            let counters = ProcessCounters(
                cpuTime: usage.ri_user_time + usage.ri_system_time,
                wakeups: usage.ri_pkg_idle_wkups + usage.ri_interrupt_wkups,
                diskRead: usage.ri_diskio_bytesread,
                diskWrite: usage.ri_diskio_byteswritten
            )
            currentCounters[pid] = counters

            var activity = ProcessActivity(
                pid: pid,
                name: processName(pid),
                memoryBytes: usage.ri_phys_footprint
            )
            if let elapsed, elapsed > 0, let previous = previousProcessCounters[pid] {
                if counters.cpuTime >= previous.cpuTime {
                    activity.cpuUsage = processCPUAccounting.cpuUsage(
                        deltaTicks: counters.cpuTime - previous.cpuTime,
                        elapsedSeconds: elapsed
                    )
                }
                if counters.wakeups >= previous.wakeups {
                    activity.wakeupsPerSecond = Double(counters.wakeups - previous.wakeups) / elapsed
                }
                if counters.diskRead >= previous.diskRead {
                    activity.diskReadPerSecond = Double(counters.diskRead - previous.diskRead) / elapsed
                }
                if counters.diskWrite >= previous.diskWrite {
                    activity.diskWritePerSecond = Double(counters.diskWrite - previous.diskWrite) / elapsed
                }
            }
            activities.append(activity)
        }

        previousProcessCounters = currentCounters
        previousProcessDate = now
        cachedRankings = ProcessRankings(
            cpu: top(activities, by: { $0.cpuUsage }),
            wakeups: top(activities, by: { $0.wakeupsPerSecond }),
            memory: top(activities, by: { Double($0.memoryBytes) }),
            disk: top(activities, by: { $0.diskReadPerSecond + $0.diskWritePerSecond })
        )
        return cachedRankings
    }

    private func processResourceUsage(_ pid: pid_t) -> rusage_info_v4? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer -> Int32 in
            pointer.withMemoryRebound(to: Optional<rusage_info_t>.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage : nil
    }

    private func top(
        _ activities: [ProcessActivity],
        by value: (ProcessActivity) -> Double
    ) -> [ProcessActivity] {
        activities
            .filter { value($0) > 0 }
            .sorted { value($0) > value($1) }
            .prefix(5)
            .map { $0 }
    }

    private func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : "PID \(pid)"
    }
#endif
}

struct MemoryAccounting {
    let pageSize: UInt64
    let physicalMemory: UInt64

    func calculate(
        internalPages: UInt64,
        purgeablePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        externalPages: UInt64
    ) -> MemoryAccountingResult {
        let appPages = internalPages >= purgeablePages
            ? internalPages - purgeablePages
            : 0
        let app = bytes(for: appPages)
        let wired = bytes(for: wiredPages)
        let compressed = bytes(for: compressedPages)
        let cached = clampedSum([
            bytes(for: externalPages),
            bytes(for: purgeablePages)
        ])

        return MemoryAccountingResult(
            used: clampedSum([app, wired, compressed]),
            app: app,
            wired: wired,
            compressed: compressed,
            cached: cached
        )
    }

    private func bytes(for pages: UInt64) -> UInt64 {
        let (value, overflow) = pages.multipliedReportingOverflow(by: pageSize)
        return overflow ? physicalMemory : min(value, physicalMemory)
    }

    private func clampedSum(_ values: [UInt64]) -> UInt64 {
        values.reduce(0) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? physicalMemory : min(sum, physicalMemory)
        }
    }
}

struct MemoryAccountingResult {
    let used: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64
}

struct ProcessCPUAccounting {
    let nanosecondsPerTick: Double

    init(numer: UInt32, denom: UInt32) {
        nanosecondsPerTick = denom > 0
            ? Double(numer) / Double(denom)
            : 1
    }

    func cpuUsage(deltaTicks: UInt64, elapsedSeconds: TimeInterval) -> Double {
        guard elapsedSeconds > 0 else { return 0 }
        let elapsedCPUSeconds = Double(deltaTicks) * nanosecondsPerTick / 1_000_000_000
        return elapsedCPUSeconds / elapsedSeconds * 100
    }

    static func wholeMachineUsage(
        processUsage: Double,
        logicalProcessorCount: Int
    ) -> Double {
        guard processUsage.isFinite else { return 0 }
        let processorCount = max(logicalProcessorCount, 1)
        return min(max(processUsage / Double(processorCount), 0), 100)
    }

    static var current: ProcessCPUAccounting {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS else {
            return ProcessCPUAccounting(numer: 1, denom: 1)
        }
        return ProcessCPUAccounting(numer: timebase.numer, denom: timebase.denom)
    }
}

private struct CPUTicks {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
    var total: UInt64 { user + system + idle + nice }
}

private struct NetworkCounters {
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let receivedPackets: UInt64
    let sentPackets: UInt64
    let inputErrors: UInt64
    let outputErrors: UInt64
    let drops: UInt64
}

private struct NetworkCounterSample {
    let counters: NetworkCounters
    let date: Date
    let identity: String
}

private struct DiskCounters {
    var bytesRead: UInt64 = 0
    var bytesWritten: UInt64 = 0
    var readOperations: UInt64 = 0
    var writeOperations: UInt64 = 0
    let date: Date
}

private struct ProcessCounters {
    let cpuTime: UInt64
    let wakeups: UInt64
    let diskRead: UInt64
    let diskWrite: UInt64
}

private struct ProcessRankings {
    var cpu: [ProcessActivity] = []
    var wakeups: [ProcessActivity] = []
    var memory: [ProcessActivity] = []
    var disk: [ProcessActivity] = []
}

private final class NetworkLatencyProbe {
    private let queue = DispatchQueue(label: "com.xipiyoung.ColdHot.latency", qos: .utility)
    private let lock = NSLock()
    private var latestMilliseconds: Double?
    private var lastStarted: Date?
    private var activeConnection: NWConnection?

    func latestValue(startIfNeededAt now: Date) -> Double? {
        lock.lock()
        let shouldStart = activeConnection == nil
            && (lastStarted == nil || now.timeIntervalSince(lastStarted!) >= 10)
        if shouldStart { lastStarted = now }
        let value = latestMilliseconds
        lock.unlock()

        if shouldStart { start() }
        return value
    }

    private func start() {
        let started = DispatchTime.now()
        let connection = NWConnection(host: "1.1.1.1", port: 443, using: .tcp)
        lock.lock()
        activeConnection = connection
        lock.unlock()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                let elapsed = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
                self.finish(connection, latency: Double(elapsed) / 1_000_000)
            case .failed, .cancelled:
                self.finish(connection, latency: nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.finish(connection, latency: nil)
        }
    }

    private func finish(_ connection: NWConnection, latency: Double?) {
        lock.lock()
        guard activeConnection === connection else {
            lock.unlock()
            return
        }
        if let latency { latestMilliseconds = latency }
        activeConnection = nil
        lock.unlock()
        connection.cancel()
    }
}
