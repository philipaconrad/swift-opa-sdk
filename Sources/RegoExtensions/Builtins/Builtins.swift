import Foundation
import Rego

// SDKBuiltinFuncs is a local wrapper around the Rego builtin functions we provide
// in this package. The functions are implemented in files following the
// upstream Go topdown file organization to help better keep the 1:1 mapping.
// Each function needs to be registered in the sdkDefaultBuiltins.
public enum SDKBuiltinFuncs {

}

extension SDKBuiltinFuncs {
    /// The default set of builtins for this library.
    public static var sdkDefaultBuiltins: [String: Rego.Builtin] {
        return [
            "yaml.is_valid": SDKBuiltinFuncs.yamlIsValid,
            "yaml.marshal": SDKBuiltinFuncs.yamlMarshal,
            "yaml.unmarshal": SDKBuiltinFuncs.yamlUnmarshal,
        ]
    }
}
