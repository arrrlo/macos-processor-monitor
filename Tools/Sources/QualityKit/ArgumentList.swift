/// `<subcommand> [--option value]...` with repeatable options.
public struct ArgumentList: Sendable {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case missingSubcommand
        case missingValue(String)
        case missingOption(String)
        case unexpected(String)
        case notANumber(String)

        public var description: String {
            switch self {
            case .missingSubcommand: "missing subcommand"
            case .missingValue(let name): "option --\(name) needs a value"
            case .missingOption(let name): "missing required option --\(name)"
            case .unexpected(let argument): "unexpected argument '\(argument)'"
            case .notANumber(let name): "option --\(name) needs a number"
            }
        }
    }

    public let subcommand: String
    private let options: [(name: String, value: String)]

    public init(_ arguments: [String]) throws {
        guard let first = arguments.first, !first.hasPrefix("--") else { throw Failure.missingSubcommand }
        subcommand = first
        var options: [(name: String, value: String)] = []
        var remaining = arguments.dropFirst()
        while let argument = remaining.popFirst() {
            guard argument.hasPrefix("--") else { throw Failure.unexpected(argument) }
            let name = String(argument.dropFirst(2))
            guard let value = remaining.popFirst() else { throw Failure.missingValue(name) }
            options.append((name, value))
        }
        self.options = options
    }

    public func values(for name: String) -> [String] {
        options.filter { $0.name == name }.map(\.value)
    }

    public func optionalValue(for name: String) -> String? {
        values(for: name).last
    }

    public func value(for name: String) throws -> String {
        guard let value = optionalValue(for: name) else { throw Failure.missingOption(name) }
        return value
    }

    public func intValue(for name: String, default fallback: Int) throws -> Int {
        guard let text = optionalValue(for: name) else { return fallback }
        guard let number = Int(text) else { throw Failure.notANumber(name) }
        return number
    }
}
