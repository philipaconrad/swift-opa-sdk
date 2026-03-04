import Foundation

// MARK: - Azue Managed Identities Authentication Plugin

private let azureIMDSEndpoint = "http://169.254.169.254/metadata/identity/oauth2/token"
private let defaultAPIVersion = "2018-02-01"
private let defaultResource = "https://storage.azure.com/"
private let defaultAPIVersionForAppServiceMsi = "2019-08-01"
private let defaultKeyVaultAPIVersion = "7.4"

/// Uses an Azure Managed Identities token's access token for bearer authorization
// From: v1/plugins/rest/azure.go
public struct AzureManagedIdentitiesAuthPlugin: Codable, Sendable, Equatable {
    public let endpoint: String
    public let apiVersion: String
    public let resource: String
    public let objectID: String
    public let clientID: String
    public let miResID: String
    public let useAppServiceMsi: Bool?  // Msi -> "Managed Service Identity"

    enum CodingKeys: String, CodingKey {
        case endpoint
        case apiVersion = "api_version"
        case resource
        case objectID = "object_id"
        case clientID = "client_id"
        case miResID = "mi_res_id"
        case useAppServiceMsi = "use_app_service_msi"
    }

    /// Note: If endpoint is left blank, the initializer will look up the `IDENTITY_ENDPOINT` environment variable.
    public init(
        endpoint: String = "",
        apiVersion: String = "",
        resource: String = "",
        objectID: String,
        clientID: String,
        miResID: String
    ) {
        (self.endpoint, self.apiVersion, self.resource, self.useAppServiceMsi) =
            AzureManagedIdentitiesAuthPlugin.getDefaults(
                endpoint, apiVersion, resource)

        self.objectID = objectID
        self.clientID = clientID
        self.miResID = miResID
    }

    private static func getDefaults(_ endpoint: String, _ apiVersion: String, _ resource: String) -> (
        String, String, String, Bool
    ) {
        var outEndpoint = endpoint
        var outApiVersion = apiVersion
        var outResource = resource
        var useAppServiceMsi = false

        if endpoint.isEmpty {
            if let identityEndpoint = ProcessInfo.processInfo.environment["IDENTITY_ENDPOINT"] {
                outEndpoint = identityEndpoint
                useAppServiceMsi = true
            } else {
                outEndpoint = azureIMDSEndpoint
            }
        }

        if resource.isEmpty {
            outResource = defaultResource
        }

        if apiVersion.isEmpty {
            if useAppServiceMsi {
                outApiVersion = defaultAPIVersionForAppServiceMsi
            } else {
                outApiVersion = defaultAPIVersion
            }
        }

        return (outEndpoint, outApiVersion, outResource, useAppServiceMsi)
    }
}
