import AST
import Foundation
import Rego

// Lifted from DiscoveryConfigProviderTests so Runtime-level tests can share it.

/// Builds a discovery bundle whose evaluated `data.<decisionPath>` produces
/// the OPA.Config encoded by `configJSON`.
func makeDiscoveryBundle(
    decisionPath: String,
    configDataPath: String,
    configJSON: String
) throws -> OPA.Bundle {
    let configValue = try JSONDecoder().decode(AST.RegoValue.self, from: Data(configJSON.utf8))

    let segments = configDataPath.split(separator: "/").map(String.init)
    var nested: AST.RegoValue = configValue
    for segment in segments.reversed() {
        nested = .object([.string(segment): nested])
    }

    let roots = segments.isEmpty ? [""] : [segments.joined(separator: "/")]
    let manifest = OPA.Manifest(revision: UUID().uuidString, roots: roots)

    func generateStmtsForPath(path: String) -> ([String], [String]) {
        var staticStrings: [String] = [#"{"value": "result"}"#]
        var stmts: [String] = []
        var sourceLocalIdx = 5
        var keyStrIdx = 1
        var targetLocalIdx = 6
        stmts.append(
            #"{"type":"AssignVarOnceStmt","stmt":{"source":{"type":"local","value":1},"target":5,"file":0,"col":0,"row":0}}"#
        )
        for segment in path.split(separator: "/").map(String.init) {
            staticStrings.append(#"{"value": "\#(segment)"}"#)
            let dotStmt =
                #"{"type": "DotStmt", "stmt": {"source": {"type":"local","value":\#(sourceLocalIdx)}, "key": {"type":"string_index","value":\#(keyStrIdx)}, "target": \#(targetLocalIdx), "file":0,"col":0,"row":0}}"#
            sourceLocalIdx += 1
            keyStrIdx += 1
            targetLocalIdx += 1
            stmts.append(dotStmt)
        }
        stmts.append(
            #"{"type":"AssignVarOnceStmt","stmt":{"source":{"type":"local","value":\#(targetLocalIdx-1)},"target":2,"file":0,"col":0,"row":0}}"#
        )
        return (staticStrings, stmts)
    }

    let (staticStrings, stmts) = generateStmtsForPath(path: configDataPath)
    return try makeExampleBundle(
        manifest: manifest,
        planFiles: [
            Rego.BundleFile(
                url: URL(string: "/plan.json")!,
                data: """
                    {
                    "static":{"strings":[\(staticStrings.joined(separator: ","))],"files":[{"value":"disco.rego"}]},
                    "plans":{"plans":[{"name":"\(decisionPath)","blocks":[{"stmts":[\(stmts.joined(separator: ",")),
                    {"type":"AssignVarStmt","stmt":{"source":{"type":"local","value":2},"target":3,"file":0,"col":0,"row":0}},
                    {"type":"MakeObjectStmt","stmt":{"target":4,"file":0,"col":0,"row":0}},
                    {"type":"ObjectInsertStmt","stmt":{"key":{"type":"string_index","value":0},"value":{"type":"local","value":3},"object":4,"file":0,"col":0,"row":0}},
                    {"type":"ResultSetAddStmt","stmt":{"value":4,"file":0,"col":0,"row":0}}]}]}]},
                    "funcs":{"funcs":[]}
                    }
                    """.data(using: .utf8)!
            )
        ],
        regoFiles: [],
        data: nested
    )
}
