import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

// MARK: - ETag Test Server Infrastructure

/// Captures an incoming HTTP request's key details for later inspection.
struct ReceivedRequest: Sendable {
    let method: String
    let uri: String
    let headers: [(name: String, value: String)]

    func headerValue(for name: String) -> String? {
        headers.first(where: { $0.name.lowercased() == name.lowercased() })?.value
    }

    func allHeaderValues(for name: String) -> [String] {
        headers.filter { $0.name.lowercased() == name.lowercased() }.map(\.value)
    }
}

/// Thread-safe mutable state shared between the NIO handler and tests.
/// Allows tests to swap bundles, ETags, or force specific status codes
/// between `load()` calls.
final class ETagServerState: @unchecked Sendable {
    private let lock = NSLock()

    private var _bundleData: Data
    private var _etag: String?
    private var _requests: [ReceivedRequest] = []
    private var _forceStatusCode: UInt?
    private var _responseContentType: String

    init(
        bundleData: Data,
        etag: String?,
        forceStatusCode: UInt? = nil,
        responseContentType: String = "application/gzip"
    ) {
        self._bundleData = bundleData
        self._etag = etag
        self._forceStatusCode = forceStatusCode
        self._responseContentType = responseContentType
    }

    var bundleData: Data {
        get { lock.withLock { _bundleData } }
        set { lock.withLock { _bundleData = newValue } }
    }

    var etag: String? {
        get { lock.withLock { _etag } }
        set { lock.withLock { _etag = newValue } }
    }

    var requests: [ReceivedRequest] {
        lock.withLock { _requests }
    }

    var forceStatusCode: UInt? {
        get { lock.withLock { _forceStatusCode } }
        set { lock.withLock { _forceStatusCode = newValue } }
    }

    var responseContentType: String {
        get { lock.withLock { _responseContentType } }
        set { lock.withLock { _responseContentType = newValue } }
    }

    func recordRequest(_ request: ReceivedRequest) {
        lock.withLock { _requests.append(request) }
    }

    func clearRequests() {
        lock.withLock { _requests.removeAll() }
    }
}

/// NIO channel handler that implements ETag-aware bundle serving.
///
/// Behaviour:
///  - If `forceStatusCode` is set on the state, always respond with that code.
///  - If the incoming `If-None-Match` header matches the current ETag, respond 304.
///  - Otherwise respond 200 with the current bundle data and ETag.
final class ETagBundleHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    let state: ETagServerState
    private var requestHead: HTTPRequestHead?

    init(state: ETagServerState) {
        self.state = state
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestHead = head
        case .body:
            break
        case .end:
            guard let head = requestHead else { return }

            // Record every request for later inspection.
            let headers = head.headers.map { (name: $0.name, value: $0.value) }
            state.recordRequest(
                ReceivedRequest(
                    method: head.method.rawValue,
                    uri: head.uri,
                    headers: headers
                ))

            // Determine response.
            let forceCode = state.forceStatusCode
            let currentETag = state.etag
            let ifNoneMatch = head.headers["if-none-match"].first

            let shouldReturn304: Bool = {
                if let forceCode {
                    return forceCode == 304
                }
                guard let ifNoneMatch, let currentETag else { return false }
                return ifNoneMatch == currentETag
            }()

            if shouldReturn304 {
                var responseHead = HTTPResponseHead(version: head.version, status: .notModified)
                if let currentETag {
                    responseHead.headers.add(name: "etag", value: currentETag)
                }
                context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            } else if let forceCode, forceCode != 304 {
                let status = HTTPResponseStatus(statusCode: Int(forceCode))
                let responseHead = HTTPResponseHead(version: head.version, status: status)
                context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            } else {
                // 200 OK with bundle payload.
                var responseHead = HTTPResponseHead(version: head.version, status: .ok)
                responseHead.headers.add(name: "content-type", value: state.responseContentType)
                if let etag = currentETag {
                    responseHead.headers.add(name: "etag", value: etag)
                }

                let body = state.bundleData
                responseHead.headers.add(name: "content-length", value: "\(body.count)")

                context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
                var buffer = context.channel.allocator.buffer(capacity: body.count)
                buffer.writeBytes(body)
                context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            }

            requestHead = nil
        }
    }
}

/// A lightweight NIO-based HTTP test server that supports ETag / 304 semantics.
struct ETagBundleServer: Sendable {
    let channel: Channel
    let group: EventLoopGroup
    let state: ETagServerState

    var port: Int { channel.localAddress!.port! }
    var baseURL: String { "http://127.0.0.1:\(port)" }

    static func start(
        bundleData: Data,
        etag: String?,
        forceStatusCode: UInt? = nil,
        contentType: String = "application/gzip"
    ) async throws -> ETagBundleServer {
        let state = ETagServerState(
            bundleData: bundleData,
            etag: etag,
            forceStatusCode: forceStatusCode,
            responseContentType: contentType)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(ETagBundleHandler(state: state))
                }
            }

        let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        return ETagBundleServer(channel: channel, group: group, state: state)
    }

    func shutdown() async throws {
        try await channel.close()
        try await group.shutdownGracefully()
    }
}
