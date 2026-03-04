import AST
import Foundation
import Rego
import Yams

extension AST.RegoValue {
    /// Initializes the RegoValue from a YAML source.
    init(yamlData: Data) throws {
        self = try YAMLDecoder().decode(RegoValue.self, from: yamlData)
    }
}
