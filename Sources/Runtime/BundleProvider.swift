import AST
import Foundation
import Rego

extension OPA {
    /// BundleLoader abstracts over the "how" of retrieving a bundle.
    /// It is expected that implementations each have to be created
    /// from an OPA config's service / resource definitions.
    public protocol BundleLoader {
        func load() async -> Result<Bundle, any Swift.Error>
    }
}
