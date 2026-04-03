import AST
import AsyncHTTPClient
import Config
import Foundation
import Rego
import SWCompression

// TODO: Need some way to signal "Ready" state. Upstream OPA uses a ready channel.
//   - Just throwing an error on a failed bundle fetch is insufficient. Any of N-many bundles *could* fail at load time.
//   - HACK: We will just not worry about concurrency at present.
// TODO: Provide a parameter for the Store?
// TODO: Provide a rough equivalent of hooks.Hooks, once we have appropriate infrastructure to warrant it.
// TODO: Figure out if we care about RegoV0/RegoV1 compatibility / language version enforcement.
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
    /// Some actions the Runtime may perform have non-trivial
    /// costs and stateful behaviors associated with them (e.g.
    /// downloading and activating bundles).
    public struct Runtime: ~Copyable {  // TODO: Consider making Sendable once OPA.Engine is Sendable.
        /// The underlying Rego engine.
        private var engine: OPA.Engine
        public var config: OPA.Config

        /// The ID this Runtime instance will use to identify itself in logs and traces.
        public let instanceID: String

        /// The logger to use for events within the Runtime.
        // private let logger: Logger

        public let restClient: HTTPClient?

        public var bundleStorage: [String: Result<OPA.Bundle, any Swift.Error>]

        public var bundles: [String: OPA.Bundle] {
            var result: [String: OPA.Bundle] = [:]
            for (name, storage) in bundleStorage {
                switch storage {
                case .success(let bundle):
                    result[name] = bundle
                default:
                    continue
                }
            }
            return result
        }

        /// Cache for prepared queries. The cache invalidates all entries when new bundles are loaded.
        /// FUTURE: Optimization opportunity-- invalidate only the affected *subset* of the queries.
        private var preparedQueries: [String: Engine.PreparedQuery] = [:]

        public init(
            config: OPA.Config, instanceID: String = UUID().uuidString, httpClient: HTTPClient? = nil,
            bundles: [String: OPA.Bundle]? = nil
        ) {
            self.config = config
            self.instanceID = instanceID
            self.preparedQueries = [:]

            self.bundleStorage = [String: Result<OPA.Bundle, any Swift.Error>](
                minimumCapacity: (bundles?.count ?? 0) + config.bundles.count)

            for (name, bundleSourceConfig) in self.config.bundles {
                if DiskBasedBundleLoader.compatibleWithConfig(resource: bundleSourceConfig) {
                    do {
                        let bundleLoader = try DiskBasedBundleLoader(
                            services: self.config.services, name: name, resource: bundleSourceConfig)
                        self.bundleStorage[name] = bundleLoader.load()
                    } catch {
                        self.bundleStorage[name] = .failure(error)
                    }
                } else if RESTClientBundleLoader.compatibleWithConfig(
                    services: self.config.services, resource: bundleSourceConfig)
                {
                    guard let httpClient = httpClient else {
                        self.bundleStorage[name] = .failure(
                            RuntimeError.init(
                                code: .internalError, message: "No HTTP client available for fetching bundle \(name)"))
                        continue
                    }

                    do {
                        let bundleLoader = try RESTClientBundleLoader(
                            services: self.config.services, name: name, resource: bundleSourceConfig,
                            httpClient: httpClient)
                        self.bundleStorage[name] = bundleLoader.load()
                    } catch {
                        self.bundleStorage[name] = .failure(error)
                    }
                } else {
                    self.bundleStorage[name] = .failure(
                        .failure(
                            RuntimeError.init(
                                code: .internalError,
                                message: "Unsupported bundle source for bundle \(name)")))
                }
            }

            // Load the explicitly provided in-memory bundles, overwriting entries.
            for (name, bundle) in bundles ?? [:] {
                self.bundleStorage[name] = .success(bundle)
            }

            // Filter just the successfully loaded bundles for initializing the engine.
            var loadedBundles: [String: OPA.Bundle] = [:]
            for (name, storage) in bundleStorage {
                switch storage {
                case .success(let bundle):
                    loadedBundles[name] = bundle
                default:
                    continue
                }
            }
            self.engine = OPA.Engine(bundles: loadedBundles)
        }
    }
}

extension OPA.Runtime {
    /// Prepares queries for later use.
    /// - parameter queries: The query entrypoints for the policy/policies.
    public mutating func prepare(queries: [String]) async throws {
        // TODO: Possibly check for the "no bundles loaded" case and error?
        var newEngine = OPA.Engine(bundles: self.bundles, capabilities: nil, customBuiltins: [:])
        for query in queries {
            self.preparedQueries[query] = try await newEngine.prepareForEvaluation(query: query)
        }
        self.engine = newEngine
    }

    // TODO: Refactor to the more generic "DecisionOptions" struct, once ported.
    public mutating func decision(
        _ entrypoint: String, input: AST.RegoValue, decisionID: String = UUID.init().uuidString
    )
        async throws
        -> OPA.DecisionResult
    {
        // Prepare query if not already cached.
        if preparedQueries[entrypoint] == nil {
            try await prepare(queries: [entrypoint])
        }

        guard let pq: OPA.Engine.PreparedQuery = preparedQueries[entrypoint] else {
            throw RuntimeError(
                code: .bundleUnpreparedError, message: "Could not find prepared query for entrypoint \(entrypoint)")
        }

        let result = try await pq.evaluate(input: input)
        return OPA.DecisionResult(
            id: decisionID,
            result: result
        )
    }
}

public typealias DecisionIDGenerator = @Sendable () async throws -> String
