import Foundation
import Rego

extension OPA {
    // MARK: - Key Configuration

    /// Holds the keys used to sign or verify bundles and tokens.
    // From: v1/keys/keys.go
    public struct KeyConfig: Codable, Sendable, Equatable {
        public let key: String
        public let privateKey: String
        public let algorithm: String
        public let scope: String

        private static let defaultSigningAlgorithm = "RS256"

        private static let supportedAlgorithms: Set<String> = [
            "ES256", "ES384", "ES512",
            "HS256", "HS384", "HS512",
            "PS256", "PS384", "PS512",
            "RS256", "RS384", "RS512",
        ]

        public static func isSupportedAlgorithm(_ algorithm: String) -> Bool {
            supportedAlgorithms.contains(algorithm)
        }

        public init(
            key: String,
            privateKey: String = "",
            algorithm: String = "",
            scope: String = ""
        ) throws {
            self.key = key
            self.privateKey = privateKey
            self.algorithm = algorithm.isEmpty ? KeyConfig.defaultSigningAlgorithm : algorithm
            self.scope = scope
            try self.validate()
        }

        // Validates struct-local constraints.
        public func validate() throws {
            if !KeyConfig.isSupportedAlgorithm(algorithm) {
                throw ConfigError(
                    code: .internalError,
                    message: "unsupported algorithm '\(algorithm)'"
                )
            }
        }

        // Validates constraints that require context from the parent `Config` struct.
        public func validateWithContext(id: String) throws {
            if key.isEmpty && privateKey.isEmpty {
                throw ConfigError(
                    code: .internalError,
                    message: "invalid keys configuration: no keys provided for key ID \(id)"
                )
            }
        }

        private enum CodingKeys: String, CodingKey {
            case key
            case privateKey = "private_key"
            case algorithm
            case scope
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
            let privateKey = try container.decodeIfPresent(String.self, forKey: .privateKey) ?? ""
            let algorithm = try container.decodeIfPresent(String.self, forKey: .algorithm) ?? ""
            let scope = try container.decodeIfPresent(String.self, forKey: .scope) ?? ""

            try self.init(
                key: key,
                privateKey: privateKey,
                algorithm: algorithm,
                scope: scope
            )
        }
    }
}
