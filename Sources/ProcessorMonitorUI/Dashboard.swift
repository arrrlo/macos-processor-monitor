import AppKit
import ProcessorMonitorCore
import SwiftUI

public struct DashboardModel {
    public let snapshot: MonitorSnapshot
    public let clusterNames: [String]
    public let apps: [Int32: AppInfo]

    public init(snapshot: MonitorSnapshot, clusterNames: [String], apps: [Int32: AppInfo]) {
        self.snapshot = snapshot
        self.clusterNames = clusterNames
        self.apps = apps
    }

    var text: MenuText { MenuText(snapshot, clusterNames: clusterNames) }

    func coreLoads(for cluster: String) -> [CoreLoad] {
        snapshot.clusters.first { $0.name == cluster }?.cores ?? []
    }

    static func barWidth(_ fraction: Double, of width: CGFloat) -> CGFloat {
        width * CGFloat(min(max(fraction, 0), 1))
    }
}

/// Read-only dashboard. It has no controls on purpose: every action lives in the menu.
struct DashboardView: View {
    let model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                LoadCard(model: model)
                TemperatureCard(summary: model.snapshot.temperature)
            }
            OccupancyCard(model: model)
            ProcessesCard(model: model)
        }
        .padding(18)
        .frame(width: 600)
    }
}

private struct Card<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }
}

private struct LoadCard: View {
    static let barWidth: CGFloat = 250
    let model: DashboardModel

    var body: some View {
        let text = model.text
        let overall = model.snapshot.load?.overall
        Card("Processor load") {
            Text(text.load.value).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
            HStack(spacing: 0) {
                Rectangle().fill(Color.accentColor).frame(width: DashboardModel.barWidth(overall?.user ?? 0, of: Self.barWidth))
                Rectangle().fill(Color.orange).frame(width: DashboardModel.barWidth(overall?.system ?? 0, of: Self.barWidth))
                Spacer(minLength: 0)
            }
            .frame(width: Self.barWidth, height: 10)
            .background(Color.gray.opacity(0.25))
            .clipShape(Capsule())
            HStack(spacing: 14) {
                Legend(color: .accentColor, row: text.user)
                Legend(color: .orange, row: text.system)
                Legend(color: .gray.opacity(0.4), row: text.idle)
            }
        }
    }
}

private struct Legend: View {
    let color: Color
    let row: MenuText.Row

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(row.title) \(row.value)").font(.callout).monospacedDigit()
        }
    }
}

private struct TemperatureCard: View {
    let summary: TemperatureSummary?

    var body: some View {
        Card("Temperature") {
            Text(MetricFormatter.temperature(summary?.average)).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(summary.map { "Max \(MetricFormatter.temperature($0.maximum)) · \($0.sensorCount) readings" } ?? "No sensors found")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Processor die sensors").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

private struct OccupancyCard: View {
    let model: DashboardModel

    var body: some View {
        Card("Occupancy") {
            ForEach(Array(zip(model.clusterNames, model.text.clusters)), id: \.0) { name, row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.title)
                        Spacer()
                        Text(row.value).monospacedDigit()
                    }
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(model.coreLoads(for: name), id: \.index) { core in
                            CoreBar(core: core)
                        }
                    }
                }
            }
        }
    }
}

private struct CoreBar: View {
    static let height: CGFloat = 40
    let core: CoreLoad

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.2))
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(height: DashboardModel.barWidth(core.load, of: Self.height))
            }
            .frame(width: 16, height: Self.height)
            Text(verbatim: String(core.index)).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .help("Core \(core.index): \(MetricFormatter.percent(core.load))")
    }
}

private struct ProcessesCard: View {
    let model: DashboardModel

    var body: some View {
        let text = model.text
        Card(text.processHeader) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("Name")
                    Text("PID")
                    Text("CPU").gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                // A fixed number of rows keeps the window from resizing as the list changes.
                ForEach(0..<StatusMenuController.processSlots, id: \.self) { index in
                    if index < text.processes.count {
                        ProcessRowView(process: text.processes[index], app: model.apps[text.processes[index].pid])
                    } else {
                        GridRow { Text(" ") }
                    }
                }
            }
        }
    }
}

private struct ProcessRowView: View {
    let process: MenuText.ProcessRow
    let app: AppInfo?

    var body: some View {
        GridRow {
            if let app {
                Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "gearshape").foregroundStyle(.secondary).frame(width: 16, height: 16)
            }
            Text(app?.name ?? process.row.title).lineLimit(1).frame(width: 330, alignment: .leading)
            // verbatim: a PID is an identifier, not a number to format with thousands separators.
            Text(verbatim: String(process.pid)).monospacedDigit().foregroundStyle(.secondary)
            Text(process.row.value).monospacedDigit()
        }
    }
}
