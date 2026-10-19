import Testing
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorSystem

@Suite struct HIDEventSystemTests {
    @Test func listsServices() {
        // Every Mac (and VM) exposes some HID services, e.g. keyboards.
        #expect(!HIDEventSystem.services().isEmpty)
    }

    @Test func readsPropertiesAndEventsOfArbitraryServices() throws {
        let service = try #require(HIDEventSystem.services().first)
        _ = HIDEventSystem.intProperty(service, "PrimaryUsagePage")
        _ = HIDEventSystem.stringProperty(service, "Product")
        _ = HIDEventSystem.temperature(of: service)
    }

    @Test func missingPropertiesAreNil() throws {
        let service = try #require(HIDEventSystem.services().first)
        #expect(HIDEventSystem.intProperty(service, "NoSuchProperty") == nil)
        #expect(HIDEventSystem.stringProperty(service, "NoSuchProperty") == nil)
    }

    @Test func identifiesTemperatureServicesByUsage() {
        #expect(HIDTemperatureSensors.isTemperatureService(usagePage: 0xff00, usage: 5))
        #expect(!HIDTemperatureSensors.isTemperatureService(usagePage: 0xff00, usage: 4))
        #expect(!HIDTemperatureSensors.isTemperatureService(usagePage: 0x01, usage: 5))
        #expect(!HIDTemperatureSensors.isTemperatureService(usagePage: nil, usage: nil))
    }

    @Test func liveSensorsReportPlausibleTemperatures() {
        // Real Apple Silicon hardware has die sensors; VMs have none.
        for sensor in HIDTemperatureSensors.discover() where sensor.name.hasPrefix("PMU tdie") {
            let celsius = sensor.read()
            #expect(celsius.map { $0 > 5 && $0 < 120 } != false, "\(sensor.name) read \(String(describing: celsius))")
        }
    }
}

@Suite struct CPUTemperatureReaderTests {
    func sensor(_ name: String, _ value: Double?) -> TemperatureSensor {
        TemperatureSensor(name: name) { value }
    }

    @Test func summarisesOnlyCPUSensors() throws {
        let reader = CPUTemperatureReader(sensors: [
            sensor("PMU tdie1", 50),
            sensor("PMU tdev1", -9201),
            sensor("PMU tdie2", 60),
            sensor("PMU tdie3", nil),
            sensor("NAND CH0 temp", 90),
        ])
        #expect(reader.sensorNames == ["PMU tdie1", "PMU tdie2", "PMU tdie3"])
        #expect(reader.read() == TemperatureSummary(average: 55, maximum: 60, sensorCount: 2))
    }

    @Test func withoutSensorsThereIsNoTemperature() {
        let reader = CPUTemperatureReader(sensors: [sensor("NAND CH0 temp", 40)])
        #expect(reader.sensorNames.isEmpty)
        #expect(reader.read() == nil)
    }

    @Test func liveReaderMatchesHardware() {
        let reader = CPUTemperatureReader.live()
        if reader.sensorNames.isEmpty {
            #expect(reader.read() == nil)
        } else {
            #expect(reader.read() != nil)
        }
    }
}
