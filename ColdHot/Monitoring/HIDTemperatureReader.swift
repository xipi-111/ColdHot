import Foundation
import IOKit.hidsystem

enum HIDTemperatureGroup {
    case cpu
    case gpu
    case nand
    case battery
    case powerManagement
}

/// Read-only access to Apple Silicon temperature services exposed through IOHID.
/// Symbols that are not part of the public SDK are resolved dynamically so an
/// unsupported macOS release fails gracefully instead of preventing launch.
#if APP_STORE
final class HIDTemperatureReader {
    init?() { return nil }
    func readTemperatures(for group: HIDTemperatureGroup) -> [Double] { [] }
}
#else
final class HIDTemperatureReader {
    private let frameworkHandle: UnsafeMutableRawPointer
    private let client: IOHIDEventSystemClient
    private let copyEvent: HIDServiceCopyEvent
    private let getFloatValue: HIDEventGetFloatValue
    private let services: [NamedHIDTemperatureService]

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let createSymbol = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let matchingSymbol = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let eventSymbol = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let valueSymbol = dlsym(handle, "IOHIDEventGetFloatValue"),
              let propertySymbol = dlsym(handle, "IOHIDServiceClientCopyProperty") else {
            return nil
        }

        let createClient = unsafeBitCast(createSymbol, to: HIDClientCreate.self)
        let setMatching = unsafeBitCast(matchingSymbol, to: HIDClientSetMatching.self)
        let copyEvent = unsafeBitCast(eventSymbol, to: HIDServiceCopyEvent.self)
        let getFloatValue = unsafeBitCast(valueSymbol, to: HIDEventGetFloatValue.self)
        let copyProperty = unsafeBitCast(propertySymbol, to: HIDServiceCopyProperty.self)

        guard let client = createClient(kCFAllocatorDefault) else {
            dlclose(handle)
            return nil
        }
        setMatching(client, ["PrimaryUsage": 5, "PrimaryUsagePage": 65_280] as CFDictionary)
        guard let rawServices = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            dlclose(handle)
            return nil
        }

        let services = rawServices.compactMap { service -> NamedHIDTemperatureService? in
            guard let name = copyProperty(service, "Product" as CFString) as? String else { return nil }
            return NamedHIDTemperatureService(name: name, service: service)
        }

        frameworkHandle = handle
        self.client = client
        self.copyEvent = copyEvent
        self.getFloatValue = getFloatValue
        self.services = services
    }

    deinit {
        _ = client
        dlclose(frameworkHandle)
    }

    func readTemperatures(for group: HIDTemperatureGroup) -> [Double] {
        services.compactMap { item in
            guard matches(item.name, group: group),
                  let event = copyEvent(item.service, 15, 0, 0) else { return nil }
            let value = getFloatValue(event, 983_040)
            guard value.isFinite, value >= 5, value <= 125 else { return nil }
            return value
        }
    }

    private func matches(_ name: String, group: HIDTemperatureGroup) -> Bool {
        switch group {
        case .cpu:
            return name.hasPrefix("pACC MTR Temp Sensor") || name.hasPrefix("eACC MTR Temp Sensor")
        case .gpu:
            return name.hasPrefix("GPU MTR Temp Sensor")
        case .nand:
            return name.hasPrefix("NAND CH") && name.localizedCaseInsensitiveContains("temp")
        case .battery:
            return name == "gas gauge battery"
        case .powerManagement:
            return name.hasPrefix("PMU tdie") || name.hasPrefix("PMGR SOC Die Temp Sensor")
        }
    }
}

private struct NamedHIDTemperatureService {
    let name: String
    let service: IOHIDServiceClient
}

@objc private protocol HIDTemperatureEvent: NSObjectProtocol {}

private typealias HIDClientCreate = @convention(c) (CFAllocator?) -> IOHIDEventSystemClient?
private typealias HIDClientSetMatching = @convention(c) (IOHIDEventSystemClient?, CFDictionary?) -> Void
private typealias HIDServiceCopyEvent = @convention(c) (IOHIDServiceClient?, Int64, Int32, Int64) -> HIDTemperatureEvent?
private typealias HIDEventGetFloatValue = @convention(c) (HIDTemperatureEvent?, UInt32) -> Double
private typealias HIDServiceCopyProperty = @convention(c) (IOHIDServiceClient?, CFString?) -> CFTypeRef?
#endif
