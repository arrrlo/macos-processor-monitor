import Foundation

/// Side effects the tools need, injectable for tests.
public struct ToolEnvironment: Sendable {
    public var readFile: @Sendable (String) throws -> Data
    /// Absolute paths of all `.swift` files below a directory, sorted.
    public var swiftFiles: @Sendable (String) throws -> [String]
    public var output: @Sendable (String) -> Void

    public init(
        readFile: @escaping @Sendable (String) throws -> Data,
        swiftFiles: @escaping @Sendable (String) throws -> [String],
        output: @escaping @Sendable (String) -> Void
    ) {
        self.readFile = readFile
        self.swiftFiles = swiftFiles
        self.output = output
    }

    public static let live = ToolEnvironment(
        readFile: { try Data(contentsOf: URL(fileURLWithPath: $0)) },
        swiftFiles: { directory in
            try FileManager.default.subpathsOfDirectory(atPath: directory)
                .filter { $0.hasSuffix(".swift") }
                .map { directory + "/" + $0 }
                .sorted()
        },
        output: { print($0) }
    )
}
