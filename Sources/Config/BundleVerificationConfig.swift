import Foundation
import Rego

extension OPA {
    // MARK: - Bundle Verification Configuration

    /// Represents the key configuration used to verify a signed bundle.
    /// In the ``resolved`` method, we pass down the list of all known public
    /// keys, as bundles can select the key ID (`kid`) used for
    /// verification in the bundle signature JWT header.
    // From: v1/keys/keys.go
    public struct BundleVerificationConfig: Codable, Equatable, Sendable {
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
}
