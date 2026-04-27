import Foundation
import Rego

extension OPA {

    /// DecisionResult encodes basic state information about a policy decision.
    public struct DecisionResult: Codable, Sendable {
        /// A unique identifier for the policy decision.
        public let id: String

        /// The output of the evaluated query.
        public let result: Rego.ResultSet

        //public let Provenance types.ProvenanceV1 // wraps the bundle build/version information

        public init(id: String = UUID().uuidString, result: Rego.ResultSet = Rego.ResultSet()) {
            self.id = id
            self.result = result
        }
    }
}
