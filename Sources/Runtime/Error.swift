/// A representation of an error thrown by the OPA Runtime.
///
/// A RuntimeError will have a ``code`` specifying the type of error.
/// See ``RuntimeError/Code`` for available codes.
public struct RuntimeError: Sendable, Swift.Error {

    /// A domain-specific code describing the type of error.
    public struct Code: Hashable, Sendable {
        internal enum InternalCode {
            case internalError

            // Bundle errors
            case bundleInitializationError
            case bundleLoadError
            case bundleNameConflictError
            case bundleRootConflictError
            case bundleUnpreparedError
            case invalidArgumentError
        }

        private let internalCode: InternalCode

        internal init(_ code: InternalCode) {
            self.internalCode = code
        }

        // Bundle-related codes
        public static let bundleInitializationError = Code(.bundleInitializationError)
        public static let bundleLoadError = Code(.bundleLoadError)
        public static let bundleNameConflictError = Code(.bundleNameConflictError)
        public static let bundleRootConflictError = Code(.bundleRootConflictError)
        public static let bundleUnpreparedError = Code(.bundleUnpreparedError)
        public static let internalError = Code(.internalError)
        public static let invalidArgumentError = Code(.invalidArgumentError)
    }

    /// A code representing the high-level domain of the error.
    public var code: Code

    /// A message providing additional context about the error.
    public var message: String

    /// The original error which led to this error being thrown.
    public var cause: (any Swift.Error)?
}
