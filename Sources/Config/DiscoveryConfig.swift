import AST
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
            downloaderConfig: DownloaderConfig = DownloaderConfig(),
            decision: String? = nil,
            service: String,
            resource: String? = nil,
            signing: BundleVerificationConfig? = nil,
            persist: Bool
        ) {
            self.downloaderConfig = downloaderConfig
            self.decision = decision
            self.service = service
            self.resource = resource
            self.signing = signing
            self.persist = persist
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Decode DownloaderConfig properties inline
            let trigger = try container.decodeIfPresent(PluginTriggerMode.self, forKey: .trigger)
            let polling = try container.decode(PollingConfig.self, forKey: .polling)
            self.downloaderConfig = DownloaderConfig(trigger: trigger, polling: polling)

            self.decision = try container.decodeIfPresent(String.self, forKey: .decision)
            self.service = try container.decode(String.self, forKey: .service)
            self.resource = try container.decodeIfPresent(String.self, forKey: .resource)
            self.signing = try container.decodeIfPresent(BundleVerificationConfig.self, forKey: .signing)
            self.persist = try container.decode(Bool.self, forKey: .persist)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            // Encode DownloaderConfig properties inline
            try container.encodeIfPresent(downloaderConfig.trigger, forKey: .trigger)
            try container.encode(downloaderConfig.polling, forKey: .polling)

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
