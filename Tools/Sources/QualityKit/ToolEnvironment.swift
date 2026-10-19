import Foundation

/// Side effects the tools need, injectable for tests.
public struct ToolEnvironment: Sendable {
    public var readFile: @Sendable (String) throws -> Data
    /// Absolute paths of all `.swift` files below a directory, sorted.
    public var swiftFiles: @Sendable (String) throws -> [String]
    public var output: @Sendable (String) -> Void
    public var writeFile: @Sendable (String, Data) throws -> Void
    public var runner: any CommandRunning
    public var temporaryDirectory: String
    /// Seconds, for timing only.
    public var now: @Sendable () -> Double

    public init(
        readFile: @escaping @Sendable (String) throws -> Data,
        swiftFiles: @escaping @Sendable (String) throws -> [String],
        output: @escaping @Sendable (String) -> Void,
        writeFile: @escaping @Sendable (String, Data) throws -> Void,
        runner: any CommandRunning,
        temporaryDirectory: String,
        now: @escaping @Sendable () -> Double
    ) {
        self.readFile = readFile
        self.swiftFiles = swiftFiles
        self.output = output
        self.writeFile = writeFile
        self.runner = runner
        self.temporaryDirectory = temporaryDirectory
        self.now = now
    }

    public static let live = ToolEnvironment(
        readFile: { try Data(contentsOf: URL(fileURLWithPath: $0)) },
        swiftFiles: { directory in
            try FileManager.default.subpathsOfDirectory(atPath: directory)
                .filter { $0.hasSuffix(".swift") }
                .map { directory + "/" + $0 }
                .sorted()
        },
        output: { print($0) },
        writeFile: { path, data in try data.write(to: URL(fileURLWithPath: path)) },
        runner: ShellRunner(),
        temporaryDirectory: SourceRoot(NSTemporaryDirectory()).path,
        now: { Date().timeIntervalSinceReferenceDate }
    )
}
