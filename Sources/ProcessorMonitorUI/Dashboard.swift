import AppKit
import ProcessorMonitorCore
import SwiftUI

public struct DashboardModel {
    public let snapshot: MonitorSnapshot
    public let clusterNames: [String]
    public let apps: [Int32: AppInfo]
    public let gpu: GPUInfo?
    /// Seconds between readings, which sets how much time the GPU activity bars span.
    public let refreshInterval: Double

    public init(
        snapshot: MonitorSnapshot,
        clusterNames: [String],
        apps: [Int32: AppInfo],
        gpu: GPUInfo? = nil,
        refreshInterval: Double = RefreshInterval.standard.seconds
    ) {
        self.snapshot = snapshot
        self.clusterNames = clusterNames
        self.apps = apps
        self.gpu = gpu
        self.refreshInterval = refreshInterval
    }

    var gpuCaption: String {
        guard let gpu else { return "No GPU found" }
        return "\(gpu.name) · \(gpu.coreCount) GPU cores"
    }

    /// The GPU's two units. They overlap in time, so they are shown as text, not as parts of the bar.
    var gpuSplit: String {
        let load = snapshot.gpuLoad
        return "Renderer \(MetricFormatter.percent(load?.renderer)) · Tiler \(MetricFormatter.percent(load?.tiler))"
    }

    /// One slot per bar, oldest first; slots not filled yet (after a start or an interval change) are nil.
    var historyBars: [Double?] {
        let values = snapshot.gpuHistory.values
        return Array(repeating: nil, count: GPULoadHistory.capacity - values.count) + values.map { $0 }
    }

    var historySpan: String {
        "Last \(Int((Double(GPULoadHistory.capacity) * refreshInterval).rounded())) s"
    }

    var cpuProcessesTitle: String { MenuText.processHeader(snapshot.topProcesses?.scope, kind: "CPU") }
    var gpuProcessesTitle: String { MenuText.processHeader(snapshot.topGPUProcesses?.scope, kind: "GPU") }
    var gpuProcessRows: [MenuText.ProcessRow] { MenuText.processRows(snapshot.topGPUProcesses) }

    var text: MenuText { MenuText(snapshot, clusterNames: clusterNames) }

    func coreLoads(for cluster: String) -> [CoreLoad] {
        snapshot.clusters.first { $0.name == cluster }?.cores ?? []
    }

    static func barWidth(_ fraction: Double, of width: CGFloat) -> CGFloat {
        width * CGFloat(min(max(fraction, 0), 1))
    }

    /// Width of each of `count` bars so the bars and their gaps span the occupancy column.
    static func coreBarWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return (DashboardView.barsWidth - DashboardView.barSpacing * CGFloat(count - 1)) / CGFloat(count)
    }

    static let historyBarWidth = coreBarWidth(count: GPULoadHistory.capacity)
}

/// Read-only dashboard, one row per processor: load, temperature, occupancy (load over time for
/// the GPU, which has no per-core figure) and top processes. Every card in a row is as tall as the
/// tallest, the process list. It has no controls on purpose: every action lives in the menu.
struct DashboardView: View {
    static let padding: CGFloat = 18
    static let spacing: CGFloat = 14
    static let cardPadding: CGFloat = 14
    /// Fits the 250 pt load bar and its legend.
    static let loadWidth: CGFloat = LoadCard.barWidth + 2 * cardPadding
    static let temperatureWidth: CGFloat = 220
    /// Sized so 6, 12 and 30 bars with 4 pt gaps all come out in whole points.
    static let occupancyWidth: CGFloat = 384
    static let processesWidth: CGFloat = 380
    /// The width the occupancy and activity cards leave for their bars.
    static let barsWidth: CGFloat = occupancyWidth - 2 * cardPadding
    static let barSpacing: CGFloat = 4

    let model: DashboardModel

    var body: some View {
        Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
            GridRow {
                LoadCard(model: model).frame(width: Self.loadWidth)
                TemperatureCard(title: "CPU temperature", summary: model.snapshot.temperature, caption: "Processor die sensors")
                    .frame(width: Self.temperatureWidth)
                OccupancyCard(model: model).frame(width: Self.occupancyWidth)
                ProcessesCard(title: model.cpuProcessesTitle, valueHeader: "CPU", rows: model.text.processes, apps: model.apps)
                    .frame(width: Self.processesWidth)
            }
            GridRow {
                GPULoadCard(model: model).frame(width: Self.loadWidth)
                TemperatureCard(title: "GPU temperature", summary: model.snapshot.gpuTemperature, caption: "GPU sensors")
                    .frame(width: Self.temperatureWidth)
                GPUActivityCard(model: model).frame(width: Self.occupancyWidth)
                ProcessesCard(title: model.gpuProcessesTitle, valueHeader: "GPU", rows: model.gpuProcessRows, apps: model.apps)
                    .frame(width: Self.processesWidth)
            }
        }
        .padding(Self.padding)
        .fixedSize()
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
        .padding(DashboardView.cardPadding)
        // Fills its grid cell, so every card in a row is as tall as the tallest.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }
}

private struct LoadCard: View {
    static let barWidth: CGFloat = 250
    let model: DashboardModel

    var body: some View {
        let text = model.text
        let overall = model.snapshot.load?.overall
        Card("CPU load") {
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

private struct GPULoadCard: View {
    let model: DashboardModel

    var body: some View {
        let device = model.snapshot.gpuLoad?.device
        Card("GPU load") {
            Text(MetricFormatter.percent(device)).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
            HStack(spacing: 0) {
                Rectangle().fill(Color.accentColor).frame(width: DashboardModel.barWidth(device ?? 0, of: LoadCard.barWidth))
                Spacer(minLength: 0)
            }
            .frame(width: LoadCard.barWidth, height: 10)
            .background(Color.gray.opacity(0.25))
            .clipShape(Capsule())
            Text(model.gpuSplit).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

private struct TemperatureCard: View {
    let title: String
    let summary: TemperatureSummary?
    let caption: String

    var body: some View {
        Card(title) {
            Text(MetricFormatter.temperature(summary?.average)).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(summary.map { "Max \(MetricFormatter.temperature($0.maximum)) · \($0.sensorCount) readings" } ?? "No sensors found")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(caption).font(.caption).foregroundStyle(.tertiary)
        }
    }
}

private struct OccupancyCard: View {
    let model: DashboardModel

    var body: some View {
        Card("CPU occupancy") {
            ForEach(Array(zip(model.clusterNames, model.text.clusters)), id: \.0) { name, row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.title)
                        Spacer()
                        Text(row.value).monospacedDigit()
                    }
                    let cores = model.coreLoads(for: name)
                    let barWidth = DashboardModel.coreBarWidth(count: cores.count)
                    HStack(alignment: .bottom, spacing: DashboardView.barSpacing) {
                        ForEach(cores, id: \.index) { core in
                            CoreBar(core: core, width: barWidth)
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
    let width: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            LoadBar(load: core.load, width: width, height: Self.height)
            Text(verbatim: String(core.index)).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .help("Core \(core.index): \(MetricFormatter.percent(core.load))")
    }
}

/// A vertical bar filled from the bottom to `load` (0...1).
private struct LoadBar: View {
    let load: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.2))
            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(height: DashboardModel.barWidth(load, of: height))
        }
        .frame(width: width, height: height)
    }
}

/// The GPU's counterpart of the core bars: macOS reports one load for the whole GPU, so its
/// activity is shown over time instead, newest on the right.
private struct GPUActivityCard: View {
    static let barHeight: CGFloat = 130
    let model: DashboardModel

    var body: some View {
        Card("GPU activity") {
            HStack {
                Text(model.historySpan)
                Spacer()
                Text(MetricFormatter.percent(model.snapshot.gpuLoad?.device)).monospacedDigit()
            }
            HStack(alignment: .bottom, spacing: DashboardView.barSpacing) {
                ForEach(Array(model.historyBars.enumerated()), id: \.offset) { _, load in
                    LoadBar(load: load ?? 0, width: DashboardModel.historyBarWidth, height: Self.barHeight)
                }
            }
            Text(model.gpuCaption).font(.caption).foregroundStyle(.tertiary)
            Text("macOS reports one load for the whole GPU").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// A top-10 list. The name column takes the spare width, so the numbers sit at the card's right edge.
private struct ProcessesCard: View {
    let title: String
    let valueHeader: String
    let rows: [MenuText.ProcessRow]
    let apps: [Int32: AppInfo]

    var body: some View {
        Card(title) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                    Text("PID").gridColumnAlignment(.trailing)
                    Text(valueHeader).gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                // A fixed number of rows keeps the window from resizing as the list changes.
                ForEach(0..<StatusMenuController.processSlots, id: \.self) { index in
                    if index < rows.count {
                        ProcessRowView(process: rows[index], app: apps[rows[index].pid])
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
            Text(app?.name ?? process.row.title).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            // verbatim: a PID is an identifier, not a number to format with thousands separators.
            Text(verbatim: String(process.pid)).monospacedDigit().foregroundStyle(.secondary)
            Text(process.row.value).monospacedDigit()
        }
    }
}
