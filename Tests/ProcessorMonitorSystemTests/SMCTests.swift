import CSystemShims
import Foundation
import IOKit
import Testing
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorSystem

/// An SMC with a sorted key table, answering the three read commands the app sends.
final class FakeSMC: @unchecked Sendable {
    struct Key {
        let name: String
        var type = "flt "
        var size: UInt32 = 4
        var value: Float = 0
    }

    var keys: [Key]
    var status = KERN_SUCCESS
    private(set) var inputs: [SMCParamStruct] = []

    init(_ keys: [Key]) {
        self.keys = keys.sorted { SMCKey.code($0.name) < SMCKey.code($1.name) }
    }

    /// A table of `Tg` keys between neighbours, plus keys that must be skipped.
    static func gpu(_ values: [Float]) -> FakeSMC {
        FakeSMC([Key(name: "#KEY", type: "ui32"), Key(name: "TaLP", value: 40), Key(name: "Tf14", value: 43)]
            + values.enumerated().map { Key(name: String(format: "Tg%02d", $0.offset), value: $0.element) }
            + [Key(name: "Th0x", value: 38), Key(name: "Tm00", value: 44)])
    }

    var keyAtCalls: Int { inputs.filter { $0.data8 == SMCCommand.keyAtIndex.rawValue }.count }

    var access: SMCAccess {
        SMCAccess { input in
            self.inputs.append(input)
            return (self.status, self.answer(input))
        }
    }

    private func answer(_ input: SMCParamStruct) -> SMCParamStruct {
        var output = SMCParamStruct()
        output.result = 0x84 // key not found
        switch input.data8 {
        case SMCCommand.keyAtIndex.rawValue where Int(input.data32) < keys.count:
            output.key = SMCKey.code(keys[Int(input.data32)].name)
            output.result = 0
        case SMCCommand.keyInfo.rawValue:
            if let key = keys.first(where: { SMCKey.code($0.name) == input.key }) {
                output.keyInfo.dataSize = key.size
                output.keyInfo.dataType = SMCKey.code(key.type)
                output.result = 0
            }
        case SMCCommand.read.rawValue where input.key == SMCKey.code("#KEY"):
            withUnsafeMutableBytes(of: &output.bytes) { $0.storeBytes(of: UInt32(keys.count).bigEndian, as: UInt32.self) }
            output.result = 0
        case SMCCommand.read.rawValue:
            if let key = keys.first(where: { SMCKey.code($0.name) == input.key }) {
                withUnsafeMutableBytes(of: &output.bytes) { $0.storeBytes(of: key.value, as: Float.self) }
                output.result = 0
            }
        default:
            break
        }
        return output
    }
}

extension FakeSMC {
    /// `count` (up to 17576) filler keys "AAAA", "AAAB", … that sort before every `T` key, to make
    /// the table as long as a real one.
    static func filler(_ count: Int) -> [Key] {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return (0..<count).map { Key(name: String(["A", letters[$0 / 676], letters[$0 / 26 % 26], letters[$0 % 26]])) }
    }
}

@Suite struct SMCKeyTests {
    @Test func namesAreFourCharacterCodes() {
        #expect(SMCKey.code("Tg0C") == 0x5467_3043)
        #expect(SMCKey.name(0x5467_3043) == "Tg0C")
        #expect(SMCKey.code("flt ") == 0x666C_7420)
    }

    @Test func shortNamesSortBeforeEveryKeyTheyPrefix() {
        #expect(SMCKey.code("Tg") == 0x5467_0000)
        #expect(SMCKey.code("Tg") < SMCKey.code("Tg00"))
        #expect(SMCKey.code("Th") > SMCKey.code("Tgzz"))
    }
}

@Suite struct SMCClientTests {
    @Test func listsKeysByIndex() throws {
        let smc = FakeSMC.gpu([42])
        let client = SMCClient(access: smc.access)
        #expect(client.key(at: 3) == SMCKey.code("Tg00"))
        let input = try #require(smc.inputs.last)
        #expect(input.data8 == 8)
        #expect(input.data32 == 3)
        #expect(client.key(at: 99) == nil)
    }

    @Test func failedCallsAndSMCErrorsReadNothing() {
        let smc = FakeSMC.gpu([42])
        let client = SMCClient(access: smc.access)
        #expect(client.readFloat(SMCKey.code("Tz99")) == nil)
        smc.status = kIOReturnNotPrivileged
        #expect(client.key(at: 3) == nil)
        #expect(client.keyCount == 0)
    }

    @Test func readsTheKeyCountAsBigEndian() throws {
        let smc = FakeSMC(FakeSMC.filler(300) + [FakeSMC.Key(name: "#KEY", type: "ui32")])
        let client = SMCClient(access: smc.access)
        #expect(client.keyCount == 301)
        let input = try #require(smc.inputs.last)
        #expect(input.data8 == 5)
        #expect(input.key == SMCKey.code("#KEY"))
        #expect(input.keyInfo.dataSize == 4)
    }

    @Test func readsKeyInfo() throws {
        let smc = FakeSMC([FakeSMC.Key(name: "TB0T", type: "ui16", size: 2)])
        let info = try #require(SMCClient(access: smc.access).info(of: SMCKey.code("TB0T")))
        #expect(info.dataType == SMCKey.code("ui16"))
        #expect(info.dataSize == 2)
        let input = try #require(smc.inputs.last)
        #expect(input.data8 == 9)
        #expect(input.key == SMCKey.code("TB0T"))
    }

    @Test func readsFloatsInTheCPUByteOrder() throws {
        let smc = FakeSMC.gpu([41.5])
        #expect(SMCClient(access: smc.access).readFloat(SMCKey.code("Tg00")) == 41.5)
        let input = try #require(smc.inputs.last)
        #expect(input.data8 == 5)
        #expect(input.key == SMCKey.code("Tg00"))
        #expect(input.keyInfo.dataSize == 4)
    }
}

@Suite struct SMCTemperatureSensorsTests {
    let gpu = SMCKey.code("Tg")..<SMCKey.code("Th")

    func names(_ smc: FakeSMC) -> [String] {
        SMCTemperatureSensors.discover(in: gpu, using: SMCClient(access: smc.access)).map(\.name)
    }

    @Test func findsTheFloatSensorsInTheRangeAndReadsThem() {
        let smc = FakeSMC.gpu([41, 42.5, 43])
        let sensors = SMCTemperatureSensors.discover(in: gpu, using: SMCClient(access: smc.access))
        #expect(sensors.map(\.name) == ["Tg00", "Tg01", "Tg02"])
        #expect(sensors.map { $0.read() } == [41, 42.5, 43])
    }

    @Test func skipsKeysThatAreNotFourByteFloats() {
        let smc = FakeSMC.gpu([41, 42])
        smc.keys.insert(FakeSMC.Key(name: "Tg01", type: "ui32"), at: 4)
        smc.keys.insert(FakeSMC.Key(name: "Tg02", type: "flt ", size: 2), at: 5)
        smc.keys[6] = FakeSMC.Key(name: "Tg03", value: 42)
        #expect(names(smc) == ["Tg00", "Tg03"])
    }

    @Test func findsRangesAtEitherEndOfTheTable() {
        #expect(names(FakeSMC([FakeSMC.Key(name: "Tg00"), FakeSMC.Key(name: "Tg01"), FakeSMC.Key(name: "Th00")])) == ["Tg00", "Tg01"])
        #expect(names(FakeSMC([FakeSMC.Key(name: "#KEY", type: "ui32"), FakeSMC.Key(name: "Tf00"), FakeSMC.Key(name: "Tg00")])) == ["Tg00"])
        #expect(names(FakeSMC([FakeSMC.Key(name: "Tg00")])) == ["Tg00"])
    }

    @Test func aKeyEqualToTheLowerBoundIsIncluded() {
        let smc = FakeSMC([FakeSMC.Key(name: "#KEY", type: "ui32"), FakeSMC.Key(name: "Tf99"), FakeSMC.Key(name: "Tg"), FakeSMC.Key(name: "Tg00")])
        #expect(names(smc) == ["Tg\0\0", "Tg00"])
    }

    @Test func findsNothingWithoutMatchingKeysOrWithoutAnSMC() {
        #expect(names(FakeSMC([FakeSMC.Key(name: "#KEY", type: "ui32"), FakeSMC.Key(name: "Tf00"), FakeSMC.Key(name: "Th00")])).isEmpty)
        let missing = FakeSMC.gpu([41])
        missing.status = kIOReturnNotFound
        #expect(names(missing).isEmpty)
    }

    /// Two binary searches instead of a scan of every key: a real table has about 3700.
    @Test func searchesInsteadOfScanning() {
        let smc = FakeSMC.gpu([41, 42, 43])
        smc.keys.insert(contentsOf: FakeSMC.filler(4000), at: 1)
        #expect(names(smc) == ["Tg00", "Tg01", "Tg02"])
        #expect(smc.keyAtCalls <= 2 * 13 + 3)
    }

    @Test func firstIndexIsTheFirstKeyNotBelowTheCode() {
        let smc = FakeSMC([FakeSMC.Key(name: "Ta00"), FakeSMC.Key(name: "Tb00"), FakeSMC.Key(name: "Tc00")])
        let client = SMCClient(access: smc.access)
        func index(_ name: String) -> UInt32 { SMCTemperatureSensors.firstIndex(atLeast: SMCKey.code(name), of: 3, using: client) }
        #expect(index("T") == 0)
        #expect(index("Ta00") == 0)
        #expect(index("Ta01") == 1)
        #expect(index("Tb00") == 1)
        #expect(index("Tc00") == 2)
        #expect(index("Tz") == 3)
    }
}

@Suite struct GPUTemperatureReaderTests {
    @Test func readsAnEvenSampleOfTheSensors() {
        let sensors = (0..<16).map { index in TemperatureSensor(name: "Tg\(index)") { Double(40 + index) } }
        let reader = GPUTemperatureReader(sensors: sensors)
        #expect(reader.sensorNames == ["Tg0", "Tg2", "Tg4", "Tg6", "Tg8", "Tg10", "Tg12", "Tg14"])
        #expect(reader.read() == TemperatureSummary(average: 47, maximum: 54, sensorCount: 8))
    }

    @Test func unusedSensorsReadingZeroAreDropped() {
        let reader = GPUTemperatureReader(sensors: [TemperatureSensor(name: "Tg00") { 0 }, TemperatureSensor(name: "Tg01") { 42 }])
        #expect(reader.read() == TemperatureSummary(average: 42, maximum: 42, sensorCount: 1))
        #expect(GPUTemperatureReader(sensors: []).read() == nil)
    }
}

/// Serialized: the retain-count test must not overlap other uses of the AppleSMC service.
@Suite(.serialized) struct LiveSMCTests {
    func smcService() -> io_service_t {
        IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
    }

    @Test func connectionIsOpenWhereverThereIsAnSMC() {
        let service = smcService()
        #expect((SMCAccess.connection != 0) == (service != 0))
        IOObjectRelease(service)
    }

    @Test func openingReleasesTheService() {
        _ = SMCAccess.connection // the one-time lookup is done before counting
        let service = smcService()
        guard service != 0 else { return } // a VM without an SMC
        let extra = smcService()
        let before = IOObjectGetUserRetainCount(service)
        IOServiceClose(SMCAccess.open(extra))
        #expect(IOObjectGetUserRetainCount(service) == before - 1)
        IOObjectRelease(service)
    }

    /// Every Apple Silicon GPU has `Tg*` SMC sensors; a VM has neither a GPU entry nor the sensors.
    @Test func gpuSensorsAreTgKeysOnMacsWithAGPU() {
        let reader = GPUTemperatureReader.live()
        guard GPUReader().read() != nil else { return }
        #expect(!reader.sensorNames.isEmpty)
        #expect(reader.sensorNames.count <= 8)
        #expect(reader.sensorNames.allSatisfy { $0.hasPrefix("Tg") })
        if let summary = reader.read() {
            #expect(TemperatureAggregator.isValid(summary.average))
        }
    }
}
