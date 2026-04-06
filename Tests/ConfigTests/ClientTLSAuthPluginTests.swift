import Foundation
import Rego
import Testing

@testable import Config

@Suite("ClientTLSAuthPluginTests")
struct ClientTLSAuthPluginTests {

    struct ValidTestCase: Sendable {
        let description: String
        let json: String
    }

    static var validTestCases: [ValidTestCase] {
        [
            ValidTestCase(
                description: "minimal valid client TLS config",
                json: #"""
                    {
                        "cert": "/path/to/cert.pem",
                        "private_key": "/path/to/key.pem"
                    }
                    """#
            ),
            ValidTestCase(
                description: "client TLS with CA cert",
                json: #"""
                    {
                        "cert": "/path/to/cert.pem",
                        "private_key": "/path/to/key.pem",
                        "ca_cert": "/path/to/ca.pem"
                    }
                    """#
            ),
            ValidTestCase(
                description: "client TLS with private key passphrase",
                json: #"""
                    {
                        "cert": "/path/to/cert.pem",
                        "private_key": "/path/to/key.pem",
                        "private_key_passphrase": "secret"
                    }
                    """#
            ),
        ]
    }

    @Test(arguments: validTestCases)
    func testValidClientTLS(tc: ValidTestCase) throws {
        let data = tc.json.data(using: .utf8)!
        let _ = try JSONDecoder().decode(OPA.ClientTLSAuthPlugin.self, from: data)
    }

    struct InvalidTestCase: Sendable {
        let description: String
        let json: String
    }

    static var invalidTestCases: [InvalidTestCase] {
        [
            InvalidTestCase(
                description: "missing cert",
                json: #"""
                    {
                        "private_key": "/path/to/key.pem"
                    }
                    """#
            ),
            InvalidTestCase(
                description: "missing private_key",
                json: #"""
                    {
                        "cert": "/path/to/cert.pem"
                    }
                    """#
            ),
            InvalidTestCase(
                description: "empty cert string",
                json: #"""
                    {
                        "cert": "",
                        "private_key": "/path/to/key.pem"
                    }
                    """#
            ),
            InvalidTestCase(
                description: "empty private_key string",
                json: #"""
                    {
                        "cert": "/path/to/cert.pem",
                        "private_key": ""
                    }
                    """#
            ),
            InvalidTestCase(
                description: "both cert and private_key empty",
                json: #"""
                    {
                        "cert": "",
                        "private_key": ""
                    }
                    """#
            ),
        ]
    }

    @Test(arguments: invalidTestCases)
    func testInvalidClientTLS(tc: InvalidTestCase) throws {
        let data = tc.json.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(OPA.ClientTLSAuthPlugin.self, from: data)
        }
    }
}

// MARK: - Type Extensions

extension ClientTLSAuthPluginTests.ValidTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}

extension ClientTLSAuthPluginTests.InvalidTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}
