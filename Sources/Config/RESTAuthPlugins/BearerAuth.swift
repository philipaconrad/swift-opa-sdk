import Foundation
import Rego

extension OPA {
    // MARK: - Bearer Authentication Plugin

    /// Authentication via a bearer token in the HTTP Authorization header
    // From: v1/plugins/rest/auth.go
    public struct BearerAuthPlugin: Codable, Sendable, Equatable {
        public let token: String?
        public let tokenPath: String?
        public let scheme: String

        /// When true, the token is base64-encoded before use (needed by OCI downloads).
        /// Not serialized – set during resolution.
        public let encode: Bool

        public init(
            token: String? = nil,
            tokenPath: String? = nil,
            scheme: String = "Bearer",
            encode: Bool = false
        ) throws {
            self.token = token
            self.tokenPath = tokenPath
            self.scheme = scheme.isEmpty ? "Bearer" : scheme
            self.encode = encode
            try self.validate()
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.token = try container.decodeIfPresent(String.self, forKey: .token)
            self.tokenPath = try container.decodeIfPresent(String.self, forKey: .tokenPath)
            let scheme = try container.decodeIfPresent(String.self, forKey: .scheme) ?? "Bearer"
            self.scheme = scheme.isEmpty ? "Bearer" : scheme
            self.encode = false
            try self.validate()
        }

        /// Validates struct-local constraints.
        /// Ported from Go's `bearerAuthPlugin.NewClient` validation.
        public func validate() throws {
            let hasToken = token != nil && !(token?.isEmpty ?? true)
            let hasTokenPath = tokenPath != nil && !(tokenPath?.isEmpty ?? true)
            // We want either a token or token path. Both or neither being present are error conditions.
            if (hasToken && hasTokenPath) || (!hasToken && !hasTokenPath) {
                throw ConfigError(
                    code: .internalError,
                    message:
                        "Invalid config: specify a value for either the \"token\" or \"token_path\" field"
                )
            }
        }

        /// Returns a new config with all context-dependent properties resolved.
        ///
        /// This follows the "resolve" pattern: some properties depend on the
        /// parent service configuration and aren't available at decode time.
        /// The parent config calls this method during its resolution phase to
        /// produce a fully-populated instance.
        ///
        /// Ported from Go's `bearerAuthPlugin.NewClient`.
        ///
        /// - Parameter serviceType: The type of the owning service (e.g. `"oci"`).
        public func resolved(serviceType: String? = nil) throws -> BearerAuthPlugin {
            // Standard REST clients use the bearer token as-is, but the
            // OCI downloader needs it base64-encoded before signing a request.
            return try BearerAuthPlugin(
                token: token,
                tokenPath: tokenPath,
                scheme: scheme,
                encode: serviceType == "oci"
            )
        }

        private enum CodingKeys: String, CodingKey {
            case token
            case tokenPath = "token_path"
            case scheme
            // encode is not serialized (matches Go's unexported field)
        }
    }
}
