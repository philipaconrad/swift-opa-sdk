import Config
import Foundation
import Rego

extension OPA {
    /// DiskBasedBundleLoader abstracts over folder and tarball bundles.
    public struct DiskBasedBundleLoader: BundleLoader {
        public let name: String
        public let fetchURL: URL
        public let polling: PollingConfig?

        public init(config: OPA.Config, bundleResourceName: String) throws {
            self.name = bundleResourceName
            guard let resource = config.bundles[bundleResourceName] else {
                throw RuntimeError(
                    code: .internalError,
                    message: "No bundle config was found for bundle resource \(bundleResourceName)."
                )
            }

            guard let url = URL(string: resource.resource ?? "") else {
                throw RuntimeError(
                    code: .internalError,
                    message: "Invalid URL for bundle config \(name): \(resource.resource ?? "")"
                )
            }

            // If no bundle service specified to fetch from, make sure we have a file URL to load from disk.
            guard !(resource.service.isEmpty && url.scheme != "file") else {
                throw RuntimeError(
                    code: .internalError,
                    message: "No service config or file:// URL was provided for bundle config \(name)."
                )
            }

            self.polling = resource.downloaderConfig.polling
            self.fetchURL = url
        }

        // If the resource is a file URL, we can load it.
        public static func compatibleWithConfig(config: Config, bundleResourceName: String) -> Bool {
            guard let resource = config.bundles[bundleResourceName] else {
                return false
            }

            return (URL(string: resource.resource ?? "")?.scheme == "file")
        }

        public func load() async -> Result<Bundle, any Swift.Error> {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: self.fetchURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Assert directory not empty before attempting to load it as a bundle.
                    do {
                        guard !(try FileManager.default.contentsOfDirectory(atPath: self.fetchURL.path).isEmpty)
                        else {
                            throw OPA.Bundle.LoadError.unsupported("Directory was empty")
                        }
                    } catch {
                        return .failure(
                            RuntimeError(
                                code: .internalError,
                                message:
                                    "bundle \(name) failed to load with error: \(error)"
                            ))
                    }
                    // Directory not empty.
                    do {
                        let bundle = try Bundle.decodeFromDirectory(fromDir: self.fetchURL)
                        return .success(bundle)
                    } catch {
                        return .failure(error)
                    }
                } else {
                    do {
                        let bundleData = try Data(contentsOf: self.fetchURL)
                        let bundle = try Bundle.decodeFromTarball(from: bundleData)
                        return .success(bundle)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            return .failure(
                RuntimeError(
                    code: .internalError,
                    message:
                        "bundle \(name) failed to load. No file or directory found."
                ))
        }
    }
}
