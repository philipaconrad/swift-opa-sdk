import AST
import AsyncHTTPClient
import Config
import Foundation
import Rego

extension OPA {

    /// BundleLoader abstracts over the details of retrieving a bundle.
    public protocol BundleLoader {
        /// Needs a public constructor that can build from the config directly.
        init(config: OPA.Config, bundleResourceName: String) throws

        /// Load the bundle, based on the config and any existing state.
        mutating func load() async -> Result<OPA.Bundle, any Swift.Error>

        /// Compatibility check, based on what's in the OPA config.
        static func compatibleWithConfig(config: OPA.Config, bundleResourceName: String) -> Bool
    }

    /// HTTPBundleLoader is a slightly more specialized protocol to allow greater
    /// control for HTTP-based bundle loaders.
    public protocol HTTPBundleLoader: BundleLoader {
        /// Needs a public constructor that can build from the config directly.
        init(
            config: OPA.Config, bundleResourceName: String, etag: String?, headers: [String: String]?,
            httpClient: HTTPClient?) throws

        /// Used by the loader-manging task to determine whether to sleep or not between polls.
        func isLongPollingEnabled() -> Bool
    }
}
