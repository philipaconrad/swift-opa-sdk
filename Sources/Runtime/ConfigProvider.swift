import Config
import Foundation
import Rego

extension OPA {
    /// A type that produces configuration updates over time.
    ///
    /// Implementations run independently (off the Runtime actor) and
    /// yield ``Result<OPA.Config, Error>`` values through an `AsyncStream`
    /// whenever the active configuration should change (or an error occurs
    /// fetching it). The Runtime consumes these updates, reloading bundles
    /// and restarting polling workers for each successful new configuration.
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
        /// Needs a public constructor that can build from the config directly.
        init(config: OPA.Config) throws

        /// Load (or re-load) the discovered configuration, based on the
        /// initial config and any existing state.
        mutating func load() async -> Result<OPA.Config, any Swift.Error>
    }

    /// HTTPConfigProvider is a slightly more specialized protocol to allow greater
    /// control for HTTP-based config providers (e.g. Discovery).
    public protocol HTTPConfigProvider: ConfigProvider, Sendable {
        /// Used by the loader-managing task to determine whether to sleep or not between polls.
        func isLongPollingEnabled() -> Bool
    }
}
