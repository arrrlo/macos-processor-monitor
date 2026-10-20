public struct TemperatureSummary: Equatable, Sendable {
    /// Mean of all valid sensor readings, °C. This is the headline "processor temperature".
    public let average: Double
    public let maximum: Double
    public let sensorCount: Int

    public init(average: Double, maximum: Double, sensorCount: Int) {
        self.average = average
        self.maximum = maximum
        self.sensorCount = sensorCount
    }
}

public enum TemperatureAggregator {
    /// Sensors report nonsense outside this range (e.g. `PMU tdev*` returns about −9201).
    public static func isValid(_ celsius: Double) -> Bool {
        celsius > 0 && celsius <= 150
    }

    public static func summarize(_ readings: [Double]) -> TemperatureSummary? {
        let valid = readings.filter(isValid)
        guard let maximum = valid.max() else { return nil }
        return TemperatureSummary(
            average: valid.reduce(0, +) / Double(valid.count),
            maximum: maximum,
            sensorCount: valid.count
        )
    }
}

/// Picks the HID temperature sensors that describe the CPU.
public enum CPUTemperatureSensors {
    /// Indices of the chosen sensors. Chips with per-cluster sensors ("pACC/eACC MTR Temp Sensor")
    /// use those; newer chips (e.g. M5) only expose SoC die sensors ("PMU tdie*"), each listed
    /// several times with slightly different values, so duplicates are kept for the average.
    public static func select(_ names: [String]) -> [Int] {
        let cluster = names.indices.filter { names[$0].contains("ACC MTR Temp Sensor") }
        guard cluster.isEmpty else { return cluster }
        return names.indices.filter { names[$0].hasPrefix("PMU tdie") }
    }
}

/// Picks which of the SMC's GPU sensors (`Tg*`) to read. An M5 Max has 84 that read within a degree
/// of each other, so an even spread of at most `limit` gives the same average for a tenth of the
/// cost (8 reads take about 0.1 ms of CPU, 84 take 1 ms).
public enum GPUTemperatureSensors {
    public static let limit = 8

    /// Indices of the chosen sensors among `count`, spread evenly from the first.
    public static func select(count: Int) -> [Int] {
        let chosen = min(count, limit)
        return (0..<chosen).map { $0 * count / chosen }
    }
}
