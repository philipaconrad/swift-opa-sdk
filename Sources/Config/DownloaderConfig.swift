import AST
import Foundation
import Rego

extension OPA {
    // MARK: - Plugin Trigger Mode

    /// Defines the trigger mode utilized by a plugin for bundle download, log upload, etc.
    public enum PluginTriggerMode: String, Codable, Sendable {
        case immediate = "immediate"
        case periodic = "periodic"
        case manual = "manual"

        public static let `default` = PluginTriggerMode.periodic
    }

    // MARK: - Polling Configuration

    /// Represents polling configuration for the downloader.
    // From: v1/download/config.go
    public struct PollingConfig: Codable, Sendable {
        public let minDelaySeconds: Int64?
        public let maxDelaySeconds: Int64?
        public let longPollingTimeoutSeconds: Int64?

        public init(
            minDelaySeconds: Int64? = nil,
            maxDelaySeconds: Int64? = nil,
            longPollingTimeoutSeconds: Int64? = nil
        ) {
            self.minDelaySeconds = minDelaySeconds
            self.maxDelaySeconds = maxDelaySeconds
            self.longPollingTimeoutSeconds = longPollingTimeoutSeconds
        }

        private enum CodingKeys: String, CodingKey {
            case minDelaySeconds = "min_delay_seconds"
            case maxDelaySeconds = "max_delay_seconds"
            case longPollingTimeoutSeconds = "long_polling_timeout_seconds"
        }
    }

    // MARK: - Downloader Configuration

    /// Represents the configuration for the downloader.
    // From: v1/download/config.go
    public struct DownloaderConfig: Codable, Sendable {
        public let trigger: PluginTriggerMode?
        public let polling: PollingConfig?

        public init(
            trigger: PluginTriggerMode? = nil,
            polling: PollingConfig? = nil
        ) {
            self.trigger = trigger
            self.polling = polling
        }
    }
}
