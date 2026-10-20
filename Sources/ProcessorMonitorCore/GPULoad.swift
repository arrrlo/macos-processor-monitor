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
