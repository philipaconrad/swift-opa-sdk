import Foundation
import Rego

extension OPA {
    /// A representation of an error thrown due to OPA configuration issues.
    ///
    /// An OPAConfigurationError will have a ``code`` specifying the type of error.
    /// See ``ConfigError/Code`` for available codes.
    public struct ConfigError: Sendable, Swift.Error {
        /// A domain-specific code describing the type of configuration error.
        public struct Code: Hashable, Sendable {
            internal enum InternalCode {
                case internalError
                case invalidValue
                case mutuallyExclusiveValues
                case referenceNotFound
            }

            private let internalCode: InternalCode

            internal init(_ code: InternalCode) {
                self.internalCode = code
            }

            public static let internalError = Code(.internalError)
            public static let invalidValue = Code(.invalidValue)
            public static let mutuallyExclusiveValues = Code(.mutuallyExclusiveValues)
            public static let referenceNotFound = Code(.referenceNotFound)
        }

        /// A code representing the high-level domain of the error.
        public var code: Code

        /// A message providing additional context about the error.
        public var message: String

        /// The original error which led to this error being thrown.
        public var cause: (any Swift.Error)?
    }

    /// A collection of OPA configuration-specific error constructors.
    public enum ConfigurationError {
        /// The provided value is not valid for the given configuration field.
        ///
        /// Use this for out-of-range values, wrong types, or otherwise disallowed values.
        public static func invalidValue(field: String, got: String, reason: String) -> ConfigError {
            return ConfigError(
                code: .invalidValue,
                message: "invalid value for '\(field)' (got: \(got)): \(reason)"
            )
        }

        /// Two or more configuration fields that cannot be set simultaneously were both provided.
        public static func mutuallyExclusiveValues(fields: [String]) -> ConfigError {
            let fieldList = fields.joined(separator: ", ")
            return ConfigError(
                code: .mutuallyExclusiveValues,
                message: "mutually exclusive configuration fields specified: \(fieldList)"
            )
        }

        /// A configuration value references something that isn't defined elsewhere in the configuration.
        public static func referenceNotFound(field: String, reference: String) -> ConfigError {
            return ConfigError(
                code: .referenceNotFound,
                message: "configuration field '\(field)' references undefined value '\(reference)'"
            )
        }

        /// General-purpose internal configuration error.
        internal static func internalError(msg: String) -> ConfigError {
            return ConfigError(
                code: .internalError,
                message: "internal configuration error: \(msg)"
            )
        }
    }
}
