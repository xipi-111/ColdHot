import Foundation
import IOKit
import Darwin

enum SMCTemperatureGroup {
    case cpu
    case gpu
    case memory
    case nand
    case battery
    case airflow
    case wireless
}

struct SMCPowerReadings {
    var systemTotalWatts: Double?
    var dcInputWatts: Double?
    var batteryWatts: Double?

    var hasAnyValue: Bool {
        systemTotalWatts != nil || dcInputWatts != nil || batteryWatts != nil
    }
}

/// Read-only access to AppleSMC power sensors. These keys are private and may
/// not exist on every Mac, so callers must treat every value as optional.
#if APP_STORE
final class SMCPowerReader {
    init?() { return nil }
    func readPower() -> SMCPowerReadings? { nil }
    func readFans() -> [FanSnapshot] { [] }
    func readTemperatures(for group: SMCTemperatureGroup) -> [String: Double] { [:] }
}
#else
final class SMCPowerReader {
    private var connection: io_connect_t = 0
    private var keyInfoCache: [UInt32: SMCKeyInfo] = [:]
    private let chipFamily: AppleChipFamily

    init?() {
        chipFamily = Self.currentChipFamily()
        guard let matching = IOServiceMatching("AppleSMC") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return nil
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func readPower() -> SMCPowerReadings? {
        let readings = SMCPowerReadings(
            systemTotalWatts: sanitizedPower(readValue(for: "PSTR")),
            dcInputWatts: sanitizedPower(readValue(for: "PDTR")),
            batteryWatts: sanitizedPower(readValue(for: "PPBR"), acceptsNegative: true).map(abs)
        )
        return readings.hasAnyValue ? readings : nil
    }

    func readFans() -> [FanSnapshot] {
        let reportedCount = readValue(for: "FNum").map { Int($0.rounded()) }
        let fanCount = min(max(reportedCount ?? 0, 0), 16)
        guard fanCount > 0 else { return [] }

        return (0..<fanCount).compactMap { index in
            let hexadecimalIndex = String(index, radix: 16, uppercase: true)
            guard let speed = readValue(for: "F\(hexadecimalIndex)Ac"),
                  speed.isFinite,
                  speed >= 0,
                  speed < 20_000 else { return nil }
            return FanSnapshot(id: index, speedRPM: speed)
        }
    }

    func readTemperatures(for group: SMCTemperatureGroup) -> [String: Double] {
        temperatureKeys(for: group).reduce(into: [:]) { readings, key in
            guard let value = sanitizedTemperature(readValue(for: key)) else { return }
            readings[key] = value
        }
    }

    private func temperatureKeys(for group: SMCTemperatureGroup) -> [String] {
        switch group {
        case .cpu:
            switch chipFamily {
            case .m1:
                return ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
            case .m2:
                return ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
            case .m3:
                return ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
            case .m4:
                return ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
            case .m5:
                return ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K"]
            case .intel, .unknown:
                return ["TC0D", "TC0E", "TC0F", "TC0H", "TC0P", "TCAD"]
            }
        case .gpu:
            switch chipFamily {
            case .m1:
                return ["Tg05", "Tg0D", "Tg0L", "Tg0T"]
            case .m2:
                return ["Tg0f", "Tg0j"]
            case .m3:
                return ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]
            case .m4:
                return ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]
            case .m5:
                return ["Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"]
            case .intel, .unknown:
                return ["TG0D", "TGDD", "TG0H", "TG0P", "TCGC"]
            }
        case .memory:
            switch chipFamily {
            case .m1:
                return ["Tm02", "Tm06", "Tm08", "Tm09"]
            case .m4:
                return ["Tm0p", "Tm1p", "Tm2p"]
            default:
                return ["Tm0P"]
            }
        case .nand:
            return ["TH0x", "TH0A", "TH0B", "TH0C"]
        case .battery:
            return ["TB1T", "TB2T"]
        case .airflow:
            return ["TaLP", "TaRF"]
        case .wireless:
            return ["TW0P"]
        }
    }

    private func sanitizedTemperature(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 5, value <= 125 else { return nil }
        return value
    }

    private func sanitizedPower(_ value: Double?, acceptsNegative: Bool = false) -> Double? {
        guard let value, value.isFinite, abs(value) < 2_000 else { return nil }
        guard acceptsNegative || value >= 0 else { return nil }
        return value
    }

    private func readValue(for key: String) -> Double? {
        guard let code = fourCharacterCode(key) else { return nil }

        let info: SMCKeyInfo
        if let cached = keyInfoCache[code] {
            info = cached
        } else {
            var input = SMCKeyData()
            var output = SMCKeyData()
            input.key = code
            input.command = SMCCommand.readKeyInfo.rawValue
            guard call(input: &input, output: &output) == kIOReturnSuccess,
                  output.result == 0,
                  output.keyInfo.dataSize > 0,
                  output.keyInfo.dataSize <= 32 else { return nil }
            info = output.keyInfo
            keyInfoCache[code] = info
        }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = code
        input.keyInfo.dataSize = info.dataSize
        input.command = SMCCommand.readBytes.rawValue
        guard call(input: &input, output: &output) == kIOReturnSuccess,
              output.result == 0 else { return nil }

        let byteCount = Int(info.dataSize)
        let bytes = withUnsafeBytes(of: &output.bytes) { Array($0.prefix(byteCount)) }
        return decode(bytes: bytes, type: fourCharacterString(info.dataType))
    }

    private func decode(bytes: [UInt8], type: String) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(
                UInt32(bytes[0]) << 24
                    | UInt32(bytes[1]) << 16
                    | UInt32(bytes[2]) << 8
                    | UInt32(bytes[3])
            )
        default:
            return decodeFixedPoint(bytes: bytes, type: type)
        }
    }

    private func decodeFixedPoint(bytes: [UInt8], type: String) -> Double? {
        guard bytes.count >= 2, type.count == 4 else { return nil }
        let characters = Array(type)
        guard characters[0] == "s" || characters[0] == "f",
              characters[1] == "p",
              let fractionalBits = Int(String(characters[3]), radix: 16) else { return nil }

        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let scale = pow(2.0, Double(fractionalBits))
        if characters[0] == "s" {
            return Double(Int16(bitPattern: raw)) / scale
        }
        return Double(raw) / scale
    }

    private func call(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(
            connection,
            UInt32(SMCCommand.kernelIndex.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }

    private func fourCharacterCode(_ string: String) -> UInt32? {
        let bytes = Array(string.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func fourCharacterString(_ code: UInt32) -> String {
        String(bytes: [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ], encoding: .ascii) ?? ""
    }

    private static func currentChipFamily() -> AppleChipFamily {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return .unknown
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return .unknown
        }
        let name = String(cString: buffer)
        if name.contains("Apple M5") { return .m5 }
        if name.contains("Apple M4") { return .m4 }
        if name.contains("Apple M3") { return .m3 }
        if name.contains("Apple M2") { return .m2 }
        if name.contains("Apple M1") { return .m1 }
        if name.contains("Intel") { return .intel }
        return .unknown
    }
}

private enum AppleChipFamily {
    case m1
    case m2
    case m3
    case m4
    case m5
    case intel
    case unknown
}

private enum SMCCommand: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case readKeyInfo = 9
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memoryPLimit: UInt32 = 0
}

private struct SMCKeyInfo {
    var dataSize: IOByteCount32 = 0
    var dataType: UInt32 = 0
    var attributes: UInt8 = 0
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var command: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}
#endif
