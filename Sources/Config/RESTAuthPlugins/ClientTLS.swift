import Foundation
import Rego

extension OPA {
    // MARK: - Client TLS Authentication Plugin

    /// Authentication via client certificate on a TLS connection
    // From: v1/plugins/rest/auth.go
    public struct ClientTLSAuthPlugin: Codable, Sendable, Equatable {
        /// Filename for the public key certificate.
        public let cert: String
        /// Filename for the private key.
        public let privateKey: String
        /// Passphrase for the private key.
        public let privateKeyPassphrase: String?
        /// Deprecated: Use `services[_].tls.ca_cert` instead
        public let caCert: String?
        /// Deprecated: Use `services[_].tls.system_ca_required` instead
        public let systemCARequired: Bool?
        public let certRereadIntervalSeconds: Int64?

        public init(
            cert: String,
            privateKey: String,
            privateKeyPassphrase: String? = nil,
            caCert: String? = nil,
            systemCARequired: Bool? = nil,
            certRereadIntervalSeconds: Int64? = nil
        ) throws {
            self.cert = cert
            self.privateKey = privateKey
            self.privateKeyPassphrase = privateKeyPassphrase
            self.caCert = caCert
            self.systemCARequired = systemCARequired
            self.certRereadIntervalSeconds = certRereadIntervalSeconds
            try self.validate()
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.cert = try container.decode(String.self, forKey: .cert)
            self.privateKey = try container.decode(String.self, forKey: .privateKey)
            self.privateKeyPassphrase = try container.decodeIfPresent(String.self, forKey: .privateKeyPassphrase)
            self.caCert = try container.decodeIfPresent(String.self, forKey: .caCert)
            self.systemCARequired = try container.decodeIfPresent(Bool.self, forKey: .systemCARequired)
            self.certRereadIntervalSeconds = try container.decodeIfPresent(
                Int64.self, forKey: .certRereadIntervalSeconds)
            try self.validate()
        }

        /// Validates struct-local constraints.
        public func validate() throws {
            guard !cert.isEmpty else {
                throw ConfigError(
                    code: .internalError,
                    message: "client certificate is needed when client TLS is enabled"
                )
            }
            guard !privateKey.isEmpty else {
                throw ConfigError(
                    code: .internalError,
                    message: "private key is needed when client TLS is enabled"
                )
            }
        }

        /// Validates constraints that require context from the parent service config.
        public func validateWithContext(serviceTLS: ServerTLSConfig?) throws {
            // If the service already provides a TLS CA cert, the deprecated
            // plugin-level ca_cert should not also be specified.
            if let serviceTLS, serviceTLS.caCert != nil, caCert != nil {
                throw ConfigError(
                    code: .internalError,
                    message:
                        "Deprecated 'credentials.client_tls.ca_cert' must not be specified alongside 'tls.ca_cert'"
                )
            }
        }

        private enum CodingKeys: String, CodingKey {
            case cert
            case privateKey = "private_key"
            case privateKeyPassphrase = "private_key_passphrase"
            case caCert = "ca_cert"
            case systemCARequired = "system_ca_required"
            case certRereadIntervalSeconds = "cert_reread_interval_seconds"
        }
    }
}
