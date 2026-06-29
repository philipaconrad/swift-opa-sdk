import Rego

import struct IR.Policy

// MARK: - OPA.Engine convenience

extension OPA.Engine {
    /// Initializes the OPA engine with in-memory bundles and a unified ``Rego/BuiltinImpl`` dictionary.
    ///
    /// Splits the dictionary into async-only and sync builtins before forwarding to the engine.
    public init(
        bundles: [String: OPA.Bundle],
        capabilities: OPA.Engine.CapabilitiesInput? = nil,
        customBuiltins: [String: Rego.BuiltinImpl]
    ) {
        self.init(
            bundles: bundles,
            capabilities: capabilities,
            customBuiltins: customBuiltins.asyncBuiltins,
            customSyncBuiltins: customBuiltins.syncBuiltins)
    }

    /// Initializes the OPA engine with bundle paths on disk and a unified ``Rego/BuiltinImpl`` dictionary.
    ///
    /// Splits the dictionary into async-only and sync builtins before forwarding to the engine.
    public init(
        bundlePaths: [OPA.Engine.BundlePath],
        capabilities: OPA.Engine.CapabilitiesInput? = nil,
        customBuiltins: [String: Rego.BuiltinImpl]
    ) {
        self.init(
            bundlePaths: bundlePaths,
            capabilities: capabilities,
            customBuiltins: customBuiltins.asyncBuiltins,
            customSyncBuiltins: customBuiltins.syncBuiltins)
    }

    /// Initializes the OPA engine with raw IR policies and a unified ``Rego/BuiltinImpl`` dictionary.
    ///
    /// Splits the dictionary into async-only and sync builtins before forwarding to the engine.
    public init(
        policies: [IR.Policy],
        store: any OPA.Store,
        capabilities: OPA.Engine.CapabilitiesInput? = nil,
        customBuiltins: [String: Rego.BuiltinImpl]
    ) {
        self.init(
            policies: policies,
            store: store,
            capabilities: capabilities,
            customBuiltins: customBuiltins.asyncBuiltins,
            customSyncBuiltins: customBuiltins.syncBuiltins)
    }
}

extension Dictionary where Key == String, Value == Rego.BuiltinImpl {
    fileprivate var asyncBuiltins: [String: Rego.AsyncBuiltin] {
        compactMapValues {
            guard case .asyncOnly(let f) = $0 else { return nil }
            return f
        }
    }
    fileprivate var syncBuiltins: [String: Rego.SyncBuiltin] {
        compactMapValues {
            guard case .sync(let f) = $0 else { return nil }
            return f
        }
    }
}
