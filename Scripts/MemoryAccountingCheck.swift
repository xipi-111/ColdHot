import Foundation

@main
enum MemoryAccountingCheck {
    private static let gibibyte = Double(1 << 30)

    static func main() {
        checkActivityMonitorAccounting()
        checkBounds()
        print("Memory accounting checks passed")
    }

    private static func checkActivityMonitorAccounting() {
        let pageSize: UInt64 = 16_384
        let total = UInt64(48 * gibibyte)
        let purgeablePages = pages(forGiB: 0.70, pageSize: pageSize)
        let accounting = MemoryAccounting(
            pageSize: pageSize,
            physicalMemory: total
        )
        let result = accounting.calculate(
            internalPages: pages(forGiB: 15.86, pageSize: pageSize) + purgeablePages,
            purgeablePages: purgeablePages,
            wiredPages: pages(forGiB: 5.03, pageSize: pageSize),
            compressedPages: pages(forGiB: 13.45, pageSize: pageSize),
            externalPages: pages(forGiB: 10.00, pageSize: pageSize)
        )

        expect(abs(gibibytes(result.app) - 15.86) < 0.01)
        expect(abs(gibibytes(result.wired) - 5.03) < 0.01)
        expect(abs(gibibytes(result.compressed) - 13.45) < 0.01)
        expect(abs(gibibytes(result.cached) - 10.70) < 0.01)
        expect(abs(gibibytes(result.used) - 34.34) < 0.01)
        expect(abs(Double(result.used) / Double(total) * 100 - 71.5) < 0.1)

        let freePages = pages(forGiB: 2.57, pageSize: pageSize)
        let speculativePages = pages(forGiB: 0.45, pageSize: pageSize)
        let legacyAvailable = (freePages + speculativePages) * pageSize
        let legacyUsed = total - legacyAvailable
        expect(abs(Double(legacyUsed) / Double(total) * 100 - 93.7) < 0.1)
    }

    private static func checkBounds() {
        let accounting = MemoryAccounting(pageSize: 16_384, physicalMemory: 1 << 30)
        let result = accounting.calculate(
            internalPages: .max,
            purgeablePages: 0,
            wiredPages: .max,
            compressedPages: .max,
            externalPages: .max
        )

        expect(result.used == 1 << 30)
        expect(result.cached == 1 << 30)
    }

    private static func pages(forGiB value: Double, pageSize: UInt64) -> UInt64 {
        UInt64((value * gibibyte / Double(pageSize)).rounded())
    }

    private static func gibibytes(_ bytes: UInt64) -> Double {
        Double(bytes) / gibibyte
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
