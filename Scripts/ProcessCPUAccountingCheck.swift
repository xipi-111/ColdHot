import Foundation

@main
enum ProcessCPUAccountingCheck {
    static func main() {
        let accounting = ProcessCPUAccounting(numer: 125, denom: 3)
        let usage = accounting.cpuUsage(
            deltaTicks: 8_712_000,
            elapsedSeconds: 1
        )

        expect(abs(usage - 36.3) < 0.001)

        let wholeMachineUsage = ProcessCPUAccounting.wholeMachineUsage(
            processUsage: usage,
            logicalProcessorCount: 14
        )
        expect(abs(wholeMachineUsage - (36.3 / 14)) < 0.001)
        expect(
            abs(
                ProcessCPUAccounting.wholeMachineUsage(
                    processUsage: 400,
                    logicalProcessorCount: 14
                ) - (400.0 / 14)
            ) < 0.001
        )
        expect(
            ProcessCPUAccounting.wholeMachineUsage(
                processUsage: 1_600,
                logicalProcessorCount: 14
            ) == 100
        )
        expect(
            ProcessCPUAccounting.wholeMachineUsage(
                processUsage: .nan,
                logicalProcessorCount: 14
            ) == 0
        )
        expect(
            ProcessCPUAccounting.wholeMachineUsage(
                processUsage: 36.3,
                logicalProcessorCount: 0
            ) == 36.3
        )
        print("Process CPU accounting checks passed")
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
