import Foundation
import Rego

private let azureIMDSEndpoint = "http://169.254.169.254/metadata/identity/oauth2/token"
private let defaultAPIVersion = "2018-02-01"
private let defaultResource = "https://storage.azure.com/"
private let defaultAPIVersionForAppServiceMsi = "2019-08-01"
private let defaultKeyVaultAPIVersion = "7.4"

extension OPA {
    // MARK: - Azure Managed Identities Authentication Plugin

    public struct AzureManagedIdentitiesToken: Codable, Sendable, Equatable {
        public let accessToken: String
        public let expiresIn: String
        public let expiresOn: String
        public let notBefore: String
        public let resource: String
        public let tokenType: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case expiresOn = "expires_on"
            case notBefore = "not_before"
            case resource
            case tokenType = "token_type"
        }
    }

    public struct AzureManagedIdentitiesError: Error, Sendable, Equatable {
        public let error: String
        public let errorDescription: String
        public let endpoint: String
        public let statusCode: Int

        public var description: String {
            "\(statusCode) \(error) retrieving azure token from \(endpoint): \(errorDescription)"
        }
    }

    /// Uses an Azure Managed Identities token's access token for bearer authorization
    // From: v1/plugins/rest/azure.go
    public struct AzureManagedIdentitiesAuthPlugin: Codable, Sendable, Equatable {
        public let endpoint: String
        public let apiVersion: String
        public let resource: String
        public let objectID: String
        public let clientID: String
        public let miResID: String
        public let useAppServiceMsi: Bool

        enum CodingKeys: String, CodingKey {
            case endpoint
            case apiVersion = "api_version"
            case resource
            case objectID = "object_id"
            case clientID = "client_id"
            case miResID = "mi_res_id"
            case useAppServiceMsi = "use_app_service_msi"
        }
        public init(
            endpoint: String = "",
            apiVersion: String = "",
            resource: String = "",
            objectID: String = "",
            clientID: String = "",
            miResID: String = ""
        ) {
            let resolvedUseAppServiceMsi: Bool
            if endpoint.isEmpty {
                if let identityEndpoint = ProcessInfo.processInfo.environment["IDENTITY_ENDPOINT"],
                    !identityEndpoint.isEmpty
                {
                    self.endpoint = identityEndpoint
                    resolvedUseAppServiceMsi = true
                } else {
                    self.endpoint = azureIMDSEndpoint
                    resolvedUseAppServiceMsi = false
                }
            } else {
                self.endpoint = endpoint
                resolvedUseAppServiceMsi = false
            }
            self.useAppServiceMsi = resolvedUseAppServiceMsi

            self.resource = resource.isEmpty ? defaultResource : resource

            if apiVersion.isEmpty {
                self.apiVersion =
                    resolvedUseAppServiceMsi
                    ? defaultAPIVersionForAppServiceMsi
                    : defaultAPIVersion
            } else {
                self.apiVersion = apiVersion
            }

            self.objectID = objectID
            self.clientID = clientID
            self.miResID = miResID
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                endpoint: try container.decodeIfPresent(String.self, forKey: .endpoint) ?? "",
                apiVersion: try container.decodeIfPresent(String.self, forKey: .apiVersion) ?? "",
                resource: try container.decodeIfPresent(String.self, forKey: .resource) ?? "",
                objectID: try container.decodeIfPresent(String.self, forKey: .objectID) ?? "",
                clientID: try container.decodeIfPresent(String.self, forKey: .clientID) ?? "",
                miResID: try container.decodeIfPresent(String.self, forKey: .miResID) ?? ""
            )
        }

        public func validateWithContext(serviceType: String) throws {
            guard serviceType != "oci" else {
                throw ConfigError(
                    code: .internalError,
                    message: "azure managed identities auth: OCI service not supported"
                )
            }
        }
    }
}
