import AsyncHTTPClient
import Config
import Foundation
import Rego

extension OPA {
    /// RESTClientBundleLoader abstracts over OPA's HTTP-based bundle sources.
    public struct RESTClientBundleLoader: BundleLoader {
        public let name: String
        public let fetchURL: URL
        public var client: HTTPClient

        public init(
            services: [String: ServiceConfig], name: String, resource: BundleSourceConfig, httpClient: HTTPClient? = nil
        )
            throws
        {
            self.name = name
            // guard let url = URL(string: resource.resource ?? "") else {
            //     throw RuntimeError(
            //         code: .internalError,
            //         message: "Invalid URL for bundle config \(name): \(resource.resource ?? "")"
            //     )
            // }
            // // If no bundle service specified to fetch from, make sure we have a file URL to load from disk.
            // guard !(resource.service.isEmpty && url.scheme != "file") else {
            //     throw RuntimeError(
            //         code: .internalError,
            //         message: "No service config or file:// URL was provided for bundle config \(name)."
            //     )
            // }
            // TODO: Validate the URL by combining parts from both the service and resource.
            self.fetchURL = url
            self.client = httpClient
        }

        // If the resource is for a compatible bundle source, we can load it.
        public static func compatibleWithConfig(services: [String: ServiceConfig], resource: BundleSourceConfig) -> Bool
        {
            let isFileURL = (URL(string: resource.resource ?? "")?.scheme == "file")
            guard !isFileURL && !resource.service.isEmpty else {
                return false  // Bail if no service referenced, or if it's a file URL.
            }

            guard let service = services[resource.service] else {
                return false
            }

            switch service.credentials {
            case .bearer(_), .clientTLS(_): return true
            // Other REST client types not implemented yet.
            default: return false
            }
        }

        public func load() -> Result<Bundle, any Swift.Error> {
            return .failure(RuntimeError(code: .internalError, message: "Not Implemented Yet"))
        }
    }
}
