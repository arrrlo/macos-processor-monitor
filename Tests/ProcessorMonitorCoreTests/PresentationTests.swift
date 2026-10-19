import Testing
@testable import ProcessorMonitorCore

@Suite struct MetricFormatterTests {
    @Test func percentRoundsAndClamps() {
        #expect(MetricFormatter.percent(0.234) == "23%")
        #expect(MetricFormatter.percent(0.235) == "24%")
        #expect(MetricFormatter.percent(1.2) == "100%")
        #expect(MetricFormatter.percent(-0.1) == "0%")
        #expect(MetricFormatter.percent(nil) == "—")
    }

    @Test func temperatureInWholeDegrees() {
        #expect(MetricFormatter.temperature(53.4) == "53°C")
        #expect(MetricFormatter.temperature(nil) == "—")
    }

    @Test func processPercentKeepsOneDecimalBelowOneHundred() {
        #expect(MetricFormatter.processPercent(12.345) == "12.3%")
        #expect(MetricFormatter.processPercent(0) == "0.0%")
        #expect(MetricFormatter.processPercent(99.96) == "100%")
        #expect(MetricFormatter.processPercent(250.4) == "250%")
    }

    @Test func statusTitleShowsLoadAndTemperature() {
        var snapshot = MonitorSnapshot.empty
        #expect(MetricFormatter.statusTitle(snapshot) == "—  —")
        snapshot.load = CPULoad(overall: LoadBreakdown(user: 0.2, system: 0.03, idle: 0.77), cores: [])
        snapshot.temperature = TemperatureSummary(average: 48.6, maximum: 60, sensorCount: 3)
        #expect(MetricFormatter.statusTitle(snapshot) == "23%  49°C")
    }
}

@Suite struct MenuTextTests {
    let snapshot = MonitorSnapshot(
        load: CPULoad(overall: LoadBreakdown(user: 0.15, system: 0.08, idle: 0.77), cores: []),
        clusters: [ClusterLoad(name: "Super", average: 0.4, cores: []), ClusterLoad(name: "Performance", average: 0.12, cores: [])],
        temperature: TemperatureSummary(average: 53.2, maximum: 58.9, sensorCount: 42),
        topProcesses: TopProcessesResult(processes: [ProcessUsage(pid: 7, name: "WindowServer", cpuPercent: 12.34)], scope: .allProcesses)
    )

    @Test func metricRows() {
        let text = MenuText(snapshot, clusterNames: ["Super", "Performance"])
        #expect(text.load == MenuText.Row(title: "Processor load", value: "23%"))
        #expect(text.user == MenuText.Row(title: "User", value: "15%"))
        #expect(text.system == MenuText.Row(title: "System", value: "8%"))
        #expect(text.idle == MenuText.Row(title: "Idle", value: "77%"))
        #expect(text.temperature == MenuText.Row(title: "Temperature", value: "53°C (max 59°C)"))
        #expect(text.clusters == [
            MenuText.Row(title: "Super cores", value: "40%"),
            MenuText.Row(title: "Performance cores", value: "12%"),
        ])
        #expect(text.processes == [MenuText.ProcessRow(pid: 7, row: MenuText.Row(title: "WindowServer", value: "12.3%"))])
        #expect(text.processHeader == "Top processes")
    }

    @Test func placeholdersBeforeDataArrives() {
        let text = MenuText(.empty, clusterNames: ["Super"])
        #expect(text.load.value == "—")
        #expect(text.user.value == "—")
        #expect(text.system.value == "—")
        #expect(text.idle.value == "—")
        #expect(text.temperature.value == "Unavailable")
        #expect(text.clusters == [MenuText.Row(title: "Super cores", value: "—")])
        #expect(text.processes.isEmpty)
        #expect(text.processHeader == "Top processes — measuring…")
    }

    @Test func headerExplainsLimitedScope() {
        var limited = snapshot
        limited.topProcesses = TopProcessesResult(processes: [], scope: .currentUser)
        #expect(MenuText(limited, clusterNames: []).processHeader == "Top processes (your processes only)")
    }
}

@Suite struct RefreshIntervalTests {
    @Test func optionsAndTitles() {
        #expect(RefreshInterval.allCases.map(\.seconds) == [1, 2, 5])
        #expect(RefreshInterval.allCases.map(\.title) == ["1 second", "2 seconds", "5 seconds"])
        #expect(RefreshInterval.standard == .two)
    }

    @Test func lookupBySeconds() {
        #expect(RefreshInterval(seconds: 5) == .five)
        #expect(RefreshInterval(seconds: 3) == nil)
    }
}

@Suite struct LaunchctlDisabledParserTests {
    let output = """
    \tdisabled services = {
    \t\t"com.example.other" => disabled
    \t\t"io.github.arrrlo.macos-processor-monitor" => enabled
    \t\t"com.example.legacy" => true
    \t}
    """

    @Test func readsModernAndLegacyFormats() {
        #expect(!LaunchctlDisabledParser.isDisabled(label: "io.github.arrrlo.macos-processor-monitor", in: output))
        #expect(LaunchctlDisabledParser.isDisabled(label: "com.example.other", in: output))
        #expect(LaunchctlDisabledParser.isDisabled(label: "com.example.legacy", in: output))
    }

    @Test func unlistedLabelIsEnabled() {
        #expect(!LaunchctlDisabledParser.isDisabled(label: "com.example.absent", in: output))
    }

    @Test func labelMustMatchExactly() {
        #expect(!LaunchctlDisabledParser.isDisabled(label: "com.example", in: output))
    }
}

@Suite struct ProcessDemandTests {
    @Test func demandWhileMenuOpenOrDashboardVisible() {
        let changes = Values<Bool>()
        let demand = ProcessDemand { changes.all.append($0) }
        demand.menuOpen = true
        demand.dashboardVisible = true
        demand.menuOpen = false
        demand.dashboardVisible = false
        #expect(changes.all == [true, false])
        #expect(!demand.isActive)
    }

    @Test func repeatedValuesDoNotNotify() {
        let changes = Values<Bool>()
        let demand = ProcessDemand { changes.all.append($0) }
        demand.menuOpen = true
        demand.menuOpen = true
        #expect(changes.all == [true])
        #expect(demand.isActive)
    }
}
