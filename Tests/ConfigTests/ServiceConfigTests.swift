import Foundation
import Rego
import Testing

@testable import Config

@Suite("ServiceConfigTests")
struct ServiceConfigTests {

    struct ValidTestCase: Sendable {
        let description: String
        let json: String
        let expectedName: String
        let expectedURL: String
    }

    static var validTestCases: [ValidTestCase] {
        [
            ValidTestCase(
                description: "minimal service config",
                json: #"""
                    {
                        "name": "acmecorp",
                        "url": "https://example.com/api/v1"
                    }
                    """#,
                expectedName: "acmecorp",
                expectedURL: "https://example.com/api/v1"
            ),
            ValidTestCase(
                description: "service with headers",
                json: #"""
                    {
                        "name": "acmecorp",
                        "url": "https://example.com/api/v1",
                        "headers": {"foo": "bar"}
                    }
                    """#,
                expectedName: "acmecorp",
                expectedURL: "https://example.com/api/v1"
            ),
            ValidTestCase(
                description: "service with response timeout",
                json: #"""
                    {
                        "name": "acmecorp",
                        "url": "https://example.com/api/v1",
                        "response_header_timeout_seconds": 5
                    }
                    """#,
                expectedName: "acmecorp",
                expectedURL: "https://example.com/api/v1"
            ),
            ValidTestCase(
                description: "service with bearer token credentials",
                json: #"""
                    {
                        "name": "acmecorp",
                        "url": "https://example.com/api/v1",
                        "credentials": {"bearer": {"token": "test-token"}}
                    }
                    """#,
                expectedName: "acmecorp",
                expectedURL: "https://example.com/api/v1"
            ),
            ValidTestCase(
                description: "service with allow_insecure_tls",
                json: #"""
                    {
                        "name": "local",
                        "url": "https://localhost:8181",
                        "allow_insecure_tls": true
                    }
                    """#,
                expectedName: "local",
                expectedURL: "https://localhost:8181"
            ),
        ]
    }

    @Test(arguments: validTestCases)
    func testValidServiceConfig(tc: ValidTestCase) throws {
        let data = tc.json.data(using: .utf8)!
        let service = try JSONDecoder().decode(OPA.ServiceConfig.self, from: data)
        #expect(service.name == tc.expectedName)
        #expect(service.url.absoluteString == tc.expectedURL)
    }

    struct InvalidTestCase: Sendable {
        let description: String
        let json: String
    }

    static var invalidTestCases: [InvalidTestCase] {
        [
            InvalidTestCase(
                description: "missing url field",
                json: #"""
                    {"name": "acmecorp"}
                    """#
            ),
            InvalidTestCase(
                description: "service config is an array",
                json: #"""
                    ["not", "an", "object"]
                    """#
            ),
        ]
    }

    @Test(arguments: invalidTestCases)
    func testInvalidServiceConfig(tc: InvalidTestCase) throws {
        let data = tc.json.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(OPA.ServiceConfig.self, from: data)
        }
    }
}

// MARK: - Type Extensions

extension ServiceConfigTests.ValidTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}

extension ServiceConfigTests.InvalidTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}
