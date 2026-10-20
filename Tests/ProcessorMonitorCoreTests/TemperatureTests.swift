import Testing
@testable import ProcessorMonitorCore

@Suite struct TemperatureAggregatorTests {
    @Test func averagesAndFindsMaximumOfValidReadings() throws {
        let summary = try #require(TemperatureAggregator.summarize([50, 60, 55, -9201, 0, 151]))
        #expect(summary == TemperatureSummary(average: 55, maximum: 60, sensorCount: 3))
    }

    @Test func boundariesOfTheValidRange() {
        #expect(TemperatureAggregator.isValid(150))
        #expect(TemperatureAggregator.isValid(0.5))
        #expect(!TemperatureAggregator.isValid(0))
        #expect(!TemperatureAggregator.isValid(150.01))
        #expect(!TemperatureAggregator.isValid(.nan))
    }

    @Test func noValidReadingsMeansNoSummary() {
        #expect(TemperatureAggregator.summarize([]) == nil)
        #expect(TemperatureAggregator.summarize([-9201]) == nil)
    }
}

@Suite struct CPUTemperatureSensorsTests {
    @Test func prefersPerClusterSensorsWhenPresent() {
        let names = ["PMU tdie1", "pACC MTR Temp Sensor0", "GPU MTR Temp Sensor1", "eACC MTR Temp Sensor3", "NAND CH0 temp"]
        #expect(CPUTemperatureSensors.select(names) == [1, 3])
    }

    @Test func fallsBackToDieSensorsKeepingDuplicates() {
        let names = ["PMU tdev1", "PMU tdie1", "PMU tdie1", "PMU tcal", "PMU tdie14", "NAND CH0 temp"]
        #expect(CPUTemperatureSensors.select(names) == [1, 2, 4])
    }

    @Test func nothingSuitable() {
        #expect(CPUTemperatureSensors.select(["NAND CH0 temp", "gas gauge battery"]).isEmpty)
    }
}

@Suite struct GPUTemperatureSensorsTests {
    @Test func takesEveryoneUpToEight() {
        #expect(GPUTemperatureSensors.select(count: 0).isEmpty)
        #expect(GPUTemperatureSensors.select(count: 3) == [0, 1, 2])
        #expect(GPUTemperatureSensors.select(count: 8) == Array(0..<8))
    }

    /// An M5 Max has 84 GPU sensors within a degree of each other; eight spread across them read the same.
    @Test func spreadsEightAcrossMore() {
        #expect(GPUTemperatureSensors.limit == 8)
        #expect(GPUTemperatureSensors.select(count: 84) == [0, 10, 21, 31, 42, 52, 63, 73])
        #expect(GPUTemperatureSensors.select(count: 9) == [0, 1, 2, 3, 4, 5, 6, 7])
    }
}
