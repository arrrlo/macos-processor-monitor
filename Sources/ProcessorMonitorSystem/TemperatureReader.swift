import CSystemShims
import Foundation
import IOKit.hidsystem
import ProcessorMonitorCore

/// The few calls into the private HID event system that temperature reading needs.
enum HIDEventSystem {
    static let temperatureEventType: Int64 = 15
    static let temperatureField = Int32(temperatureEventType << 16)

    /// One client for the process lifetime; services are only valid while it lives.
    nonisolated(unsafe) static let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)

    static func services() -> [IOHIDServiceClient] {
        var services: [IOHIDServiceClient] = []
        if let copied = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] {
            services = copied
        }
        return services
    }

    static func intProperty(_ service: IOHIDServiceClient, _ key: String) -> Int? {
        IOHIDServiceClientCopyProperty(service, key as CFString) as? Int
    }

    static func stringProperty(_ service: IOHIDServiceClient, _ key: String) -> String? {
        IOHIDServiceClientCopyProperty(service, key as CFString) as? String
    }

    static func temperature(of service: IOHIDServiceClient) -> Double? {
        var celsius: Double?
        if let event = IOHIDServiceClientCopyEvent(service, temperatureEventType, 0, 0) {
            celsius = IOHIDEventGetFloatValue(event, temperatureField)
        }
        return celsius
    }
}

/// A named sensor with a way to read it now.
public struct TemperatureSensor: Sendable {
    public let name: String
    let read: @Sendable () -> Double?

    public init(name: String, read: @escaping @Sendable () -> Double?) {
        self.name = name
        self.read = read
    }
}

public enum HIDTemperatureSensors {
    /// Apple's vendor usage page and the temperature usage.
    static func isTemperatureService(usagePage: Int?, usage: Int?) -> Bool {
        usagePage == 0xff00 && usage == 5
    }

    /// Every temperature service with its product name. Enumerating is the expensive part, so do it once.
    public static func discover() -> [TemperatureSensor] {
        HIDEventSystem.services().compactMap { service in
            let page = HIDEventSystem.intProperty(service, "PrimaryUsagePage")
            let usage = HIDEventSystem.intProperty(service, "PrimaryUsage")
            guard isTemperatureService(usagePage: page, usage: usage),
                  let name = HIDEventSystem.stringProperty(service, "Product") else { return nil }
            nonisolated(unsafe) let handle = service
            return TemperatureSensor(name: name) { HIDEventSystem.temperature(of: handle) }
        }
    }
}

/// Reads the CPU sensors chosen once at construction.
public struct CPUTemperatureReader: Sendable {
    private let sensors: [TemperatureSensor]

    public init(sensors: [TemperatureSensor]) {
        self.sensors = CPUTemperatureSensors.select(sensors.map(\.name)).map { sensors[$0] }
    }

    public static func live() -> CPUTemperatureReader {
        CPUTemperatureReader(sensors: HIDTemperatureSensors.discover())
    }

    public var sensorNames: [String] { sensors.map(\.name) }

    public func read() -> TemperatureSummary? {
        TemperatureAggregator.summarize(sensors.compactMap { $0.read() })
    }
}
