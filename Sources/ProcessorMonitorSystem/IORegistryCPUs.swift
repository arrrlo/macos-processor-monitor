import Foundation
import IOKit
import ProcessorMonitorCore

/// Reads `IODeviceTree:/cpus/cpuN` — the only reliable source for which logical CPU belongs to which cluster.
public enum IORegistryCPUs {
    public static func read() -> [CPUDescriptor] {
        childProperties(path: "IODeviceTree:/cpus").compactMap(RegistryCPUParser.descriptor)
    }

    static func childProperties(path: String) -> [[String: Any]] {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return [] }
        defer { IOObjectRelease(entry) }
        var iterator: io_iterator_t = 0
        IORegistryEntryGetChildIterator(entry, kIODeviceTreePlane, &iterator)
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        var child = IOIteratorNext(iterator)
        while child != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            IORegistryEntryCreateCFProperties(child, &properties, kCFAllocatorDefault, 0)
            if let dictionary = properties?.takeRetainedValue() as? [String: Any] {
                result.append(dictionary)
            }
            IOObjectRelease(child)
            child = IOIteratorNext(iterator)
        }
        return result
    }
}

enum RegistryCPUParser {
    static func descriptor(from properties: [String: Any]) -> CPUDescriptor? {
        guard let id = properties["logical-cpu-id"] as? NSNumber,
              let data = properties["cluster-type"] as? Data else { return nil }
        let type = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        guard !type.isEmpty else { return nil }
        return CPUDescriptor(logicalID: id.intValue, clusterType: type)
    }
}
