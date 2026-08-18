import Foundation

@main
enum HIDTemperatureOwnershipCheck {
    static func main() throws {
        let sourcePath = CommandLine.arguments.dropFirst().first
            ?? "ColdHot/Monitoring/HIDTemperatureReader.swift"
        let source = try String(contentsOfFile: sourcePath, encoding: .utf8)

        expect(source.contains("-> Unmanaged<HIDTemperatureEvent>?"))
        expect(source.contains("let retainedEvent = copyEvent(item.service, 15, 0, 0)"))
        expect(source.contains("let event = retainedEvent.takeRetainedValue()"))
        print("HID temperature ownership checks passed")
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
