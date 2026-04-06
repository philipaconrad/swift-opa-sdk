import Foundation
import Rego

private let defaultGCPMetadataEndpoint = "http://metadata.google.internal"
private let defaultAccessTokenPath = "/computeMetadata/v1/instance/service-accounts/default/token"
private let defaultIdentityTokenPath = "/computeMetadata/v1/instance/service-accounts/default/identity"

extension OPA {
    // MARK: - GCP Metadata Authentication Plugin

    /// Represents authentication via GCP metadata service
    // From: v1/plugins/rest/gcp.go
    public struct GCPMetadataAuthPlugin: Codable, Sendable, Equatable {
        public let accessTokenPath: String
        public let audience: String?
        public let endpoint: String
        public let identityTokenPath: String
        public let scopes: [String]

        enum CodingKeys: String, CodingKey {
            case accessTokenPath = "access_token_path"
            case audience
            case endpoint
            case identityTokenPath = "identity_token_path"
            case scopes
        }

        // Note: The default values set here are derived from the `NewClient()`
        // method for this type over in OPA. This behavior may be refactored in
        // in the future when we decide where config validation should be happening.
        public init(
            accessTokenPath: String? = nil,
            audience: String? = nil,
            endpoint: String? = nil,
            identityTokenPath: String? = nil,
            scopes: [String] = []
        ) throws {
            self.accessTokenPath = accessTokenPath ?? defaultAccessTokenPath
            self.audience = audience
            self.endpoint = endpoint ?? defaultGCPMetadataEndpoint
            self.identityTokenPath = identityTokenPath ?? defaultIdentityTokenPath
            self.scopes = scopes
            try self.validate()
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let accessTokenPath =
                try container.decodeIfPresent(String.self, forKey: .accessTokenPath)
            self.accessTokenPath = accessTokenPath ?? defaultAccessTokenPath

            self.audience = try container.decodeIfPresent(String.self, forKey: .audience)

            let endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
            self.endpoint = endpoint ?? defaultGCPMetadataEndpoint

            let identityTokenPath =
                try container.decodeIfPresent(String.self, forKey: .identityTokenPath)

            self.identityTokenPath = identityTokenPath ?? defaultIdentityTokenPath
            self.scopes = try container.decodeIfPresent([String].self, forKey: .scopes) ?? []

            try self.validate()
        }

        /// Validates struct-local constraints.
        /// Ported from Go's `gcpMetadataAuthPlugin.NewClient` validation logic.
        public func validate() throws {
            let hasAudience = self.audience != nil && !self.audience!.isEmpty
            let hasScopes = !self.scopes.isEmpty

            guard hasAudience || hasScopes else {
                throw ConfigError(
                    code: .internalError,
                    message: "audience or scopes is required when gcp metadata is enabled"
                )
            }

            guard !(hasAudience && hasScopes) else {
                throw ConfigError(
                    code: .internalError,
                    message: "either audience or scopes can be set, not both, when gcp metadata is enabled"
                )
            }
        }
    }
}
