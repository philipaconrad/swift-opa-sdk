import AST
import AsyncHTTPClient
import Config
import Foundation
import Rego
import Testing

@testable import Runtime

// MARK: - HTTP Bundle Tests

@Suite("RuntimeHTTPBundleTests")
struct RuntimeHTTPBundleTests {
    // MARK: - Valid HTTP Cases
    @Test("simple HTTP service with tarball bundle")
    func testValidHTTPBundle() async throws {
        let testBundle = try makeExampleBundle()
        let bundleData = try OPA.Bundle.encodeToTarball(bundle: testBundle)

        let server = try await TestBundleServer.start(files: [
            "/bundles/bundle.tar.gz": bundleData
        ])
        defer { Task { try? await server.shutdown() } }

        let configJSON = """
            {
              "services": {
                "test-svc": {"url": "\(server.baseURL)"}
              },
                            "bundles": {
                "test": {"service": "test-svc", "resource": "/bundles/bundle.tar.gz"}
                            }
                        }
            """

        let config = try JSONDecoder().decode(OPA.Config.self, from: configJSON.data(using: .utf8)!)
        var rt = await OPA.Runtime(config: config, bundles: [:])
        let bundleResult = try #require(
            rt.bundleStorage.first, "Expected exactly 1 bundle, got \(rt.bundleStorage.count)")
        #expect(rt.bundleStorage.count == 1, "Expected exactly 1 bundle, got \(rt.bundleStorage.count)")
        guard case .success = bundleResult.value else {
            Issue.record("Expected bundle '\(bundleResult.key)' to be .success, got \(bundleResult.value)")
            return
        }
        try await rt.prepare(queries: ["data/foo/hello"])
        #expect(
            rt.bundleStorage.allSatisfy { (_, value) in
                if case .success = value { return true }
                return false
            })

        let dr = try await rt.decision("data/foo/hello", input: nil)
        #expect(dr.result.first == ["result": 1])
    }

    @Test("HTTP service with custom resource path")
    func testValidHTTPBundleCustomPath() async throws {
        let testBundle = try makeExampleBundle()
        let bundleData = try OPA.Bundle.encodeToTarball(bundle: testBundle)

        let server = try await TestBundleServer.start(files: [
            "/custom/path/my-bundle.tar.gz": bundleData
        ])
        defer { Task { try? await server.shutdown() } }

        let configJSON = """
                        {
              "services": {
                "my-service": {"url": "\(server.baseURL)"}
              },
                            "bundles": {
                "test": {"service": "my-service", "resource": "/custom/path/my-bundle.tar.gz"}
                            }
                        }
            """

        let config = try JSONDecoder().decode(OPA.Config.self, from: configJSON.data(using: .utf8)!)
        var rt = await OPA.Runtime(config: config, bundles: [:])

        let bundleResult = try #require(
            rt.bundleStorage.first, "Expected exactly 1 bundle, got \(rt.bundleStorage.count)")
        #expect(rt.bundleStorage.count == 1, "Expected exactly 1 bundle, got \(rt.bundleStorage.count)")
        guard case .success = bundleResult.value else {
            Issue.record("Expected bundle '\(bundleResult.key)' to be .success, got \(bundleResult.value)")
            return
        }
        try await rt.prepare(queries: ["data/foo/hello"])

        let dr = try await rt.decision("data/foo/hello", input: nil)
        #expect(dr.result.first == ["result": 1])
    }

    // MARK: - Invalid HTTP Cases
    @Test("HTTP service returns 404 for bundle path")
    func testHTTPBundle404() async throws {
        // Server is running but has no files — every request gets 404
        let server = try await TestBundleServer.start(files: [:])
        defer { Task { try? await server.shutdown() } }

        let configJSON = """
            {
              "services": {
                "test-svc": {"url": "\(server.baseURL)"}
              },
                            "bundles": {
                "test": {"service": "test-svc", "resource": "/bundles/nonexistent.tar.gz"}
                            }
                        }
            """

        let config = try JSONDecoder().decode(OPA.Config.self, from: configJSON.data(using: .utf8)!)
        let rt = await OPA.Runtime(config: config, bundles: [:])

        #expect(rt.bundleStorage.count == 1)
        #expect(
            rt.bundleStorage.allSatisfy { (_, value) in
                if case .failure = value { return true }
                return false
            }, "Expected bundle load to fail for 404 response")
    }

    @Test("service URL with invalid scheme fails config decode")
    func testInvalidServiceScheme() async throws {
        let configJSON = """
            {
              "services": {
                "bad-svc": {"url": "ftp://example.com"}
              },
                            "bundles": {
                "test": {"service": "bad-svc", "resource": "/bundle.tar.gz"}
                            }
                        }
            """
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(OPA.Config.self, from: configJSON.data(using: .utf8)!)
        }
    }
}
