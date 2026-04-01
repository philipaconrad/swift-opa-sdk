import AsyncHTTPClient
import Config
import Foundation
import NIOCore  // Needed for type TimeAmount
import NIOHTTP1  // Needed for type HTTPHeaders
import Rego

extension OPA {
    /// RESTClientBundleLoader abstracts over OPA's HTTP-based bundle sources.
    public struct RESTClientBundleLoader: HTTPBundleLoader, BundleLoader {
        public let name: String
        public let fetchURL: URL
        public private(set) var etag: String
        public let serviceConfig: ServiceConfig
        public let bundleConfig: BundleSourceConfig
        public let customHeaders: [String: String]
        public var httpClient: HTTPClient
        public let polling: PollingConfig?
        private var lastBundle: OPA.Bundle?
        private var longPollingEnabled: Bool

        public init(
            config: OPA.Config,
            bundleResourceName: String
        ) throws {
            self = try Self.init(config: config, bundleResourceName: bundleResourceName, etag: nil)
        }

        public init(
            config: Rego.OPA.Config, bundleResourceName: String, etag: String? = nil, headers: [String: String]? = nil,
            httpClient: AsyncHTTPClient.HTTPClient? = nil
        ) throws {
            guard let resource = config.bundles[bundleResourceName] else {
                throw RuntimeError(
                    code: .internalError,
                    message: "No bundle config was found for bundle resource \(bundleResourceName)."
                )
            }
            let name = bundleResourceName

            // Fail if no bundle service specified.
            guard !resource.service.isEmpty else {
                throw RuntimeError(
                    code: .internalError,
                    message: "No service config was provided for bundle config \(name)."
                )
            }

            // Fail if bundle service is not found in the config.
            guard let service = config.services[resource.service] else {
                throw RuntimeError(
                    code: .internalError,
                    message: "No service config was found for bundle config \(name)."
                )
            }

            self.name = name
            self.fetchURL = service.url.appending(path: resource.resource ?? "/bundle/\(name)")
            self.etag = etag ?? ""
            self.serviceConfig = service
            self.bundleConfig = resource
            self.customHeaders = headers ?? [:]
            self.httpClient = httpClient ?? HTTPClient.shared
            self.polling = resource.downloaderConfig.polling
            self.lastBundle = nil
            self.longPollingEnabled = false
        }

        // If the resource is for a compatible bundle source, we can load it.
        public static func compatibleWithConfig(config: Config, bundleResourceName: String) -> Bool {
            guard let resource = config.bundles[bundleResourceName] else {
                return false
            }

            let isFileURL = (URL(string: resource.resource ?? "")?.scheme == "file")
            guard !isFileURL && !resource.service.isEmpty else {
                return false  // Bail if no service referenced, or if it's a file URL.
            }

            guard let service = config.services[resource.service] else {
                return false
            }

            switch service.credentials {
            case .defaultNoAuth, .bearer(_), .clientTLS(_): return true
            // Other REST client types not implemented yet.
            default: return false
            }
        }

        // Adjust headers, then call the appropriate backend for fetching the bundle.
        // Mutation required for Etag header handling (also requires caching last good bundle).
        public mutating func load() async -> Result<OPA.Bundle, any Swift.Error> {
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

            // Set If-None-Match header for ETag supporting servers.
            if !self.etag.isEmpty {
                httpRequest.headers.replaceOrAdd(name: "if-none-match", value: self.etag)
            }

            // Set preference/long-polling headers.
            // Future: Switch to the full "modes=snapshot,delta" when we support delta bundles.
            var prefHeader = "modes=snapshot"
            let usingLongPolling = self.longPollingEnabled && self.polling?.longPollingTimeoutSeconds != nil
            if usingLongPolling {
                prefHeader += ";wait=\(self.polling?.longPollingTimeoutSeconds ?? 0)"
            }
            httpRequest.headers.replaceOrAdd(name: "prefer", value: prefHeader)

            // Launch HTTP request, process response.
            do {
                var longPollingTA: Int64 = 0
                if let longPollTimeout = self.polling?.longPollingTimeoutSeconds, usingLongPolling {
                    longPollingTA = longPollTimeout
                }

                let response =
                    if longPollingTA > 0 {
                        try await self.httpClient.execute(httpRequest, timeout: .seconds(longPollingTA))
                    } else {
                        try await self.httpClient.execute(httpRequest, deadline: NIODeadline.distantFuture)
                    }

                // Future: Add logger warning if Content-Type header values are off. (Validation done by OPA)

                // Collect the full response body into a ByteBuffer.
                let maxBytesLimit = 50 * 1024 * 1024  // 50 MB
                let body = try await response.body.collect(upTo: maxBytesLimit)

                if response.status.code == 304 {
                    guard let bundle = self.lastBundle else {
                        return .failure(
                            RuntimeError(
                                code: .internalError,
                                message:
                                    "Bundle download failed. Server returned response code 304 Not Modified, but no prior bundle cached."
                            ))
                    }
                    return .success(bundle)
                    // Otherwise, fall through to error handler.
                }

                guard (200..<300).contains(response.status.code) else {
                    throw RuntimeError(
                        code: .internalError,
                        message: "Bundle download failed with response code: \(response.status.code)")
                }

                // Convert ByteBuffer to Data.
                let data = Data(body.readableBytesView)

                // Decode the tarball into an OPA.Bundle.
                let newBundle = try OPA.Bundle.decodeFromTarball(from: data)

                // Cache last bundle, so we can handle the "no changes case".
                self.lastBundle = newBundle
                self.etag = response.headers["etag"].first ?? ""
                self.longPollingEnabled = isLongPollingSupported(headers: response.headers)
                return .success(newBundle)
            } catch {
                self.etag = ""
                return .failure(error)
            }
        }

        private func isLongPollingSupported(headers: HTTPHeaders) -> Bool {
            return headers["content-type"].contains("application/vnd.openpolicyagent.bundles")
        }

        public func isLongPollingEnabled() -> Bool {
            return self.longPollingEnabled
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
