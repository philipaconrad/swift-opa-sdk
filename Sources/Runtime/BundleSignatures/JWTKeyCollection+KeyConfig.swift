import Config
import Foundation
import JWTKit
import Rego

extension OPA {
    /// Builds a `JWTKeyCollection` from a map of key configurations, loading
    /// only the subset specified.
    ///
    /// - Parameter configs: A dictionary mapping key IDs to their `KeyConfig`.
    /// - Parameter keyIds: A list of key IDs to load.
    /// - Returns: A populated `JWTKeyCollection`.
    /// - Throws: Any error encountered while parsing or loading a key.
    public static func makeJWTKeyCollection(
        from configs: [String: KeyConfig],
        loadingKeys keyIds: [String] = []
    ) async throws -> JWTKeyCollection {
        return try await makeJWTKeyCollection(from: configs.filter({ keyIds.contains($0.key) }))
    }

    /// Builds a `JWTKeyCollection` from a map of key configurations, using
    /// each map key as the `kid` (key identifier) for the corresponding JWT key.
    ///
    /// - Parameter configs: A dictionary mapping key IDs to their `KeyConfig`.
    /// - Returns: A populated `JWTKeyCollection`.
    /// - Throws: Any error encountered while parsing or loading a key.
    public static func makeJWTKeyCollection(
        from configs: [String: KeyConfig]
    ) async throws -> JWTKeyCollection {
        let collection = JWTKeyCollection()

        for (id, config) in configs {
            let kid = JWKIdentifier(string: id)

            switch config.algorithm {

            // MARK: HMAC
            case "HS256":
                await collection.add(hmac: hmacKey(from: config), digestAlgorithm: .sha256, kid: kid)
            case "HS384":
                await collection.add(hmac: hmacKey(from: config), digestAlgorithm: .sha384, kid: kid)
            case "HS512":
                await collection.add(hmac: hmacKey(from: config), digestAlgorithm: .sha512, kid: kid)

            // MARK: RSA (RS*)
            case "RS256":
                try await addRSA(config, to: collection, digest: .sha256, kid: kid)
            case "RS384":
                try await addRSA(config, to: collection, digest: .sha384, kid: kid)
            case "RS512":
                try await addRSA(config, to: collection, digest: .sha512, kid: kid)

            // MARK: RSA-PSS (PS*)
            case "PS256":
                try await addPSS(config, to: collection, digest: .sha256, kid: kid)
            case "PS384":
                try await addPSS(config, to: collection, digest: .sha384, kid: kid)
            case "PS512":
                try await addPSS(config, to: collection, digest: .sha512, kid: kid)

            // MARK: ECDSA
            case "ES256":
                if !config.privateKey.isEmpty {
                    try await collection.add(ecdsa: ES256PrivateKey(pem: config.privateKey), kid: kid)
                } else {
                    try await collection.add(ecdsa: ES256PublicKey(pem: config.key), kid: kid)
                }
            case "ES384":
                if !config.privateKey.isEmpty {
                    try await collection.add(ecdsa: ES384PrivateKey(pem: config.privateKey), kid: kid)
                } else {
                    try await collection.add(ecdsa: ES384PublicKey(pem: config.key), kid: kid)
                }
            case "ES512":
                if !config.privateKey.isEmpty {
                    try await collection.add(ecdsa: ES512PrivateKey(pem: config.privateKey), kid: kid)
                } else {
                    try await collection.add(ecdsa: ES512PublicKey(pem: config.key), kid: kid)
                }

            default:
                throw RuntimeError(
                    code: .internalError,
                    message: "unsupported algorithm '\(config.algorithm)' for key ID \(id)"
                )
            }
        }

        return collection
    }

    // MARK: - Helpers

    private static func hmacKey(from config: KeyConfig) -> HMACKey {
        // HMAC secrets are symmetric; prefer `privateKey` if supplied, else `key`.
        let secret = config.privateKey.isEmpty ? config.key : config.privateKey
        return HMACKey(stringLiteral: secret)
    }

    private static func addRSA(
        _ config: KeyConfig,
        to collection: JWTKeyCollection,
        digest: DigestAlgorithm,
        kid: JWKIdentifier
    ) async throws {
        if !config.privateKey.isEmpty {
            try await collection.add(
                rsa: Insecure.RSA.PrivateKey(pem: config.privateKey),
                digestAlgorithm: digest,
                kid: kid
            )
        } else {
            try await collection.add(
                rsa: Insecure.RSA.PublicKey(pem: config.key),
                digestAlgorithm: digest,
                kid: kid
            )
        }
    }

    private static func addPSS(
        _ config: KeyConfig,
        to collection: JWTKeyCollection,
        digest: DigestAlgorithm,
        kid: JWKIdentifier
    ) async throws {
        if !config.privateKey.isEmpty {
            try await collection.add(
                pss: Insecure.RSA.PrivateKey(pem: config.privateKey),
                digestAlgorithm: digest,
                kid: kid
            )
        } else {
            try await collection.add(
                pss: Insecure.RSA.PublicKey(pem: config.key),
                digestAlgorithm: digest,
                kid: kid
            )
        }
    }
}
