import Foundation

@main
enum SamplingDemandCheck {
    static func main() {
        checkHiddenCadencesAndVisibleRefresh()
        checkThresholdSensorDemand()
        checkPartialSnapshotMerging()
        checkFanReaderIsDemandDriven()
        print("Sampling demand checks passed")
    }

    private static func checkHiddenCadencesAndVisibleRefresh() {
        let start = Date(timeIntervalSince1970: 1_000)
        var planner = SamplingCadencePlanner()
        let allMetrics = Set(MetricKind.allCases)
        let initial = planner.plan(
            now: start,
            panelVisible: false,
            sampleInterval: 2,
            enabledMetrics: allMetrics,
            enabledDetails: [],
            expandedMetric: nil,
            enabledThresholdKinds: []
        )
        expect(initial.request.enabledMetrics == allMetrics)
        expect(!initial.request.includesFans)

        let afterTwoSeconds = planner.plan(
            now: start.addingTimeInterval(2),
            panelVisible: false,
            sampleInterval: 2,
            enabledMetrics: allMetrics,
            enabledDetails: [],
            expandedMetric: nil,
            enabledThresholdKinds: []
        )
        expect(afterTwoSeconds.request.enabledMetrics == [.cpu, .memory, .network])

        let afterFiveSeconds = planner.plan(
            now: start.addingTimeInterval(5),
            panelVisible: false,
            sampleInterval: 2,
            enabledMetrics: allMetrics,
            enabledDetails: [],
            expandedMetric: nil,
            enabledThresholdKinds: []
        )
        expect(afterFiveSeconds.request.enabledMetrics.contains(.gpu))
        expect(afterFiveSeconds.request.enabledMetrics.contains(.disk))
        expect(afterFiveSeconds.request.enabledMetrics.contains(.thermal))
        expect(!afterFiveSeconds.request.enabledMetrics.contains(.battery))

        let visible = planner.plan(
            now: start.addingTimeInterval(6),
            panelVisible: true,
            sampleInterval: 2,
            enabledMetrics: allMetrics,
            enabledDetails: Set(MetricDetail.allCases),
            expandedMetric: .cpu,
            enabledThresholdKinds: []
        )
        expect(visible.request.enabledMetrics == allMetrics)
        expect(visible.request.includesFans)

        var batteryPlanner = SamplingCadencePlanner()
        _ = batteryPlanner.plan(
            now: start,
            panelVisible: false,
            sampleInterval: 2,
            enabledMetrics: [.battery],
            enabledDetails: [],
            expandedMetric: nil,
            enabledThresholdKinds: []
        )
        let batteryEarly = batteryPlanner.plan(
            now: start.addingTimeInterval(29),
            panelVisible: false,
            sampleInterval: 2,
            enabledMetrics: [.battery],
            enabledDetails: [],
            expandedMetric: nil,
            enabledThresholdKinds: []
        )
        expect(batteryEarly.request.enabledMetrics.isEmpty)
        let batteryDue = batteryPlanner.plan(
            now: start.addingTimeInterval(30),
            panelVisible: false,
            sampleInterval: 2,
            enabledMetrics: [.battery],
            enabledDetails: [],
            expandedMetric: nil,
            enabledThresholdKinds: []
        )
        expect(batteryDue.request.enabledMetrics == [.battery])
    }

    private static func checkThresholdSensorDemand() {
        let start = Date(timeIntervalSince1970: 2_000)
        var planner = SamplingCadencePlanner()
        let thresholds: Set<ThresholdMetric> = [.fanSpeed, .temperatureCPU, .systemPower]
        let initial = planner.plan(
            now: start,
            panelVisible: false,
            sampleInterval: 2,
            enabledMetrics: [],
            enabledDetails: [],
            expandedMetric: nil,
            enabledThresholdKinds: thresholds
        )
        expect(initial.request.includesFans)
        expect(initial.request.backgroundDetails.contains(.thermalCPU))
        expect(initial.request.backgroundDetails.contains(.batteryElectrical))
        expect(initial.evaluatedThresholdKinds == thresholds)

        let early = planner.plan(
            now: start.addingTimeInterval(2),
            panelVisible: false,
            sampleInterval: 2,
            enabledMetrics: [],
            enabledDetails: [],
            expandedMetric: nil,
            enabledThresholdKinds: thresholds
        )
        expect(!early.request.includesFans)
        expect(early.request.backgroundDetails.isEmpty)
        expect(early.evaluatedThresholdKinds.isEmpty)

        let due = planner.plan(
            now: start.addingTimeInterval(5),
            panelVisible: false,
            sampleInterval: 2,
            enabledMetrics: [],
            enabledDetails: [],
            expandedMetric: nil,
            enabledThresholdKinds: thresholds
        )
        expect(due.request.includesFans)
        expect(due.evaluatedThresholdKinds == thresholds)
    }

    private static func checkPartialSnapshotMerging() {
        var base = PerformanceSnapshot.empty
        base.cpu.usage = 11
        base.gpu.usage = 22
        base.fans = [FanSnapshot(id: 0, speedRPM: 1_900)]
        base.battery = BatterySnapshot(percentage: 55)
        var partial = PerformanceSnapshot.empty
        partial.cpu.usage = 44
        partial.gpu.usage = 99
        partial.fans = []
        partial.battery = nil
        let request = SamplingRequest(
            enabledMetrics: [.cpu],
            enabledDetails: [],
            expandedMetric: nil,
            backgroundMetrics: [],
            backgroundDetails: [],
            includesFans: false
        )
        let merged = base.merging(partial, request: request)
        expect(merged.cpu.usage == 44)
        expect(merged.gpu.usage == 22)
        expect(merged.fans.first?.speedRPM == 1_900)
        expect(merged.battery?.percentage == 55)
    }

    private static func checkFanReaderIsDemandDriven() {
        var readCount = 0
        let sampler = SystemSampler(fanReader: {
            readCount += 1
            return [FanSnapshot(id: 0, speedRPM: 2_100)]
        })
        let withoutFans = SamplingRequest(
            enabledMetrics: [],
            enabledDetails: [],
            expandedMetric: nil,
            backgroundMetrics: [],
            backgroundDetails: [],
            includesFans: false
        )
        let first = sampler.sample(request: withoutFans)
        expect(readCount == 0)
        expect(first.fans.isEmpty)

        let withFans = SamplingRequest(
            enabledMetrics: [],
            enabledDetails: [],
            expandedMetric: nil,
            backgroundMetrics: [],
            backgroundDetails: [],
            includesFans: true
        )
        let second = sampler.sample(request: withFans)
        expect(readCount == 1)
        expect(second.fans.first?.speedRPM == 2_100)
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError("Check failed", file: file, line: line)
        }
    }
}
