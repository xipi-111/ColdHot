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
