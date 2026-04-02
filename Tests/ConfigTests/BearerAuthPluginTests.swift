import Foundation
import Rego
import Testing

@testable import Config

@Suite("BearerAuthPluginTests")
struct BearerAuthPluginTests {

    struct ValidTestCase: Sendable {
        let description: String
        let json: String
        let expectedScheme: String
    }

    static var validTestCases: [ValidTestCase] {
        [
            ValidTestCase(
                description: "token only",
                json: #"{"token": "my-secret-token"}"#,
                expectedScheme: "Bearer"
            ),
            ValidTestCase(
                description: "token_path only",
                json: #"{"token_path": "/path/to/token"}"#,
                expectedScheme: "Bearer"
            ),
            ValidTestCase(
                description: "token with custom scheme",
                json: #"{"token": "my-token", "scheme": "CustomScheme"}"#,
                expectedScheme: "CustomScheme"
            ),
        ]
    }

    @Test(arguments: validTestCases)
    func testValidBearerAuth(tc: ValidTestCase) throws {
        let data = tc.json.data(using: .utf8)!
        let plugin = try JSONDecoder().decode(OPA.BearerAuthPlugin.self, from: data)
        #expect(plugin.scheme == tc.expectedScheme)
    }

    struct InvalidTestCase: Sendable {
        let description: String
        let json: String
    }

    static var invalidTestCases: [InvalidTestCase] {
        [
            InvalidTestCase(
                description: "both token and token_path specified",
                json: #"{"token": "my-token", "token_path": "/path/to/token"}"#
            ),
            InvalidTestCase(
                description: "neither token nor token_path specified",
                json: #"{}"#
            ),
            InvalidTestCase(
                description: "empty token and no token_path",
                json: #"{"token": ""}"#
            ),
        ]
    }

    @Test(arguments: invalidTestCases)
    func testInvalidBearerAuth(tc: InvalidTestCase) throws {
        let data = tc.json.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(OPA.BearerAuthPlugin.self, from: data)
        }
    }
}

// MARK: - Type Extensions

extension BearerAuthPluginTests.ValidTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}

extension BearerAuthPluginTests.InvalidTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}
