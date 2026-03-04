import Foundation
import Rego

extension OPA {
    public struct DecisionResult: Codable, Sendable {
        public let id: String  // provides the identifier for this decision (which is included in the decision log.)
        public let result: Rego.ResultSet  // provides the output of query evaluation.
        //public let Provenance types.ProvenanceV1 // wraps the bundle build/version information

        public init(id: String = UUID().uuidString, result: Rego.ResultSet = Rego.ResultSet()) {
            self.id = id
            self.result = result
        }
    }
}
