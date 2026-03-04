import Foundation
import Rego

extension OPA {
    // MARK: - Configuration

    /// Represents the configuration file that OPA can be started with.
    public struct Config: Codable, Sendable {
        public let services: [String: ServiceConfig]
        public let labels: [String: String]
        public let discovery: DiscoveryConfig?
        public let bundles: [String: BundleSourceConfig]
        // public let decisionLogs: DecisionLogsConfig?
        // public let status: StatusConfig?
        // public let plugins: [String: PluginConfig]
        // public let keys: KeysConfig?
        // public let defaultDecision: String?
        // public let defaultAuthorizationDecision: String?
        // public let caching: CachingConfig?
        // public let ndBuiltinCache: Bool?
        // public let persistenceDirectory: String?
        // public let distributedTracing: DistributedTracingConfig?
        // public let server: ServerConfig?
        // public let storage: StorageConfig?
        // private let extra: [String: AnyCodable]?

        public init(
            services: [String: ServiceConfig] = [:],
            labels: [String: String] = [:],
            discovery: DiscoveryConfig? = nil,
            bundles: [String: BundleSourceConfig] = [:]
                // decisionLogs: DecisionLogsConfig? = nil,
                // status: StatusConfig? = nil,
                // plugins: [String: PluginConfig] = [:],
                // keys: KeysConfig? = nil,
                // defaultDecision: String? = nil,
                // defaultAuthorizationDecision: String? = nil,
                // caching: CachingConfig? = nil,
                // ndBuiltinCache: Bool? = nil,
                // persistenceDirectory: String? = nil,
                // distributedTracing: DistributedTracingConfig? = nil,
                // server: ServerConfig? = nil,
                // storage: StorageConfig? = nil,
                // extra: [String: AnyCodable]? = nil
        ) {
            self.services = services
            self.labels = labels
            self.discovery = discovery
            self.bundles = bundles
            // self.decisionLogs = decisionLogs
            // self.status = status
            // self.plugins = plugins
            // self.keys = keys
            // self.defaultDecision = defaultDecision
            // self.defaultAuthorizationDecision = defaultAuthorizationDecision
            // self.caching = caching
            // self.ndBuiltinCache = ndBuiltinCache
            // self.persistenceDirectory = persistenceDirectory
            // self.distributedTracing = distributedTracing
            // self.server = server
            // self.storage = storage
            // self.extra = extra
        }

        // MARK: - Decoder

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.services = try container.decodeIfPresent([String: ServiceConfig].self, forKey: .services) ?? [:]
            self.labels = try container.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
            self.discovery = try container.decodeIfPresent(DiscoveryConfig.self, forKey: .discovery)
            self.bundles = try container.decodeIfPresent([String: BundleSourceConfig].self, forKey: .bundles) ?? [:]
            // self.decisionLogs = try container.decodeIfPresent(DecisionLogsConfig.self, forKey: .decisionLogs)
            // self.status = try container.decodeIfPresent(StatusConfig.self, forKey: .status)
            // self.plugins = try container.decodeIfPresent([String: PluginConfig].self, forKey: .plugins) ?? [:]
            // self.keys = try container.decodeIfPresent(KeysConfig.self, forKey: .keys)
            // self.defaultDecision = try container.decodeIfPresent(String.self, forKey: .defaultDecision)
            // self.defaultAuthorizationDecision = try container.decodeIfPresent(String.self, forKey: .defaultAuthorizationDecision)
            // self.caching = try container.decodeIfPresent(CachingConfig.self, forKey: .caching)
            // self.ndBuiltinCache = try container.decodeIfPresent(Bool.self, forKey: .ndBuiltinCache)
            // self.persistenceDirectory = try container.decodeIfPresent(String.self, forKey: .persistenceDirectory)
            // self.distributedTracing = try container.decodeIfPresent(DistributedTracingConfig.self, forKey: .distributedTracing)
            // self.server = try container.decodeIfPresent(ServerConfig.self, forKey: .server)
            // self.storage = try container.decodeIfPresent(StorageConfig.self, forKey: .storage)
            // self.extra = nil  // Extra is not decoded from JSON (matches Go's `json:"-"`)

            // Validation for decoded config.
            for (name, bundle) in self.bundles {
                // Prevent bundle referencing a non-existent service.
                guard bundle.service.isEmpty || self.services[bundle.service] != nil else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: container.codingPath + [
                                CodingKeys.bundles, DynamicCodingKey(stringValue: name),
                            ],
                            debugDescription:
                                "Bundle config for '\(name)' references non-existent service: '\(bundle.service)'"
                        )
                    )
                }
                // If no service specified, require a file:// URL to load from disk.
                guard !bundle.service.isEmpty || (URL(string: bundle.resource ?? "")?.scheme == "file") else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: container.codingPath + [
                                CodingKeys.bundles, DynamicCodingKey(stringValue: name),
                            ],
                            debugDescription:
                                "Bundle config for '\(name)' has no service config or file:// URL resource config. \(bundle.resource ?? "(nil)")"
                        )
                    )
                }
            }
        }

        // MARK: - Encoder

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encodeIfPresent(services.isEmpty ? nil : services, forKey: .services)
            try container.encodeIfPresent(labels.isEmpty ? nil : labels, forKey: .labels)
            try container.encodeIfPresent(discovery, forKey: .discovery)
            try container.encodeIfPresent(bundles.isEmpty ? nil : bundles, forKey: .bundles)
            // try container.encodeIfPresent(decisionLogs, forKey: .decisionLogs)
            // try container.encodeIfPresent(status, forKey: .status)
            // try container.encodeIfPresent(plugins.isEmpty ? nil : plugins, forKey: .plugins)
            // try container.encodeIfPresent(keys, forKey: .keys)
            // try container.encodeIfPresent(defaultDecision, forKey: .defaultDecision)
            // try container.encodeIfPresent(defaultAuthorizationDecision, forKey: .defaultAuthorizationDecision)
            // try container.encodeIfPresent(caching, forKey: .caching)
            // try container.encodeIfPresent(ndBuiltinCache, forKey: .ndBuiltinCache)
            // try container.encodeIfPresent(persistenceDirectory, forKey: .persistenceDirectory)
            // try container.encodeIfPresent(distributedTracing, forKey: .distributedTracing)
            // try container.encodeIfPresent(server, forKey: .server)
            // try container.encodeIfPresent(storage, forKey: .storage)
            // Extra is not encoded to JSON (matches Go's `json:"-"`)
        }

        private enum CodingKeys: String, CodingKey {
            case services
            case labels
            case discovery
            case bundles
            case decisionLogs = "decision_logs"
            case status
            case plugins
            case keys
            case defaultDecision = "default_decision"
            case defaultAuthorizationDecision = "default_authorization_decision"
            case caching
            case ndBuiltinCache = "nd_builtin_cache"
            case persistenceDirectory = "persistence_directory"
            case distributedTracing = "distributed_tracing"
            case server
            case storage
            // Note: extra is not included since it uses `json:"-"` in Go
        }
    }

    /// A CodingKey for dynamic/runtime key values (e.g. dictionary keys).
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) { nil }
    }
}
