import CSystemShims
import Foundation
import IOKit
import ProcessorMonitorCore

/// The AppleSMC commands the app sends. All of them read: the app never writes to the SMC.
enum SMCCommand: UInt8 {
    case read = 5
    case keyAtIndex = 8
    case keyInfo = 9
}

/// SMC keys are four-character codes such as `Tg0C`, stored as big-endian integers.
enum SMCKey {
    /// Names shorter than four characters are padded with NULs, so `code("Tg")` sorts before every `Tg` key.
    static func code(_ name: String) -> UInt32 {
        (Array(name.utf8) + [0, 0, 0, 0]).prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func name(_ code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, as: UTF8.self)
    }
}

/// One call into the AppleSMC user client, so tests can stand in for the SMC a VM does not have.
struct SMCAccess: Sendable {
    let call: @Sendable (SMCParamStruct) -> (kern_return_t, SMCParamStruct)
}

extension SMCAccess {
    /// Selector of the user client's only method (`kSMCHandleYPCEvent`).
    static let selector: UInt32 = 2

    /// One connection for the process lifetime, like the HID client; 0 when there is no SMC, so every call fails.
    static let connection = open(IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC")))

    /// Opens a connection to `service`, then releases the service, which the connection no longer needs.
    static func open(_ service: io_service_t) -> io_connect_t {
        var connection: io_connect_t = 0
        IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        return connection
    }

    static let live = SMCAccess { input in
        var input = input
        var output = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = inputSize
        let status = IOConnectCallStructMethod(connection, selector, &input, inputSize, &output, &outputSize)
        return (status, output)
    }
}

/// Reads SMC keys. Each read is one call into the SMC firmware, about 0.02 ms of CPU.
struct SMCClient: Sendable {
    let access: SMCAccess

    /// The SMC's answer, or nil when the call fails or the SMC reports an error (e.g. an unknown key).
    func call(_ command: SMCCommand, key: UInt32 = 0, index: UInt32 = 0, size: UInt32 = 0) -> SMCParamStruct? {
        var input = SMCParamStruct()
        input.data8 = command.rawValue
        input.key = key
        input.data32 = index
        input.keyInfo.dataSize = size
        let (status, output) = access.call(input)
        guard status == KERN_SUCCESS, output.result == 0 else { return nil }
        return output
    }

    /// How many keys the SMC has (`#KEY`, a big-endian `ui32`); 0 without an SMC.
    var keyCount: UInt32 {
        guard let output = call(.read, key: SMCKey.code("#KEY"), size: 4) else { return 0 }
        return UInt32(bigEndian: withUnsafeBytes(of: output.bytes) { $0.loadUnaligned(as: UInt32.self) })
    }

    func key(at index: UInt32) -> UInt32? {
        call(.keyAtIndex, index: index)?.key
    }

    func info(of key: UInt32) -> SMCKeyInfo? {
        call(.keyInfo, key: key)?.keyInfo
    }

    /// A 4-byte `flt ` value, which the SMC stores in the CPU's (little-endian) byte order.
    func readFloat(_ key: UInt32) -> Double? {
        guard let output = call(.read, key: key, size: 4) else { return nil }
        return Double(withUnsafeBytes(of: output.bytes) { $0.loadUnaligned(as: Float.self) })
    }
}

public enum SMCTemperatureSensors {
    /// The 4-byte `flt ` sensors whose keys fall in `codes`. The SMC lists its keys in sorted order, so two
    /// binary searches find the range in about 25 calls instead of reading all ~3700 keys (0.7 s on an M5 Max).
    static func discover(in codes: Range<UInt32>, using client: SMCClient) -> [TemperatureSensor] {
        let count = client.keyCount
        let indices = firstIndex(atLeast: codes.lowerBound, of: count, using: client)..<firstIndex(atLeast: codes.upperBound, of: count, using: client)
        return indices.compactMap { index in
            guard let key = client.key(at: index), codes.contains(key), isFloat(client.info(of: key)) else { return nil }
            return TemperatureSensor(name: SMCKey.name(key)) { client.readFloat(key) }
        }
    }

    /// The first of `count` sorted keys that is not below `code`; `count` when there is none.
    static func firstIndex(atLeast code: UInt32, of count: UInt32, using client: SMCClient) -> UInt32 {
        var low: UInt32 = 0
        var high = count
        while low < high {
            let middle = low + (high - low) / 2
            if let key = client.key(at: middle), key < code {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    static func isFloat(_ info: SMCKeyInfo?) -> Bool {
        info?.dataType == SMCKey.code("flt ") && info?.dataSize == 4
    }
}

/// Reads the GPU sensors chosen once at construction.
public struct GPUTemperatureReader: Sendable {
    private let sensors: [TemperatureSensor]

    public init(sensors: [TemperatureSensor]) {
        self.sensors = GPUTemperatureSensors.select(count: sensors.count).map { sensors[$0] }
    }

    /// The SMC's `Tg*` keys, which hold the GPU temperatures on M1 through M5.
    public static func live() -> GPUTemperatureReader {
        GPUTemperatureReader(sensors: SMCTemperatureSensors.discover(in: SMCKey.code("Tg")..<SMCKey.code("Th"), using: SMCClient(access: .live)))
    }

    public var sensorNames: [String] { sensors.map(\.name) }

    public func read() -> TemperatureSummary? {
        TemperatureAggregator.summarize(sensors.compactMap { $0.read() })
    }
}
