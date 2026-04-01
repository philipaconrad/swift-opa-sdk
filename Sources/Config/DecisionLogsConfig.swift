import AST
import Foundation
import Rego

// From: v1/plugins/logs/plugin.go

// MARK: - Constants

/// Minimum amount of time to wait following a failure (100 milliseconds).
public let minRetryDelay: Duration = .milliseconds(100)

public let defaultMinDelaySeconds: Int64 = 300
public let defaultMaxDelaySeconds: Int64 = 600
public let defaultBufferSizeLimitEvents: Int64 = 10_000
public let defaultUploadSizeLimitBytes: Int64 = 32_768  // 32KB limit
public let minUploadSizeLimitBytes: Int64 = 90  // A single event with a decision ID (69 bytes) + empty gzip file (21 bytes)
public let maxUploadSizeLimitBytes: Int64 = 4_294_967_296  // about 4GB
public let defaultBufferSizeLimitBytes: Int64 = 0  // unlimited
public let defaultMaskDecisionPath = "/system/log/mask"
public let defaultDropDecisionPath = "/system/log/drop"
public let logRateLimitExDropCounterName = "decision_logs_dropped_rate_limit_exceeded"
public let logBufferEventDropCounterName = "decision_logs_dropped_buffer_size_limit_exceeded"
public let logBufferSizeLimitExDropCounterName = "decision_logs_dropped_buffer_size_limit_bytes_exceeded"
public let logEncodingFailureCounterName = "decision_logs_encoding_failure"
public let defaultResourcePath = "/logs"
public let sizeBufferType = "size"
public let eventBufferType = "event"

// MARK: - DecisionLogsConfigError

public enum DecisionLogsConfigError: Error, CustomStringConvertible {
    case invalidPluginName(String)
    case invalidServiceName(String)
    case maxDelayLessThanMinDelay
    case missingMaxDelaySeconds
    case missingMinDelaySeconds
    case invalidBufferType(String)
    case bufferSizeLimitBytesNotSupportedForEventBuffer
    case bufferSizeLimitEventsNotSupportedForSizeBuffer
    case mutuallyExclusiveBufferSizeLimitBytesAndDecisionsPerSecond
    case bufferSizeLimitBytesMustBePositive
    case bufferSizeLimitEventsMustBePositive
    case invalidMaskDecision(String, underlying: Error)
    case invalidDropDecision(String, underlying: Error)
    case invalidResourcePath(String, underlying: Error)

    public var description: String {
        switch self {
        case .invalidPluginName(let name):
            return "invalid plugin name \"\(name)\" in decision_logs"
        case .invalidServiceName(let name):
            return "invalid service name \"\(name)\" in decision_logs"
        case .maxDelayLessThanMinDelay:
            return "max reporting delay must be >= min reporting delay in decision_logs"
        case .missingMaxDelaySeconds:
            return "reporting configuration missing 'max_delay_seconds' in decision_logs"
        case .missingMinDelaySeconds:
            return "reporting configuration missing 'min_delay_seconds' in decision_logs"
        case .invalidBufferType(let bufferType):
            return
                "invalid buffer type \"\(bufferType)\", expected \"\(eventBufferType)\" or \"\(sizeBufferType)\""
        case .bufferSizeLimitBytesNotSupportedForEventBuffer:
            return
                "invalid decision_log config, 'buffer_size_limit_bytes' isn't supported for the \(eventBufferType) buffer type"
        case .bufferSizeLimitEventsNotSupportedForSizeBuffer:
            return
                "invalid decision_log config, 'buffer_size_limit_events' isn't supported for the \(sizeBufferType) buffer type"
        case .mutuallyExclusiveBufferSizeLimitBytesAndDecisionsPerSecond:
            return
                "invalid decision_log config, specify either 'buffer_size_limit_bytes' or 'max_decisions_per_second'"
        case .bufferSizeLimitBytesMustBePositive:
            return "invalid decision_log config, 'buffer_size_limit_bytes' must be higher than 0"
        case .bufferSizeLimitEventsMustBePositive:
            return "invalid decision_log config, 'buffer_size_limit_entries' must be higher than 0"
        case .invalidMaskDecision(let path, let underlying):
            return "invalid mask_decision in decision_logs: \"\(path)\": \(underlying)"
        case .invalidDropDecision(let path, let underlying):
            return "invalid drop_decision in decision_logs: \"\(path)\": \(underlying)"
        case .invalidResourcePath(let path, let underlying):
            return "invalid resource path \"\(path)\": \(underlying)"
        }
    }
}

extension OPA {
    // MARK: - ReportingConfig

    /// Represents configuration for the plugin's reporting behaviour.
    public struct ReportingConfig: Codable, Sendable {
        /// Toggles how the buffer stores events; defaults to using bytes.
        public var bufferType: String?

        /// Max size of in-memory size buffer.
        public var bufferSizeLimitBytes: Int64?

        /// Max size of in-memory event channel buffer.
        public var bufferSizeLimitEvents: Int64?

        /// Max size of upload payload.
        public var uploadSizeLimitBytes: Int64?

        /// Min amount of time to wait between successful poll attempts.
        public var minDelaySeconds: Int64?

        /// Max amount of time to wait between poll attempts.
        public var maxDelaySeconds: Int64?

        /// Max number of decision logs to buffer per second.
        public var maxDecisionsPerSecond: Double?

        /// Trigger mode.
        public var trigger: TriggerMode?

        public init(
            bufferType: String? = nil,
            bufferSizeLimitBytes: Int64? = nil,
            bufferSizeLimitEvents: Int64? = nil,
            uploadSizeLimitBytes: Int64? = nil,
            minDelaySeconds: Int64? = nil,
            maxDelaySeconds: Int64? = nil,
            maxDecisionsPerSecond: Double? = nil,
            trigger: TriggerMode? = nil
        ) {
            self.bufferType = bufferType
            self.bufferSizeLimitBytes = bufferSizeLimitBytes
            self.bufferSizeLimitEvents = bufferSizeLimitEvents
            self.uploadSizeLimitBytes = uploadSizeLimitBytes
            self.minDelaySeconds = minDelaySeconds
            self.maxDelaySeconds = maxDelaySeconds
            self.maxDecisionsPerSecond = maxDecisionsPerSecond
            self.trigger = trigger
        }

        enum CodingKeys: String, CodingKey {
            case bufferType = "buffer_type"
            case bufferSizeLimitBytes = "buffer_size_limit_bytes"
            case bufferSizeLimitEvents = "buffer_size_limit_events"
            case uploadSizeLimitBytes = "upload_size_limit_bytes"
            case minDelaySeconds = "min_delay_seconds"
            case maxDelaySeconds = "max_delay_seconds"
            case maxDecisionsPerSecond = "max_decisions_per_second"
            case trigger
        }
    }

    // MARK: - RequestContextConfig

    public struct RequestContextConfig: Codable, Sendable {
        public var httpRequest: HTTPRequestContextConfig?

        public init(httpRequest: HTTPRequestContextConfig? = nil) {
            self.httpRequest = httpRequest
        }

        enum CodingKeys: String, CodingKey {
            case httpRequest = "http"
        }
    }

    // MARK: - HTTPRequestContextConfig

    public struct HTTPRequestContextConfig: Codable, Sendable {
        public var headers: [String]?

        public init(headers: [String]? = nil) {
            self.headers = headers
        }

        enum CodingKeys: String, CodingKey {
            case headers
        }
    }

    // MARK: - DecisionLogsConfig

    /// Represents the plugin configuration.
    public struct DecisionLogsConfig: Codable, Sendable {
        public var plugin: String?
        public var service: String
        public var partitionName: String?
        public var reporting: ReportingConfig
        public var requestContext: RequestContextConfig
        public var maskDecision: String?
        public var dropDecision: String?
        public var consoleLogs: Bool
        public var resource: String?
        public var ndBuiltinCache: Bool?

        /// Creates a new configuration, validating and injecting defaults for all
        /// members that do not require external state.
        ///
        /// - Parameter logger: An optional logging closure for warnings (e.g. upload size clamping).
        /// - Throws: `DecisionLogsConfigError` if validation fails.
        ///
        /// - Note: Validation for services / plugins is done one level up, in the
        ///   top-level `Config` struct.
        public init(
            plugin: String? = nil,
            service: String,
            partitionName: String? = nil,
            reporting: ReportingConfig = ReportingConfig(),
            requestContext: RequestContextConfig = RequestContextConfig(),
            maskDecision: String? = nil,
            dropDecision: String? = nil,
            consoleLogs: Bool = false,
            resource: String? = nil,
            ndBuiltinCache: Bool? = nil,
            logger: ((String) -> Void)? = nil
        ) throws {
            self.plugin = plugin
            self.service = service
            self.partitionName = partitionName
            self.reporting = reporting
            self.requestContext = requestContext
            self.maskDecision = maskDecision
            self.dropDecision = dropDecision
            self.consoleLogs = consoleLogs
            self.resource = resource
            self.ndBuiltinCache = ndBuiltinCache
            try self.validate(logger: logger)
        }

        enum CodingKeys: String, CodingKey {
            case plugin
            case service
            case partitionName = "partition_name"
            case reporting
            case requestContext = "request_context"
            case maskDecision = "mask_decision"
            case dropDecision = "drop_decision"
            case consoleLogs = "console"
            case resource
            case ndBuiltinCache = "nd_builtin_cache"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.plugin = try container.decodeIfPresent(String.self, forKey: .plugin)
            self.service = try container.decode(String.self, forKey: .service)
            self.partitionName = try container.decodeIfPresent(String.self, forKey: .partitionName)
            self.reporting =
                try container.decodeIfPresent(ReportingConfig.self, forKey: .reporting)
                ?? ReportingConfig()
            self.requestContext =
                try container.decodeIfPresent(
                    RequestContextConfig.self, forKey: .requestContext) ?? RequestContextConfig()
            self.maskDecision = try container.decodeIfPresent(String.self, forKey: .maskDecision)
            self.dropDecision = try container.decodeIfPresent(String.self, forKey: .dropDecision)
            self.consoleLogs =
                try container.decodeIfPresent(Bool.self, forKey: .consoleLogs)
                ?? false
            self.resource = try container.decodeIfPresent(String.self, forKey: .resource)
            self.ndBuiltinCache = try container.decodeIfPresent(Bool.self, forKey: .ndBuiltinCache)
            try self.validate()
        }

        // MARK: - Validation & defaults

        /// Validates the configuration and injects defaults for all members
        /// that do not require external state.
        ///
        /// - Parameter logger: An optional logging closure for warnings (e.g. upload size clamping).
        ///
        /// - Note: Validation for services / plugins is done one level up, in the
        ///   top-level `Config` struct.
        public mutating func validate(logger warn: ((String) -> Void)? = nil) throws {
            // min/max delay
            switch (reporting.minDelaySeconds, reporting.maxDelaySeconds) {
            case (.some(let minVal), .some(let maxVal)):
                guard maxVal >= minVal else {
                    throw DecisionLogsConfigError.maxDelayLessThanMinDelay
                }
            case (.some, .none):
                throw DecisionLogsConfigError.missingMaxDelaySeconds
            case (.none, .some):
                throw DecisionLogsConfigError.missingMinDelaySeconds
            case (.none, .none):
                reporting.minDelaySeconds = defaultMinDelaySeconds
                reporting.maxDelaySeconds = defaultMaxDelaySeconds
            }

            // upload size limit
            let requestedUploadLimit = reporting.uploadSizeLimitBytes ?? defaultUploadSizeLimitBytes
            if requestedUploadLimit > maxUploadSizeLimitBytes {
                reporting.uploadSizeLimitBytes = maxUploadSizeLimitBytes
                warn?(
                    "the configured `upload_size_limit_bytes` (\(requestedUploadLimit)) has been set to the maximum limit (\(maxUploadSizeLimitBytes))"
                )
            } else if requestedUploadLimit < minUploadSizeLimitBytes {
                reporting.uploadSizeLimitBytes = minUploadSizeLimitBytes
                warn?(
                    "the configured `upload_size_limit_bytes` (\(requestedUploadLimit)) has been set to the minimum limit (\(minUploadSizeLimitBytes))"
                )
            } else {
                reporting.uploadSizeLimitBytes = requestedUploadLimit
            }

            // buffer type
            reporting.bufferType = reporting.bufferType ?? sizeBufferType
            if let bt = reporting.bufferType, bt != eventBufferType && bt != sizeBufferType {
                throw DecisionLogsConfigError.invalidBufferType(bt)
            }

            // buffer type / limit compatibility
            if reporting.bufferType == eventBufferType && reporting.bufferSizeLimitBytes != nil {
                throw DecisionLogsConfigError.bufferSizeLimitBytesNotSupportedForEventBuffer
            }
            if reporting.bufferType == sizeBufferType && reporting.bufferSizeLimitEvents != nil {
                throw DecisionLogsConfigError.bufferSizeLimitEventsNotSupportedForSizeBuffer
            }

            // mutual exclusivity
            if reporting.bufferSizeLimitBytes != nil && reporting.maxDecisionsPerSecond != nil {
                throw DecisionLogsConfigError
                    .mutuallyExclusiveBufferSizeLimitBytesAndDecisionsPerSecond
            }

            // buffer size limit (bytes)
            if let explicitLimit = reporting.bufferSizeLimitBytes {
                guard explicitLimit > 0 else {
                    throw DecisionLogsConfigError.bufferSizeLimitBytesMustBePositive
                }
            } else {
                reporting.bufferSizeLimitBytes = defaultBufferSizeLimitBytes
            }

            // buffer size limit (events)
            reporting.bufferSizeLimitEvents = reporting.bufferSizeLimitEvents ?? defaultBufferSizeLimitEvents
            guard reporting.bufferSizeLimitEvents! > 0 else {
                throw DecisionLogsConfigError.bufferSizeLimitEventsMustBePositive
            }

            // mask / drop decision paths
            maskDecision = maskDecision ?? defaultMaskDecisionPath
            dropDecision = dropDecision ?? defaultDropDecisionPath

            // TODO: Parse maskDecision via ref.ParseDataPath into maskDecisionRef
            // TODO: Parse dropDecision via ref.ParseDataPath into dropDecisionRef

            // resource path
            if let name = partitionName, !name.isEmpty {
                resource = "/logs/\(name)"
            } else if resource == nil {
                resource = defaultResourcePath
            } else if let r = resource {
                guard URL(string: r) != nil else {
                    throw DecisionLogsConfigError.invalidResourcePath(
                        r, underlying: URLError(.badURL))
                }
            }
        }
    }
}
