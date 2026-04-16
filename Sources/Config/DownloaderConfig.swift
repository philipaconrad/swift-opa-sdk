import Foundation
import Rego

extension OPA {
    // MARK: - Plugin Trigger Mode

    /// Defines the trigger mode utilized by a plugin for bundle download, log upload, etc.
    public enum TriggerMode: String, Codable, Sendable {
        case immediate = "immediate"
        case periodic = "periodic"
        case manual = "manual"

        public static let `default` = TriggerMode.periodic

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let value = TriggerMode(rawValue: rawValue) else {
                throw ConfigError(
                    code: .internalError,
                    message:
                        "invalid trigger mode '\(rawValue)' (want '\(TriggerMode.periodic.rawValue)' or '\(TriggerMode.manual.rawValue)')"
                )
            }
            self = value
        }
    }

    // MARK: - Polling Configuration

    /// Represents polling configuration for the downloader.
    // From: v1/download/config.go
    public struct PollingConfig: Codable, Equatable, Sendable {
        public let minDelaySeconds: Int64?
        public let maxDelaySeconds: Int64?
        public let longPollingTimeoutSeconds: Int64?

        public static let defaultMinDelaySeconds: Int64 = 60
        public static let defaultMaxDelaySeconds: Int64 = 120
        private static let nsPerSecond: Int64 = 1_000_000_000

        /// Minimum delay in nanoseconds, using defaults when no user value is provided.
        public var minDelayNanoseconds: Int64 {
            let seconds = minDelaySeconds ?? Self.defaultMinDelaySeconds
            return seconds * Self.nsPerSecond
        }

        /// Maximum delay in nanoseconds, using defaults when no user value is provided.
        public var maxDelayNanoseconds: Int64 {
            let seconds = maxDelaySeconds ?? Self.defaultMaxDelaySeconds
            return seconds * Self.nsPerSecond
        }

        public init(
            minDelaySeconds: Int64? = nil,
            maxDelaySeconds: Int64? = nil,
            longPollingTimeoutSeconds: Int64? = nil
        ) throws {
            self.minDelaySeconds = minDelaySeconds
            self.maxDelaySeconds = maxDelaySeconds
            self.longPollingTimeoutSeconds = longPollingTimeoutSeconds
            try self.validate()
        }

        /// Validates struct-local constraints.
        public func validate() throws {
            switch (minDelaySeconds, maxDelaySeconds) {
            case (.some(let minVal), .some(let maxVal)):
                if maxVal < minVal {
                    throw ConfigError(
                        code: .internalError,
                        message: "max polling delay must be >= min polling delay"
                    )
                }
            case (.some, .none):
                throw ConfigError(
                    code: .internalError,
                    message: "polling configuration missing 'max_delay_seconds'"
                )
            case (.none, .some):
                throw ConfigError(
                    code: .internalError,
                    message: "polling configuration missing 'min_delay_seconds'"
                )
            case (.none, .none):
                break
            }

            if let longPolling = longPollingTimeoutSeconds, longPolling < 1 {
                throw ConfigError(
                    code: .internalError,
                    message: "'long_polling_timeout_seconds' must be at least 1"
                )
            }
        }

        private enum CodingKeys: String, CodingKey {
            case minDelaySeconds = "min_delay_seconds"
            case maxDelaySeconds = "max_delay_seconds"
            case longPollingTimeoutSeconds = "long_polling_timeout_seconds"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let minDelaySeconds = try container.decodeIfPresent(Int64.self, forKey: .minDelaySeconds)
            let maxDelaySeconds = try container.decodeIfPresent(Int64.self, forKey: .maxDelaySeconds)
            let longPollingTimeoutSeconds = try container.decodeIfPresent(
                Int64.self, forKey: .longPollingTimeoutSeconds)

            try self.init(
                minDelaySeconds: minDelaySeconds,
                maxDelaySeconds: maxDelaySeconds,
                longPollingTimeoutSeconds: longPollingTimeoutSeconds
            )
        }
    }

    // MARK: - Downloader Configuration

    /// Represents the configuration for the downloader.
    // From: v1/download/config.go
    public struct DownloaderConfig: Codable, Equatable, Sendable {
        public let trigger: TriggerMode?
        public let polling: PollingConfig?

        /// The set of trigger modes valid for the downloader.
        private static let validTriggerModes: Set<TriggerMode> = [
            .periodic,
            .manual,
        ]

        public init(
            trigger: TriggerMode? = nil,
            polling: PollingConfig? = nil
        ) throws {
            self.trigger = trigger
            self.polling = polling
            try self.validate()
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let trigger = try container.decodeIfPresent(TriggerMode.self, forKey: .trigger)
            let polling = try container.decodeIfPresent(PollingConfig.self, forKey: .polling)

            try self.init(
                trigger: trigger,
                polling: polling
            )
        }

        private enum CodingKeys: String, CodingKey {
            case trigger
            case polling
        }

        /// Validates struct-local constraints.
        public func validate() throws {
            if let trigger = trigger, !Self.validTriggerModes.contains(trigger) {
                throw ConfigError(
                    code: .internalError,
                    message:
                        "invalid trigger mode '\(trigger.rawValue)' (want '\(TriggerMode.periodic.rawValue)' or '\(TriggerMode.manual.rawValue)')"
                )
            }
        }
    }
}
