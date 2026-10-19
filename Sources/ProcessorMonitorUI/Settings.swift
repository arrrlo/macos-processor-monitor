import Foundation
import ProcessorMonitorCore

public protocol SettingsStore: AnyObject {
    var refreshInterval: RefreshInterval { get set }
}

public final class UserDefaultsSettings: SettingsStore {
    private static let refreshIntervalKey = "refreshInterval"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var refreshInterval: RefreshInterval {
        get { RefreshInterval(seconds: defaults.double(forKey: Self.refreshIntervalKey)) ?? .standard }
        set { defaults.set(newValue.seconds, forKey: Self.refreshIntervalKey) }
    }
}
