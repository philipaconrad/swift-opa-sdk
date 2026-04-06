import AST
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import Rego

public func makeTempDir() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    try FileManager.default.createDirectory(
        at: tempDir,
        withIntermediateDirectories: true
    )

    guard FileManager.default.isWritableFile(atPath: tempDir.path) else {
        throw NSError(
            domain: "TestUtils",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Temp directory is not writable: \(tempDir.path)"]
        )
    }

    return tempDir
}

public func makeExampleBundle(
    manifest: OPA.Manifest? = nil,
    planFiles: [BundleFile]? = nil,
    regoFiles: [BundleFile]? = nil,
    data: AST.RegoValue? = nil
) throws -> OPA.Bundle {
    let id = UUID().uuidString
    let manifest = manifest ?? OPA.Manifest(revision: UUID().uuidString, roots: ["/\(id)"])
    let planFiles =
        planFiles ?? [
            Rego.BundleFile(
                url: URL(string: "/plan.json")!,
                data: #"""
                    {
                    "static":{"strings":[{"value":"result"},{"value":"1"}],"files":[{"value":"bar.rego"}]},
                    "plans":{"plans":[{"name":"foo/hello","blocks":[{"stmts":[{"type":"CallStmt","stmt":{"func":"g0.data.foo.hello","args":[{"type":"local","value":0},{"type":"local","value":1}],"result":2,"file":0,"col":0,"row":0}},{"type":"AssignVarStmt","stmt":{"source":{"type":"local","value":2},"target":3,"file":0,"col":0,"row":0}},{"type":"MakeObjectStmt","stmt":{"target":4,"file":0,"col":0,"row":0}},{"type":"ObjectInsertStmt","stmt":{"key":{"type":"string_index","value":0},"value":{"type":"local","value":3},"object":4,"file":0,"col":0,"row":0}},{"type":"ResultSetAddStmt","stmt":{"value":4,"file":0,"col":0,"row":0}}]}]}]},
                    "funcs":{"funcs":[{"name":"g0.data.foo.hello","params":[0,1],"return":2,"blocks":[{"stmts":[{"type":"ResetLocalStmt","stmt":{"target":3,"file":0,"col":1,"row":3}},{"type":"MakeNumberRefStmt","stmt":{"Index":1,"target":4,"file":0,"col":1,"row":3}},{"type":"AssignVarOnceStmt","stmt":{"source":{"type":"local","value":4},"target":3,"file":0,"col":1,"row":3}}]},{"stmts":[{"type":"IsDefinedStmt","stmt":{"source":3,"file":0,"col":1,"row":3}},{"type":"AssignVarOnceStmt","stmt":{"source":{"type":"local","value":3},"target":2,"file":0,"col":1,"row":3}}]},{"stmts":[{"type":"ReturnLocalStmt","stmt":{"source":2,"file":0,"col":1,"row":3}}]}],"path":["g0","foo","hello"]}]}
                    }
                    """#.data(using: .utf8)!
            )
        ]
    let regoFiles =
        regoFiles ?? [
            Rego.BundleFile(
                url: URL(string: "/\(id)/foo/bar.rego")!,
                data: "package foo\n\nhello=1".data(using: .utf8)!
            )
        ]
    let data =
        data ?? [
            "\(id)": [
                "foo": [
                    "bar": 1,
                    "baz": "qux",
                ]
            ]
        ]
    return try OPA.Bundle(manifest: manifest, planFiles: planFiles, regoFiles: regoFiles, data: data)
}

// MARK: - Test HTTP Server

/// A minimal HTTP server for testing HTTP-based bundle downloads.
/// Analogous to Go's `httptest.NewServer` — binds to 127.0.0.1 on an
/// OS-assigned port and serves canned responses keyed by request URI.
final class TestBundleServer: @unchecked Sendable {
    let port: Int
    let baseURL: String
    private let channel: Channel
    private let group: EventLoopGroup

    private init(channel: Channel, group: EventLoopGroup) {
        self.channel = channel
        self.group = group
        self.port = channel.localAddress!.port!
        self.baseURL = "http://127.0.0.1:\(self.port)"
    }

    /// Start a test server that maps request URI paths to response data.
    /// Any path not in `files` receives a 404.
    static func start(files: [String: Data]) async throws -> TestBundleServer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 16)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(Handler(files: files))
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)

        let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        return TestBundleServer(channel: channel, group: group)
    }

    func shutdown() async throws {
        try await channel.close()
        try await group.shutdownGracefully()
    }

    // MARK: - NIO Handler

    private final class Handler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart

        let files: [String: Data]
        private var requestURI: String = ""

        init(files: [String: Data]) {
            self.files = files
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let part = unwrapInboundIn(data)
            switch part {
            case .head(let head):
                requestURI = head.uri
            case .body:
                break
            case .end:
                let (status, body): (HTTPResponseStatus, Data) =
                    if let fileData = files[requestURI] {
                        (.ok, fileData)
                    } else {
                        (.notFound, Data("not found".utf8))
                    }

                var headers = HTTPHeaders()
                headers.add(name: "content-length", value: "\(body.count)")
                headers.add(name: "content-type", value: "application/octet-stream")

                let responseHead = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
                context.write(wrapOutboundOut(.head(responseHead)), promise: nil)

                var buffer = context.channel.allocator.buffer(capacity: body.count)
                buffer.writeBytes(body)
                context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
    }
}
