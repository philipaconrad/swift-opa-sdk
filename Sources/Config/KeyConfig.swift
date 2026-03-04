import AST
import Foundation
import Rego

extension OPA {
    // MARK: - Key Configuration

    /// Holds the keys used to sign or verify bundles and tokens.
    // From: v1/keys/keys.go
    public struct KeyConfig: Codable, Sendable {
        public let key: String
        public let privateKey: String
        public let algorithm: String
        public let scope: String

        public init(
            key: String,
            privateKey: String,
            algorithm: String,
            scope: String
        ) {
            self.key = key
            self.privateKey = privateKey
            self.algorithm = algorithm
            self.scope = scope
        }

        private enum CodingKeys: String, CodingKey {
            case key
            case privateKey = "private_key"
            case algorithm
            case scope
        }
    }
}
