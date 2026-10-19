/// A directory whose files are reported by path relative to it.
public struct SourceRoot: Sendable, Equatable {
    public let path: String

    public init(_ path: String) {
        self.path = path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// `nil` when `file` is not below the root.
    public func relative(_ file: String) -> String? {
        let prefix = path + "/"
        guard file.hasPrefix(prefix) else { return nil }
        return String(file.dropFirst(prefix.count))
    }

    /// Relative path when below the root, otherwise the path unchanged.
    public func display(_ file: String) -> String {
        relative(file) ?? file
    }
}
