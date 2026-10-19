import Foundation
import Testing
@testable import ProcessorMonitorCore
@testable import ProcessorMonitorUI

@Suite struct UserDefaultsSettingsTests {
    @Test func defaultsToTwoSecondsAndPersistsChanges() throws {
        let suite = "io.github.arrrlo.macos-processor-monitor.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = UserDefaultsSettings(defaults: defaults)
        #expect(settings.refreshInterval == .two)
        settings.refreshInterval = .five
        #expect(UserDefaultsSettings(defaults: defaults).refreshInterval == .five)
    }

    @Test func unknownStoredValueFallsBackToTheDefault() throws {
        let suite = "io.github.arrrlo.macos-processor-monitor.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(3.0, forKey: "refreshInterval")
        #expect(UserDefaultsSettings(defaults: defaults).refreshInterval == .two)
    }
}

@Suite struct CommandRunnerTests {
    @Test func returnsStandardOutputOnSuccess() {
        #expect(CommandRunner.run("/bin/echo", ["hello"]) == "hello\n")
    }

    @Test func failingCommandReturnsNil() {
        #expect(CommandRunner.run("/usr/bin/false", []) == nil)
    }

    @Test func missingExecutableReturnsNil() {
        #expect(CommandRunner.run("/no/such/tool", []) == nil)
    }
}

final class CommandLog: @unchecked Sendable {
    var commands: [[String]] = []
}

@Suite struct LaunchAgentLoginItemTests {
    let label = "io.github.arrrlo.macos-processor-monitor"

    func item(output: String?, exists: Bool = true, log: CommandLog = CommandLog()) -> LaunchAgentLoginItem {
        LaunchAgentLoginItem(
            label: label,
            plistPath: "/Library/LaunchAgents/\(label).plist",
            uid: 501,
            run: { arguments in
                log.commands.append(arguments)
                return output
            },
            fileExists: { path in exists && path == "/Library/LaunchAgents/\(label).plist" }
        )
    }

    @Test func availableOnlyWhenTheAgentIsInstalled() {
        #expect(item(output: "").isAvailable)
        #expect(!item(output: "", exists: false).isAvailable)
    }

    @Test func enabledUnlessLaunchdListsItAsDisabled() {
        let log = CommandLog()
        #expect(item(output: "\"\(label)\" => enabled", log: log).isEnabled)
        #expect(log.commands == [["print-disabled", "gui/501"]])
        #expect(!item(output: "\"\(label)\" => disabled").isEnabled)
        #expect(!item(output: nil).isEnabled)
    }

    @Test func togglesThroughLaunchctl() {
        let log = CommandLog()
        let loginItem = item(output: "", log: log)
        loginItem.setEnabled(false)
        loginItem.setEnabled(true)
        #expect(log.commands == [["disable", "gui/501/\(label)"], ["enable", "gui/501/\(label)"]])
    }

    @Test func liveItemQueriesTheRealLaunchd() {
        let live = LaunchAgentLoginItem.live()
        // Not installed on a development machine; either way the query must not crash.
        _ = live.isEnabled
        #expect(live.isAvailable == FileManager.default.fileExists(atPath: "/Library/LaunchAgents/\(label).plist"))
    }
}
