import Foundation

// MARK: - Bearer Authentication Plugin

/// Authentication via a bearer token in the HTTP Authorization header
// From: v1/plugins/rest/auth.go
public struct BearerAuthPlugin: Codable, Sendable, Equatable {
    public let token: String?
    public let tokenPath: String?
    public let scheme: String?

    public init(
        token: String? = nil,
        tokenPath: String? = nil,
        scheme: String = "Bearer"
    ) {
        self.token = token
        self.tokenPath = tokenPath
        self.scheme = scheme
    }

    private enum CodingKeys: String, CodingKey {
        case token
        case tokenPath = "token_path"
        case scheme
    }
}
