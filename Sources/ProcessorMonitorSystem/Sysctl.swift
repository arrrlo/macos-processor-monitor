import Darwin

public enum Sysctl {
    /// A 32- or 64-bit integer value; `nil` if the name is unknown or has another width.
    public static func int(_ name: String) -> Int? {
        var buffer: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        switch size {
        case MemoryLayout<Int32>.size: return Int(Int32(truncatingIfNeeded: buffer))
        case MemoryLayout<Int64>.size: return Int(buffer)
        default: return nil
        }
    }

    public static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        sysctlbyname(name, &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
