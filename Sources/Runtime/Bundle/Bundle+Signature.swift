import AST
import Foundation
import JWTKit
import Rego

// Ported from: v1/bundle/bundle.go
extension OPA.Bundle {
    /// A convenience struct that condenses/expands the bundle's signatures directly.
    // OPA uses a JWT in JWS format, so we use a library to automate the ugly bits.
    public struct Signatures: Codable, Equatable {
        public let fileSignatures: [String: FileInfo]
        public let plugin: String?

        public init(fileSignatures: [String: FileInfo] = [:], plugin: String? = nil) {
            self.fileSignatures = fileSignatures
            self.plugin = plugin
        }

        public init(jwt: String, plugin: String? = nil) {
            // Parse the JWT, verifies its signature, and decodes its content
            let payload = try await keys.verify(exampleJWT, as: ExamplePayload.self)
            print(payload)
        }

    }

    /// Represents an array of JWTs that encapsulate the signatures for the bundle.
    public struct SignaturesConfig: Codable, Equatable {
        public var signatures: [String]?
        public var plugin: String?

        public init(signatures: [String]? = nil, plugin: String? = nil) {
            self.signatures = signatures
            self.plugin = plugin
        }

        public init(fromJSON jsonData: Data) throws {
            self = try JSONDecoder().decode(SignaturesConfig.self, from: jsonData)
        }

        private enum CodingKeys: String, CodingKey {
            case signatures
            case plugin
        }
    }

    /// Represents the decoded JWT payload from the signature.
    public struct SignaturesPayload: Codable, Equatable {
        public var files: [FileInfo]
        /// Deprecated: use `kid` in the JWT header instead.
        public var keyID: String
        public var scope: String
        public var issuedAt: Int64
        public var issuer: String

        public init(
            files: [FileInfo],
            keyID: String,
            scope: String,
            issuedAt: Int64,
            issuer: String
        ) {
            self.files = files
            self.keyID = keyID
            self.scope = scope
            self.issuedAt = issuedAt
            self.issuer = issuer
        }

        private enum CodingKeys: String, CodingKey {
            case files
            case keyID = "keyid"
            case scope
            case issuedAt = "iat"
            case issuer = "iss"
        }
    }

    /// Contains the hashing algorithm used for the file's signature, the resulting digest, etc.
    public struct FileInfo: Codable, Equatable {
        public var name: String
        public var hash: String
        public var algorithm: String

        public init(name: String, hash: String, algorithm: String) {
            self.name = name
            self.hash = hash
            self.algorithm = algorithm
        }
    }

    public struct BundleSignaturesPayload: JWTPayload {
        var sub: SubjectClaim
        var exp: ExpirationClaim
        var admin: BoolClaim

        public func verify(using _: some JWTAlgorithm) throws {
            try self.exp.verifyNotExpired()
        }
    }
}
