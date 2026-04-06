import Foundation
import Rego
import Testing

@testable import Config

@Suite("BundleSourceConfigTests")
struct BundleSourceConfigTests {

    struct ValidTestCase: Sendable {
        let description: String
        let json: String
        /// Services context to use for validateWithContext
        let servicesJSON: String
        let keys: [String: OPA.KeyConfig]
    }

    static var validTestCases: [ValidTestCase] {
        get throws {
            [
                ValidTestCase(
                    description: "file URL resource with no service",
                    json: #"""
                        {"resource": "file:///tmp/bundle.tar.gz"}
                        """#,
                    servicesJSON: #"{}"#,
                    keys: [:]
                ),
                ValidTestCase(
                    description: "file URL resource with percent-encoded spaces",
                    json: #"""
                        {"resource": "file:///tmp/path%20with%20spaces/bundle.tar.gz"}
                        """#,
                    servicesJSON: #"{}"#,
                    keys: [:]
                ),
                ValidTestCase(
                    description: "service-backed bundle with matching service",
                    json: #"""
                        {"service": "acmecorp", "resource": "/bundles/authz"}
                        """#,
                    servicesJSON:
                        #"{"acmecorp": {"name": "acmecorp", "url": "https://acmecorp.example.com"}}"#,
                    keys: [:]
                ),
                ValidTestCase(
                    description: "service-backed bundle with valid polling config",
                    json: #"{"service": "s1", "polling": {"min_delay_seconds": 1, "max_delay_seconds": 5}}"#,
                    servicesJSON: #"{"s1": {"name": "s1", "url": "https://s1.example.com"}}"#,
                    keys: [:]
                ),
            ]
        }
    }

    @Test(arguments: try validTestCases)
    func testValidBundleConfig(tc: ValidTestCase) throws {
        let data = tc.json.data(using: .utf8) ?? Data()
        let bundleConfig = try JSONDecoder().decode(OPA.BundleSourceConfig.self, from: data)
        try bundleConfig.validate()
        let servicesConfig: [String: OPA.ServiceConfig] = try JSONDecoder().decode(
            [String: OPA.ServiceConfig].self, from: tc.servicesJSON.data(using: .utf8) ?? Data())
        try bundleConfig.validateWithContext(name: "test", services: servicesConfig, keys: tc.keys)
    }

    struct InvalidTestCase: Sendable {
        let description: String
        let json: String
        /// Services context for validateWithContext (only used if decode succeeds)
        let servicesJSON: String
        let keys: [String: OPA.KeyConfig]
        let failsAt: FailureStage

        enum FailureStage: Sendable {
            case decode
            case decodeValidate
            case validateWithContext
        }
    }

    static var invalidTestCases: [InvalidTestCase] {
        get throws {
            [
                // No service, no file URL
                // Ported from OPA's TestConfigValidation cases / TestParseAndValidateBundlesConfig cases
                InvalidTestCase(
                    description: "no service and no resource",
                    json: #"{}"#,
                    servicesJSON: #"{}"#,
                    keys: [:],
                    failsAt: .decodeValidate
                ),
                InvalidTestCase(
                    description: "empty resource string with no service",
                    json: #"{"resource": ""}"#,
                    servicesJSON: #"{}"#,
                    keys: [:],
                    failsAt: .decodeValidate
                ),
                // Ported from ConfigTests — non-file URL without service
                InvalidTestCase(
                    description: "non-file URL resource with no service",
                    json: #"{"resource": "https://example.com/bundle.tar.gz"}"#,
                    servicesJSON: #"{}"#,
                    keys: [:],
                    failsAt: .decodeValidate
                ),

                // Service not found
                // Ported from OPA's TestConfigValidation cases
                InvalidTestCase(
                    description: "references nonexistent service (no services defined)",
                    json: #"{"service": "ghost", "resource": "/bundle.tar.gz"}"#,
                    servicesJSON: #"{}"#,
                    keys: [:],
                    failsAt: .validateWithContext
                ),
                // Ported from OPA's TestParseAndValidateBundlesConfig cases
                InvalidTestCase(
                    description: "references service not in services list",
                    json: #"{"service": "s1"}"#,
                    servicesJSON: #"{}"#,
                    keys: [:],
                    failsAt: .validateWithContext
                ),
                // Ported from OPA's TestParseAndValidateBundlesConfig cases
                InvalidTestCase(
                    description: "references service missing from partial services list",
                    json: #"{"service": "s2"}"#,
                    servicesJSON: #"{"s1": {"name": "s1", "url": "https://s1.example.com"}}"#,
                    keys: [:],
                    failsAt: .validateWithContext
                ),

                // Polling validation
                // Ported from OPA's TestParseAndValidateBundlesConfig cases
                InvalidTestCase(
                    description: "polling min_delay_seconds greater than max_delay_seconds",
                    json: #"{"service": "s1", "polling": {"min_delay_seconds": 5, "max_delay_seconds": 1}}"#,
                    servicesJSON: #"{"s1": {"name": "s1", "url": "https://s1.example.com"}}"#,
                    keys: [:],
                    failsAt: .decodeValidate
                ),

                // Signing validation
                // Ported from OPA's TestParseAndValidateBundlesConfig cases
                InvalidTestCase(
                    description: "signing references unknown key ID",
                    json:
                        #"{"service": "s1", "signing": {"keyid": "bar", "scope": "write", "publicKeys": {}, "exclude_files": []}}"#,
                    servicesJSON: #"{"s1": {"name": "s1", "url": "https://s1.example.com"}}"#,
                    keys: [
                        "foo": try OPA.KeyConfig(key: "secret")
                    ],
                    failsAt: .validateWithContext
                ),

                // Trigger mode validation
                // Ported from OPA's TestParseConfigTriggerMode cases
                InvalidTestCase(
                    description: "invalid trigger mode string",
                    json: #"{"service": "s1", "trigger": "foo"}"#,
                    servicesJSON: #"{"s1": {"name": "s1", "url": "https://s1.example.com"}}"#,
                    keys: [:],
                    failsAt: .decodeValidate
                ),

                // Malformed JSON
                // Ported from OPA's TestParseAndValidateBundlesConfig cases
                InvalidTestCase(
                    description: "malformed JSON",
                    json: #"{{{"#,
                    servicesJSON: #"{}"#,
                    keys: [:],
                    failsAt: .decode
                ),
            ]
        }
    }

    @Test(arguments: try invalidTestCases)
    func testInvalidBundleConfig(tc: InvalidTestCase) throws {
        let data = tc.json.data(using: .utf8) ?? Data()
        switch tc.failsAt {
        case .decode:
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(OPA.BundleSourceConfig.self, from: data)
            }
        case .decodeValidate:
            #expect(throws: OPA.ConfigError.self) {
                try JSONDecoder().decode(OPA.BundleSourceConfig.self, from: data)
            }
        case .validateWithContext:
            let bundleConfig = try JSONDecoder().decode(OPA.BundleSourceConfig.self, from: data)
            try bundleConfig.validate()
            let servicesConfig: [String: OPA.ServiceConfig] = try JSONDecoder().decode(
                [String: OPA.ServiceConfig].self, from: tc.servicesJSON.data(using: .utf8) ?? Data())
            #expect(throws: OPA.ConfigError.self) {
                try bundleConfig.validateWithContext(name: "test", services: servicesConfig, keys: tc.keys)
            }
        }
    }
}

// MARK: - Type Extensions

extension BundleSourceConfigTests.ValidTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}

extension BundleSourceConfigTests.InvalidTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}
