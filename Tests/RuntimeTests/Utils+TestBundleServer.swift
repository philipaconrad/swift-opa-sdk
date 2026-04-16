import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

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
