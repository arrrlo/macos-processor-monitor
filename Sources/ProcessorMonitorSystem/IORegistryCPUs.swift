import Foundation
import IOKit
import ProcessorMonitorCore

/// The IOKit registry calls the traversal needs, so tests can check every object is released.
struct RegistryAccess: Sendable {
    let entry: @Sendable (String) -> io_registry_entry_t
    let childIterator: @Sendable (io_registry_entry_t) -> io_iterator_t
    let next: @Sendable (io_iterator_t) -> io_object_t
    let properties: @Sendable (io_registry_entry_t) -> [String: Any]?
    let release: @Sendable (io_object_t) -> Void

    static let live = RegistryAccess(
        entry: { IORegistryEntryFromPath(kIOMainPortDefault, $0) },
        childIterator: { entry in
            var iterator: io_iterator_t = 0
            IORegistryEntryGetChildIterator(entry, kIODeviceTreePlane, &iterator)
            return iterator
        },
        next: { IOIteratorNext($0) },
        properties: { object in
            var properties: Unmanaged<CFMutableDictionary>?
            IORegistryEntryCreateCFProperties(object, &properties, kCFAllocatorDefault, 0)
            return properties?.takeRetainedValue() as? [String: Any]
        },
        release: { IOObjectRelease($0) }
    )
}

/// Reads `IODeviceTree:/cpus/cpuN` — the only reliable source for which logical CPU belongs to which cluster.
public enum IORegistryCPUs {
    public static func read() -> [CPUDescriptor] {
        childProperties(path: "IODeviceTree:/cpus").compactMap(RegistryCPUParser.descriptor)
    }

    static func childProperties(path: String, access: RegistryAccess = .live) -> [[String: Any]] {
        let entry = access.entry(path)
        guard entry != 0 else { return [] }
        defer { access.release(entry) }
        let iterator = access.childIterator(entry)
        defer { access.release(iterator) }
        var result: [[String: Any]] = []
        var child = access.next(iterator)
        while child != 0 {
            if let properties = access.properties(child) {
                result.append(properties)
            }
            access.release(child)
            child = access.next(iterator)
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
