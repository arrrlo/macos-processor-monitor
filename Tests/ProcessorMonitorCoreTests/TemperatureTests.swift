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
