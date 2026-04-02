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

        /// Returns a new config with the provided public keys injected,
        /// validating that `keyID` (if set) references an existing key.
        ///
        /// This follows the "resolve" pattern: because `publicKeys` are defined
        /// in a separate top-level config section, they aren't available at
        /// decode time. The parent config calls this method during its
        /// resolution phase to produce a fully-populated instance.
        ///
        /// Ported from Go's `VerificationConfig.ValidateAndInjectDefaults`.
        public func resolved(withKeys keys: [String: KeyConfig]) throws -> BundleVerificationConfig {
            if !keyID.isEmpty && keys[keyID] == nil {
                throw ConfigError(
                    code: .internalError,
                    message: "Key ID '\(keyID)' not found"
                )
            }
            return BundleVerificationConfig(
                publicKeys: keys,
                keyID: keyID,
                scope: scope,
                exclude: exclude
            )
        }

        /// Validates constraints that require context from the parent `Config` struct.
        /// Ported from Go's `VerificationConfig.ValidateAndInjectDefaults`.
        public func validateWithContext(keys: [String: KeyConfig]) throws {
            guard keyID.isEmpty || keys[keyID] != nil else {
                throw ConfigError(
                    code: .internalError,
                    message: "Key ID '\(keyID)' not found"
                )
            }
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
            downloaderConfig: DownloaderConfig? = nil,
            service: String = "",
            resource: String? = nil,
            signing: BundleVerificationConfig? = nil,
            persist: Bool? = nil,
            sizeLimitBytes: Int64 = 10 * 1024 * 1024  // 10 MB
        ) throws {
            self.downloaderConfig = try downloaderConfig ?? DownloaderConfig()
            self.service = service
            self.resource = resource
            self.signing = signing
            self.persist = persist
            self.sizeLimitBytes = sizeLimitBytes
            try self.validate()
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Decode DownloaderConfig properties inline
            let trigger = try container.decodeIfPresent(TriggerMode.self, forKey: .trigger)
            let polling = try container.decodeIfPresent(PollingConfig.self, forKey: .polling)
            self.downloaderConfig = try DownloaderConfig(trigger: trigger, polling: polling)

            self.service = try container.decodeIfPresent(String.self, forKey: .service) ?? ""
            self.resource = try container.decodeIfPresent(String.self, forKey: .resource)
            self.signing = try container.decodeIfPresent(BundleVerificationConfig.self, forKey: .signing)
            self.persist = try container.decodeIfPresent(Bool.self, forKey: .persist)
            // 10 MB default
            self.sizeLimitBytes = try container.decodeIfPresent(Int64.self, forKey: .sizeLimitBytes) ?? 10 * 1024 * 1024

            try self.validate()
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

        /// Validates struct-local constraints.
        public func validate() throws {
            let isFileURL = self.resource.flatMap(URL.init(string:))?.scheme == "file"
            guard !self.service.isEmpty || isFileURL else {
                throw ConfigError(
                    code: .internalError, message: "No service config or file:// URL was provided for bundle config.")
            }
        }

        /// Validates constraints that require context from the parent `Config` struct.
        public func validateWithContext(name: String, services: [String: ServiceConfig], keys: [String: KeyConfig])
            throws
        {
            // Prevent bundle referencing a non-existent service.
            guard self.service.isEmpty || services[self.service] != nil else {
                throw ConfigError(
                    code: .internalError,
                    message:
                        "Bundle config for '\(name)' references non-existent service: '\(self.service)'"
                )
            }
            // If no service specified, require a file:// URL to load from disk.
            guard !self.service.isEmpty || (URL(string: self.resource ?? "")?.scheme == "file") else {
                throw ConfigError(
                    code: .internalError,
                    message:
                        "Bundle config for '\(name)' has no service config or file:// URL resource config. \(self.resource ?? "(nil)")"
                )
            }

            try self.signing?.validateWithContext(keys: keys)
        }

        /// Returns a new config with all context-dependent properties resolved.
        ///
        /// This follows the "resolve" pattern: some properties are defined
        /// in separate top-level config sections and aren't available at decode
        /// time. The parent config calls this method during its resolution phase
        /// to produce a fully-populated instance.
        public func resolved(withKeys keys: [String: KeyConfig]) throws -> BundleSourceConfig {
            var resolvedSigning = try self.signing?.resolved(withKeys: keys)
            if !keys.isEmpty && resolvedSigning == nil {
                resolvedSigning = BundleVerificationConfig(publicKeys: keys, keyID: "", scope: "", exclude: [])
            }

            return try BundleSourceConfig(
                downloaderConfig: downloaderConfig,
                service: service,
                resource: resource,
                signing: resolvedSigning,
                persist: persist,
                sizeLimitBytes: sizeLimitBytes
            )
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
