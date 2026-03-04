import AST
import Foundation
import Rego

extension OPA {
    // MARK: - Bundle Verification Configuration

    /// Represents the key configuration used to verify a signed bundle.
    // From: v1/keys/keys.go
    public struct BundleVerificationConfig: Codable, Sendable {
        public let publicKeys: [String: KeyConfig]
        public let keyID: String
        public let scope: String
        public let exclude: [String]

        public init(
            publicKeys: [String: KeyConfig] = [:],
            keyID: String,
            scope: String,
            exclude: [String] = []
        ) {
            self.publicKeys = publicKeys
            self.keyID = keyID
            self.scope = scope
            self.exclude = exclude
        }

        private enum CodingKeys: String, CodingKey {
            case publicKeys
            case keyID = "keyid"
            case scope
            case exclude = "exclude_files"
        }
    }

    // MARK: - Bundle Source Configuration

    /// A configured bundle source to download bundles from.
    // From: v1/plugins/bundle/bundle.go
    public struct BundleSourceConfig: Codable, Sendable {
        public let downloaderConfig: DownloaderConfig
        public let service: String
        public let resource: String?
        public let signing: BundleVerificationConfig?
        public let persist: Bool?
        public let sizeLimitBytes: Int64

        // service is set to an empty string only for file:// resource URLs.
        public init(
            downloaderConfig: DownloaderConfig = DownloaderConfig(),
            service: String,
            resource: String? = nil,
            signing: BundleVerificationConfig? = nil,
            persist: Bool? = nil,
            sizeLimitBytes: Int64 = 10 * 1024 * 1024  // 10 MB
        ) throws {
            self.downloaderConfig = downloaderConfig
            self.service = service
            self.resource = resource
            // TODO: Validate file:// URLs on empty service name here too? Might be worth having a "validate()" method?
            self.signing = signing
            self.persist = persist
            self.sizeLimitBytes = sizeLimitBytes
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Decode DownloaderConfig properties inline
            let trigger = try container.decodeIfPresent(PluginTriggerMode.self, forKey: .trigger)
            let polling = try container.decodeIfPresent(PollingConfig.self, forKey: .polling)
            self.downloaderConfig = DownloaderConfig(trigger: trigger, polling: polling)

            self.service = try container.decodeIfPresent(String.self, forKey: .service) ?? ""
            self.resource = try container.decodeIfPresent(String.self, forKey: .resource)
            // Service is only allowed to be unset when resource is a file:// URL.
            let isFileURL = self.resource.flatMap(URL.init(string:))?.scheme == "file"
            guard !self.service.isEmpty || isFileURL else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "No service config or file:// URL was provided for bundle config."
                    )
                )
            }
            self.signing = try container.decodeIfPresent(BundleVerificationConfig.self, forKey: .signing)
            self.persist = try container.decodeIfPresent(Bool.self, forKey: .persist)
            // 10 MB default
            self.sizeLimitBytes = try container.decodeIfPresent(Int64.self, forKey: .sizeLimitBytes) ?? 10 * 1024 * 1024
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            // Encode DownloaderConfig properties inline
            try container.encodeIfPresent(downloaderConfig.trigger, forKey: .trigger)
            try container.encodeIfPresent(downloaderConfig.polling, forKey: .polling)

            try container.encode(service, forKey: .service)
            try container.encodeIfPresent(resource, forKey: .resource)
            try container.encodeIfPresent(signing, forKey: .signing)
            try container.encodeIfPresent(persist, forKey: .persist)
            try container.encodeIfPresent(sizeLimitBytes, forKey: .sizeLimitBytes)
        }

        private enum CodingKeys: String, CodingKey {
            case trigger
            case polling
            case service
            case resource
            case signing
            case persist
            case sizeLimitBytes = "size_limit_bytes"
        }
    }
}
