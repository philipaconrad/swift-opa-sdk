import AST
import AsyncHTTPClient
import Config
import Foundation
import Rego

extension OPA {
    /// BundleVerifier abstracts over the details of verifying a bundle's signatures.
    public protocol BundleVerifier: Sendable {
        Verify() throws
    }
}
