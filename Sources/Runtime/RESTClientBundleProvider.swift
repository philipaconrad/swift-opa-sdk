import AsyncHTTPClient
import Config
import Foundation
import Rego

extension OPA {
    /// RESTClientBundleLoader abstracts over OPA's HTTP-based bundle sources.
    public struct RESTClientBundleLoader: BundleLoader {
        public let name: String
        public let fetchURL: URL
        public let serviceConfig: ServiceConfig
        public let bundleConfig: BundleSourceConfig
        public let customHeaders: [String: String]
        public var httpClient: HTTPClient

        public init(
            services: [String: ServiceConfig],
            name: String,
            resource: BundleSourceConfig,
            headers: [String: String] = [:],
            httpClient: HTTPClient? = nil
        )
            throws
        {

            // Fail if no bundle service specified.
            guard !resource.service.isEmpty else {
                throw RuntimeError(
                    code: .internalError,
                    message: "No service config was provided for bundle config \(name)."
                )
            }

            // Fail if bundle service is not found in the config.
            guard let service = services[resource.service] else {
                throw RuntimeError(
                    code: .internalError,
                    message: "No service config was found for bundle config \(name)."
                )
            }

            self.name = name
            self.fetchURL = service.url.appending(path: resource.resource ?? "/bundle/\(name)")
            self.serviceConfig = service
            self.bundleConfig = resource
            self.customHeaders = headers
            self.httpClient = httpClient ?? HTTPClient.shared
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
            case .defaultNoAuth, .bearer(_), .clientTLS(_): return true
            // Other REST client types not implemented yet.
            default: return false
            }
        }

        // Adjust headers, then call the appropriate backend for fetching the bundle.
        public func load() async -> Result<Bundle, any Swift.Error> {
            let headers =
                (self.serviceConfig.headers ?? [:]).merging(
                    self.customHeaders, uniquingKeysWith: { (_, new) in new })

            var httpRequest = HTTPClientRequest(url: self.fetchURL.absoluteString)
            httpRequest.method = .GET
            for (k, v) in headers {
                httpRequest.headers.replaceOrAdd(name: k, value: v)
            }

            // Set authorization headers.
            switch self.serviceConfig.credentials {
            case .defaultNoAuth: break
            case .bearer(let pluginConfig):
                let loader: OPA.BearerAuthPluginLoader = BearerAuthPluginLoader(config: pluginConfig)
                do {
                    try loader.prepare(req: &httpRequest)
                } catch {
                    return .failure(error)
                }
            // case .clientTLS(let plugin):
            //     break
            default:
                return .failure(
                    RuntimeError(
                        code: .internalError,
                        message: "Unsupported bundle service type used for bundle config \(name)."
                    ))
            }

            // Launch HTTP request, process response.
            do {
                let response = try await self.httpClient.execute(httpRequest, timeout: .seconds(30))

                // Collect the full response body into a ByteBuffer.
                let maxBytesLimit = 50 * 1024 * 1024  // 50 MB
                let body = try await response.body.collect(upTo: maxBytesLimit)

                guard (200..<300).contains(response.status.code) else {
                    throw RuntimeError(
                        code: .internalError,
                        message: "Bundle download failed with response code: \(response.status.code)")
                }

                // Convert ByteBuffer to Data
                let data = Data(body.readableBytesView)

                // Decode the tarball into an OPA.Bundle
                return .success(try OPA.Bundle.decodeFromTarball(from: data))
            } catch {
                return .failure(error)
            }
        }
    }

    /// Emulates the same basic functionality as the `rest.bearerAuthPlugin` type from OPA.
    public struct BearerAuthPluginLoader {
        public let config: BearerAuthPlugin

        public init(config: BearerAuthPlugin) {
            self.config = config
        }

        public func prepare(req: inout HTTPClientRequest) throws {
            // Either a token was provided in the config, or we have a tokenPath to fetch the token from.
            var token = self.config.token ?? ""
            if let path = self.config.tokenPath, token.isEmpty {
                let url = URL(
                    filePath: path, directoryHint: .inferFromPath,
                    relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                token = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespaces)
            }

            token = (self.config.encode) ? Data(token.utf8).base64EncodedString() : token

            req.headers.replaceOrAdd(name: "authorization", value: "\(self.config.scheme) \(token)")
        }
    }
}
