import AST
import AsyncHTTPClient
import Config
import Foundation
import Rego
import SWCompression

// TODO: Provide a rough equivalent of hooks.Hooks, once we have appropriate infrastructure to warrant it.
// TODO: Port over the hacky bundle compilation via shell-out-to-OPA approach, and add a CLI flag to force SHA sum check before executing. (Maybe also a compile flag/trait?)

extension OPA {
    /// Runtime represents an instance of a Rego policy engine,
    /// and can be started with several options that control
    /// configuration, logging, and lifecycle.
    ///
    /// It is intended to provide a "policy decision point (PDP)
    /// in a box", and is meant to be embedded into larger Swift
    /// applications. Once configured, the Runtime will
    /// automatically handle applying updates to the underlying
    /// policy and data stores as needed.
    ///
    /// ## Lifecycle
    ///
    /// After initialization, call ``run()`` to start background workers
    /// (config providers like discovery, bundle polling, etc.). The `run()`
    /// method blocks until the enclosing `Task` is cancelled, at which
    /// point all workers are torn down via structured concurrency.
    ///
    /// ```swift
    /// let runtime = await OPA.Runtime(config: myConfig)
    /// let runtimeTask = Task { try await runtime.run() }
    ///
    /// // Make policy decisions at any time while run() is active:
    /// let result = try await runtime.decision("authz/allow", input: myInput)
    ///
    /// // Shut down when done:
    /// runtimeTask.cancel()
    /// ```
    ///
    /// You can also use the Runtime without calling `run()` — it will
    /// function with whatever bundles were loaded at init time, but
    /// config providers and bundle polling will not be active.
    public actor Runtime {
        /// The immutable boot configuration. Retained for merge precedence
        /// when a config provider produces new configuration.
        public nonisolated let bootConfig: OPA.Config

        /// Optional config provider (e.g. discovery) that produces
        /// configuration updates over time. Built at init from the boot
        /// config or injected directly as an init parameter.
        private let configProvider: (any OPA.ConfigProvider)?

        /// The ID this Runtime instance uses to identify itself in logs and traces.
        public nonisolated let instanceID: String

        /// HTTP client for network operations (bundle downloads, etc.).
        /// Declared `nonisolated` because `HTTPClient` is `Sendable` and
        /// this allows off-actor bundle fetching without an actor hop.
        public nonisolated let httpClient: HTTPClient?

        /// Storage for loaded bundles (both successful and failed).
        public private(set) var bundleStorage: [String: Result<OPA.Bundle, any Swift.Error>]

        /// Accessor for only the successfully loaded bundles.
        public var bundles: [String: OPA.Bundle] {
            var result: [String: OPA.Bundle] = [:]
            for (name, storage) in bundleStorage {
                if case .success(let bundle) = storage {
                    result[name] = bundle
                }
            }
            return result
        }

        /// Cache for prepared queries. Invalidated when bundles change.
        /// FUTURE: Optimization opportunity — invalidate only the affected *subset* of queries.
        private var preparedQueries: [String: Engine.PreparedQuery]

        /// List of "always on" queries that will be automatically prepared on bundle changes.
        public private(set) var queries: Set<String>

        /// Monotonic counter incremented on every bundle change.
        /// Used to detect interleaved updates during async preparation.
        private var bundleGeneration: UInt64

        /// Monotonic counter incremented on every query set change.
        private var queryGeneration: UInt64

        /// Tracking variable for the bundle generation at the last prepare() call.
        private var preparedBundleGeneration: UInt64 = 0

        /// Tracking variable for the query generation at the last prepare() call.
        private var preparedQueryGeneration: UInt64 = 0

        /// Initialize a Runtime with the given boot configuration.
        ///
        /// If the boot config contains a `discovery` section and no explicit
        /// `configProvider` is supplied, a ``DiscoveryConfigProvider`` is
        /// created automatically.
        ///
        /// Note: No bundle fetching occurs until `run()` is called.
        ///
        /// - Parameters:
        ///   - config: The boot configuration.
        ///   - queries: Initial set of queries to prepare after bundles are loaded.
        ///   - instanceID: An identifier for this Runtime instance.
        ///   - httpClient: The HTTP client to use for network operations.
        ///   - configProvider: An optional config provider. If nil and `config.discovery`
        ///     is set, a ``DiscoveryConfigProvider`` is created automatically.
        public init(
            config: OPA.Config,
            queries: [String]? = nil,
            instanceID: String = UUID().uuidString,
            httpClient: HTTPClient? = nil,
            configProvider: (any OPA.ConfigProvider)? = nil
        ) async {
            self.bootConfig = config
            self.instanceID = instanceID
            self.httpClient = httpClient ?? HTTPClient.shared
            self.preparedQueries = [:]
            self.queries = Set(queries ?? [])
            self.bundleGeneration = 0
            self.queryGeneration = queries?.isEmpty == false ? 1 : 0

            // Placeholder values — all stored properties must be set before
            // calling async methods on self.
            self.bundleStorage = [:]
            // self.engine = OPA.Engine(bundles: [:])

            // Build config provider: explicit -> (future: discovery) -> none.
            if let configProvider {
                self.configProvider = configProvider
            } else {
                self.configProvider = nil
            }
        }
    }
}

// MARK: - Query & Decision

extension OPA.Runtime {
    // Adds a query that will automatically be prepared for later evaluation.
    public func addQuery(_ query: String) {
        if !self.queries.contains(query) {
            self.queries.insert(query)
            self.queryGeneration &+= 1
        }
    }

    // Adds a list of queries from a sequence that will automatically be prepared for later evaluation.
    public func addQueries<S>(_ queries: S) where String == S.Element, S: Sequence {
        let queryCount = self.queries.count
        self.queries.formUnion(queries)

        if self.queries.count > queryCount {
            self.queryGeneration &+= 1
        }
    }

    // Removes a query that will automatically be prepared for later evaluation.
    public func removeQuery(_ query: String) {
        if self.queries.contains(query) {
            self.queries.remove(query)
            self.queryGeneration &+= 1
        }
    }

    // Removes a list of queries from the set the Runtime maintains.
    public func removeQueries<S>(_ queries: S) where String == S.Element, S: Sequence {
        let queryCount = self.queries.count
        self.queries.subtract(queries)

        if self.queries.count < queryCount {
            self.queryGeneration &+= 1
        }
    }

    /// Prepares queries for later evaluation. Intended for use
    /// within the Runtime to ensure a set of prepared queries is available.
    /// Warning: Actor concurrency semantics make some bits more subtle
    /// here than expected.
    private func prepare(adhocQueries: [String]) async throws -> [String: OPA.Engine.PreparedQuery] {
        // Ensure any new queries are added for tracking.
        let adhocQuerySet = Set(adhocQueries)
        if !adhocQuerySet.isSubset(of: self.queries) {
            self.queries.formUnion(adhocQueries)
            self.queryGeneration &+= 1
        }

        // Nothing to do if we are already up-to-date.
        let sameBundleGeneration = self.bundleGeneration == self.preparedBundleGeneration
        let sameQueryGeneration = self.queryGeneration == self.preparedQueryGeneration

        // Snapshot generations before the async work.
        let bundleGen = self.bundleGeneration
        let queryGen = self.queryGeneration
        switch (sameBundleGeneration, sameQueryGeneration) {
        case (true, true):
            // We're already up-to-date.
            break
        case (true, false):
            // Prepare any queries not already in the cache.
            let unprepared = self.queries.subtracting(self.preparedQueries.keys)
            if !unprepared.isEmpty {
                let pq = try await Self.prepareQueries(bundles: self.bundles, queries: unprepared)
                self.preparedQueries.merge(pq, uniquingKeysWith: { (_, new) in new })
            }
            self.preparedQueryGeneration = queryGen
        default:
            // Rebuild all queries if bundles are out of date.
            let pq = try await Self.prepareQueries(bundles: self.bundles, queries: self.queries)

            // Commit results. Only mark as "caught up" to the generation
            // we snapshotted — if a newer generation arrived mid-loop,
            // the counters won't match and the next caller re-prepares.
            self.preparedQueries = pq
            self.preparedBundleGeneration = bundleGen
            self.preparedQueryGeneration = queryGen
        }
        return self.preparedQueries
    }

    /// Prepares all queries against the given engine.
    /// Runs outside actor isolation to avoid mutating-async-on-actor restrictions.
    private nonisolated static func prepareQueries(
        bundles: [String: OPA.Bundle],
        queries: Set<String>
    ) async throws -> [String: OPA.Engine.PreparedQuery] {
        var engine = OPA.Engine(bundles: bundles, capabilities: nil, customBuiltins: [:])
        var pq: [String: OPA.Engine.PreparedQuery] = Dictionary(minimumCapacity: queries.count)
        for query in queries {
            pq[query] = try await engine.prepareForEvaluation(query: query)
        }
        return pq
    }

    // TODO: Refactor to the more generic "DecisionOptions" struct, once ported.
    public func decision(
        _ entrypoint: String,
        input: AST.RegoValue,
        decisionID: String = UUID().uuidString
    ) async throws -> OPA.DecisionResult {
        let pqs: [String: OPA.Engine.PreparedQuery] = try await prepare(adhocQueries: [entrypoint])

        guard let pq = pqs[entrypoint] else {
            throw RuntimeError(
                code: .bundleUnpreparedError,
                message: "Could not find prepared query for entrypoint \(entrypoint)")
        }

        let result = try await pq.evaluate(input: input)
        return OPA.DecisionResult(id: decisionID, result: result)
    }
}

// MARK: - Lifecycle

extension OPA.Runtime {
    /// Starts the Runtime's background workers and blocks until cancelled.
    ///
    /// This creates a task group containing:
    ///  - A **config provider** task (if configured) that produces
    ///    ``OPA.Config`` values on a stream (e.g., via discovery).
    ///  - A **bundle work group managing task** that consumes configs from
    ///    the stream and (re)spawns bundle polling tasks for configured
    ///    bundle resource.
    ///
    /// The initial active config is always emitted to bootstrap bundle
    /// workers, even if no config provider is present.
    ///
    /// Cancelling the enclosing `Task` tears down all workers cleanly:
    /// the config provider finishes its stream, the managing task exits
    /// its `for await` loop, and active bundle pollers are cancelled.
    ///
    /// This method blocks until the enclosing task is cancelled.
    public func run() async throws {
        // Extract Sendable values while on the actor so they can be
        // safely captured by child task closures.
        let provider = self.configProvider
        let initialConfig = self.bootConfig

        try await withThrowingTaskGroup(of: Void.self) { group in
            let (configStream, configContinuation) = AsyncStream<OPA.Config>.makeStream()

            // Start the config provider (e.g., discovery) if present.
            // It runs entirely off the actor and yields configs to the stream.
            if let provider {
                group.addTask {
                    await provider.run(yielding: configContinuation)
                }
            }

            // Emit the initial config to bootstrap bundle workers.
            configContinuation.yield(initialConfig)
            if provider == nil {
                // No more configs coming — finish the stream so the
                // config provider task exits after processing the initial config.
                configContinuation.finish()
            }

            // Bundle worker group task: consumes configs, manages bundle loaders.
            group.addTask {
                var currentWorkers: Task<Void, Never>? = nil

                for await config in configStream {
                    // Tear down previous generation of pollers.
                    currentWorkers?.cancel()
                    await currentWorkers?.value

                    // Spawn new bundle downloaders as a group.
                    // The nested task here allows cancelling the entire
                    // group of bundle loader workers when we encounter
                    // a new config.
                    currentWorkers = Task { [self] in
                        await withTaskGroup(of: Void.self) { bundleGroup in
                            for name in config.bundles.keys {
                                bundleGroup.addTask {
                                    do {
                                        var loader = try self.getBundleLoader(name: name, config: config)
                                        var longPollingEnabled = false

                                        while !Task.isCancelled {
                                            // Attempt to fetch bundle. Update storage.
                                            let result = await loader.load()
                                            await self.updateBundleResult(name: name, result: result)

                                            // If our loader supports it, check long polling flag.
                                            if let httpLoader = loader as? OPA.HTTPBundleLoader {
                                                longPollingEnabled = httpLoader.isLongPollingEnabled()
                                            }

                                            // Sleep until next polling interval.
                                            // If long-polling, the wait is happening in the loader, so skip this.
                                            if !longPollingEnabled {
                                                do {
                                                    let polling = config.bundles[name]?.downloaderConfig.polling
                                                    let sleepTime = Int64.random(
                                                        in: (polling?.minDelaySeconds ?? 60)...(polling?.maxDelaySeconds
                                                            ?? 120))
                                                    try await Task.sleep(for: .seconds(sleepTime))
                                                } catch {
                                                    break  // Task was cancelled — exit cleanly.
                                                }
                                            }
                                        }
                                    } catch {
                                        // Something failed around setting up the bundle loader. Record the error.
                                        await self.updateBundleResult(name: name, result: .failure(error))
                                    }
                                }
                            }
                            // TaskGroup blocks here until all pollers finish or task is canceled.
                        }
                    }
                }

                // The config stream ended (e.g. no config provider).
                // Keep current bundle pollers alive until this task is
                // cancelled.
                let workersToAwait = currentWorkers
                await withTaskCancellationHandler {
                    await workersToAwait?.value
                } onCancel: {
                    workersToAwait?.cancel()
                }
            }

            // Block until all workers finish (cancellation or error).
            // If a worker throws, the group cancels the siblings.
            for try await _ in group {}
        }
    }
}

// MARK: - Bundle Loading

extension OPA.Runtime {
    /// Fetches a single bundle, based on its name and the OPA config.
    ///
    /// Declared `nonisolated` so that multiple fetches can proceed
    /// concurrently in a task group without serializing on the actor.
    /// Only accesses `self.httpClient`, which is `nonisolated let`.
    ///
    /// bundleLoaders accepts types implementing Bundle loader, in
    /// priority order to be tried against the config.
    /// If no loaders are found that can process the bundle, then
    /// we return an error result. This allows splicing in custom
    /// bundle loaders later on that use the "plugins" config section.
    nonisolated func getBundleLoader(
        name: String,
        config: OPA.Config,
        bundleLoaders: [OPA.BundleLoader.Type] = [OPA.DiskBasedBundleLoader.self, OPA.RESTClientBundleLoader.self]
    ) throws -> OPA.BundleLoader {
        var bundleLoader: OPA.BundleLoader?
        for loaderType in bundleLoaders {
            if loaderType.compatibleWithConfig(config: config, bundleResourceName: name) {
                bundleLoader = try loaderType.init(config: config, bundleResourceName: name)
                break
            }
        }

        guard let loader = bundleLoader else {
            throw RuntimeError(
                code: .internalError,
                message: "Unsupported bundle source for bundle \(name)")
        }

        return loader
    }

    /// Applies a single bundle result to the actor's state
    /// and bumps the bundle generation counter.
    ///
    /// Called from bundle polling loops after an off-actor fetch completes.
    /// The actor hop is brief — only synchronous dictionary updates.
    private func updateBundleResult(
        name: String,
        result: Result<OPA.Bundle, any Swift.Error>
    ) {
        // Deduplicate — skip if the result hasn't meaningfully changed.
        let existing = self.bundleStorage[name]
        switch (existing, result) {
        case (.success(let old), .success(let new))
        where old == new:
            return
        case (.failure(let old), .failure(let new))
        where old.localizedDescription == new.localizedDescription:
            return
        default:
            break
        }
        // Update the bundle storage.
        self.bundleStorage[name] = result
        self.bundleGeneration &+= 1
    }
}

public typealias DecisionIDGenerator = @Sendable () async throws -> String
