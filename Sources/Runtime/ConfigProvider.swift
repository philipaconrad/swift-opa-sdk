import Config
import Foundation
import Rego

extension OPA {
    /// A type that produces configuration updates over time.
    ///
    /// Implementations run independently (off the Runtime actor) and
    /// yield new ``OPA.Config`` values through an `AsyncStream` whenever
    /// the active configuration should change. The Runtime consumes
    /// these updates, reloading bundles and restarting polling workers
    /// for each new configuration.
    ///
    /// Conforming types must be `Sendable` so they can be safely handed
    /// off to a child task in the Runtime's task group.
    ///
    /// ## Implementing a ConfigProvider
    ///
    /// ```swift
    /// struct MyConfigProvider: OPA.ConfigProvider {
    ///     func run(yielding continuation: AsyncStream<OPA.Config>.Continuation) async {
    ///         defer { continuation.finish() }
    ///         while !Task.isCancelled {
    ///             let config = try? await fetchLatestConfig()
    ///             if let config { continuation.yield(config) }
    ///             try? await Task.sleep(for: .seconds(30))
    ///         }
    ///     }
    /// }
    /// ```
    public protocol ConfigProvider: Sendable {
        /// Produces configuration values until cancelled.
        ///
        /// Implementations should:
        /// 1. Yield an initial config as soon as it's available.
        /// 2. Yield subsequent configs whenever the configuration changes.
        /// 3. Call `continuation.finish()` when done (typically in a `defer`).
        /// 4. Exit on `Task.isCancelled`.
        func run(yielding continuation: AsyncStream<OPA.Config>.Continuation) async
    }
}
