import Foundation
import Rego
import Testing

@testable import Config

@Suite("DiscoveryConfigTests")
struct DiscoveryConfigTests {

    struct ValidTestCase: Sendable {
        let description: String
        let json: String
    }

    static var validTestCases: [ValidTestCase] {
        [
            ValidTestCase(
                description: "minimal discovery config",
                json: #"""
                    {
                        "resource": "https://example.com/discovery"
                    }
                    """#
            ),
            ValidTestCase(
                description: "discovery with resource and decision",
                json: #"""
                    {
                        "service": "acmecorp",
                        "resource": "/config",
                        "decision": "config/result"
                    }
                    """#
            ),
            ValidTestCase(
                description: "discovery with persist enabled",
                json: #"""
                    {
                        "service": "acmecorp",
                        "resource": "/config",
                        "persist": true
                    }
                    """#
            ),
        ]
    }

    @Test(arguments: validTestCases)
    func testValidDiscovery(tc: ValidTestCase) throws {
        let data = tc.json.data(using: .utf8)!
        let _ = try JSONDecoder().decode(OPA.DiscoveryConfig.self, from: data)
    }
}

// MARK: - Type Extensions

extension DiscoveryConfigTests.ValidTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}
