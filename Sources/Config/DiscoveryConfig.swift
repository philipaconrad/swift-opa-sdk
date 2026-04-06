import Foundation
import Rego

extension OPA {
    // MARK: - Discovery Configuration

    /// Represents the configuration for the discovery feature.
    // From: v1/plugins/discovery/config.go
    public struct DiscoveryConfig: Codable, Sendable {
        public let downloaderConfig: DownloaderConfig
        public let decision: String?
        public let service: String
        public let resource: String?
        public let signing: BundleVerificationConfig?
        public let persist: Bool

        public init(
            downloaderConfig: DownloaderConfig? = nil,
            decision: String? = nil,
            service: String = "",
            resource: String? = nil,
            signing: BundleVerificationConfig? = nil,
            persist: Bool = false
        ) throws {
            self.downloaderConfig = try downloaderConfig ?? DownloaderConfig()
            self.decision = decision
            self.service = service
            self.resource = resource
            self.signing = signing
            self.persist = persist
            try self.validate()
        }

        /// Returns a new config with all context-dependent properties resolved.
        ///
        /// This follows the "resolve" pattern: some properties are defined
        /// in separate top-level config sections and aren't available at decode
        /// time. The parent config calls this method during its resolution phase
        /// to produce a fully-populated instance.
        public func resolved(withKeys keys: [String: KeyConfig]) throws -> DiscoveryConfig {
            let resolvedSigning = try self.signing?.resolved(withKeys: keys)

            return try DiscoveryConfig(
                downloaderConfig: downloaderConfig,
                decision: decision,
                service: service,
                resource: resource,
                signing: resolvedSigning,
                persist: persist
            )
        }

        /// Validates struct-local constraints.
        public func validate() throws {
            if resource == nil {
                throw ConfigError(
                    code: .internalError,
                    message: "missing required discovery.resource field"
                )
            }
        }

        /// Validates constraints that require context from the parent `Config` struct.
        // NOTE: In Go, when signing is nil but keys are present, a default
        // VerificationConfig is injected (via mutation). Since we use immutable
        // properties, that default injection should be handled at a higher level
        // (e.g. in Config) before constructing DiscoveryConfig, if needed.
        public func validateWithContext(
            services: [String: ServiceConfig],
            keys: [String: KeyConfig]
        ) throws {
            if service.isEmpty {
                if services.count != 1 {
                    throw ConfigError(
                        code: .internalError,
                        message:
                            "invalid configuration for discovery service: more than one service is defined"
                    )
                }
            } else {
                if services[service] == nil {
                    throw ConfigError(
                        code: .internalError,
                        message:
                            "invalid configuration for discovery service: service name \"\(service)\" not found"
                    )
                }
            }

            if let signing = signing {
                try signing.validateWithContext(keys: keys)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Decode DownloaderConfig properties inline
            let trigger = try container.decodeIfPresent(TriggerMode.self, forKey: .trigger)
            let polling = try container.decodeIfPresent(PollingConfig.self, forKey: .polling)
            let downloaderConfig = try DownloaderConfig(trigger: trigger, polling: polling)

            let decision = try container.decodeIfPresent(String.self, forKey: .decision)
            let service = try container.decodeIfPresent(String.self, forKey: .service) ?? ""
            let resource = try container.decodeIfPresent(String.self, forKey: .resource)
            let signing = try container.decodeIfPresent(BundleVerificationConfig.self, forKey: .signing)
            let persist = try container.decodeIfPresent(Bool.self, forKey: .persist) ?? false

            try self.init(
                downloaderConfig: downloaderConfig,
                decision: decision,
                service: service,
                resource: resource,
                signing: signing,
                persist: persist
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            // Encode DownloaderConfig properties inline
            try container.encodeIfPresent(downloaderConfig.trigger, forKey: .trigger)
            try container.encodeIfPresent(downloaderConfig.polling, forKey: .polling)

            try container.encodeIfPresent(decision, forKey: .decision)
            try container.encode(service, forKey: .service)
            try container.encodeIfPresent(resource, forKey: .resource)
            try container.encodeIfPresent(signing, forKey: .signing)
            try container.encode(persist, forKey: .persist)
        }

        private enum CodingKeys: String, CodingKey {
            case trigger
            case polling
            case decision
            case service
            case resource
            case signing
            case persist
        }
    }
}
