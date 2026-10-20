/// How busy the GPU is, as shares of 0...1 that the graphics driver reports. Apple's GPU statistics
/// cover the whole GPU, so there is no per-core figure.
public struct GPULoad: Equatable, Sendable {
    /// The whole GPU: the headline "GPU load".
    public let device: Double
    /// The renderer (fragment and compute work).
    public let renderer: Double
    /// The tiler (vertex work and binning).
    public let tiler: Double

    public init(device: Double, renderer: Double, tiler: Double) {
        self.device = device
        self.renderer = renderer
        self.tiler = tiler
    }
}

/// The GPU's name and size, read once at launch.
public struct GPUInfo: Equatable, Sendable {
    public let name: String
    public let coreCount: Int

    public init(name: String, coreCount: Int) {
        self.name = name
        self.coreCount = coreCount
    }
}

/// The latest whole-GPU load readings, oldest first, for the dashboard's activity bars. macOS has no
/// per-core GPU load, so the GPU's counterpart of the core bars is load over time.
public struct GPULoadHistory: Equatable, Sendable {
    /// A minute at the default 2 s interval.
    public static let capacity = 30
    public let values: [Double]

    public init() {
        values = []
    }

    private init(values: some Collection<Double>) {
        self.values = Array(values)
    }

    /// The history with `load` added, dropping the oldest reading once `capacity` are kept.
    public func appending(_ load: Double) -> GPULoadHistory {
        GPULoadHistory(values: (values + [load]).suffix(Self.capacity))
    }
}
