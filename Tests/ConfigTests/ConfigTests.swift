import Foundation
import Rego
import Testing

@testable import Config

// MARK: - Config Decoding Tests

@Suite("ConfigDecodingTests")
struct ConfigDecodingTests {

    struct ValidTestCase: Sendable {
        let description: String
        let json: String
        let expectedBundleCount: Int
        let expectedServiceCount: Int
        let expectedLabelCount: Int
        let expectedKeyCount: Int
    }

    static var validTestCases: [ValidTestCase] {
        [
            ValidTestCase(
                description: "empty config",
                json: #"{}"#,
                expectedBundleCount: 0,
                expectedServiceCount: 0,
                expectedLabelCount: 0,
                expectedKeyCount: 0
            ),
            ValidTestCase(
                description: "config with labels only",
                json: #"""
                    {
                        "labels": {
                            "region": "west",
                            "env": "production"
                        }
                    }
                    """#,
                expectedBundleCount: 0,
                expectedServiceCount: 0,
                expectedLabelCount: 2,
                expectedKeyCount: 0
            ),
            ValidTestCase(
                description: "config with single file bundle (tarball)",
                json: #"""
                    {
                        "bundles": {
                            "test": {"resource": "file:///tmp/bundle.tar.gz"}
                        }
                    }
                    """#,
                expectedBundleCount: 1,
                expectedServiceCount: 0,
                expectedLabelCount: 0,
                expectedKeyCount: 0
            ),
            ValidTestCase(
                description: "config with single file bundle (directory)",
                json: #"""
                    {
                        "bundles": {
                            "test": {"resource": "file:///tmp/bundle-dir"}
                        }
                    }
                    """#,
                expectedBundleCount: 1,
                expectedServiceCount: 0,
                expectedLabelCount: 0,
                expectedKeyCount: 0
            ),
            ValidTestCase(
                description: "config with multiple file bundles",
                json: #"""
                    {
                        "bundles": {
                            "bundle-a": {"resource": "file:///tmp/a.tar.gz"},
                            "bundle-b": {"resource": "file:///tmp/b.tar.gz"}
                        }
                    }
                    """#,
                expectedBundleCount: 2,
                expectedServiceCount: 0,
                expectedLabelCount: 0,
                expectedKeyCount: 0
            ),
            ValidTestCase(
                description: "config with service and bundle referencing it",
                json: #"""
                    {
                        "services": {
                            "acmecorp": {
                                "name": "acmecorp",
                                "url": "https://example.com/control-plane-api/v1"
                            }
                        },
                        "bundles": {
                            "authz": {
                                "service": "acmecorp",
                                "resource": "/bundles/authz"
                            }
                        }
                    }
                    """#,
                expectedBundleCount: 1,
                expectedServiceCount: 1,
                expectedLabelCount: 0,
                expectedKeyCount: 0
            ),
            ValidTestCase(
                description: "config with multiple services and bundles",
                json: #"""
                    {
                        "services": {
                            "acmecorp": {
                                "name": "acmecorp",
                                "url": "https://example.com/api/v1"
                            },
                            "opa.example.com": {
                                "name": "opa.example.com",
                                "url": "https://opa.example.com"
                            }
                        },
                        "bundles": {
                            "authz": {
                                "service": "acmecorp",
                                "resource": "/bundles/authz"
                            },
                            "discovery": {
                                "service": "opa.example.com",
                                "resource": "/bundles/discovery"
                            }
                        }
                    }
                    """#,
                expectedBundleCount: 2,
                expectedServiceCount: 2,
                expectedLabelCount: 0,
                expectedKeyCount: 0
            ),
            ValidTestCase(
                description: "config with keys",
                json: #"""
                    {
                        "keys": {
                            "global_key": {
                                "algorithm": "HS256",
                                "key": "secret"
                            },
                            "local_key": {
                                "private_key": "some_private_key"
                            }
                        }
                    }
                    """#,
                expectedBundleCount: 0,
                expectedServiceCount: 0,
                expectedLabelCount: 0,
                expectedKeyCount: 2
            ),
            ValidTestCase(
                description: "config with service using bearer token credentials",
                json: #"""
                    {
                        "services": {
                            "acmecorp": {
                                "name": "acmecorp",
                                "url": "https://example.com/api/v1",
                                "credentials": {
                                    "bearer": {
                                        "token": "test-token"
                                    }
                                }
                            }
                        }
                    }
                    """#,
                expectedBundleCount: 0,
                expectedServiceCount: 1,
                expectedLabelCount: 0,
                expectedKeyCount: 0
            ),
            ValidTestCase(
                description: "config with service headers and response timeout",
                json: #"""
                    {
                        "services": {
                            "acmecorp": {
                                "name": "acmecorp",
                                "url": "https://example.com/api/v1",
                                "response_header_timeout_seconds": 5,
                                "headers": {"Authorization": "Basic dXNlcjpwYXNz"}
                            }
                        }
                    }
                    """#,
                expectedBundleCount: 0,
                expectedServiceCount: 1,
                expectedLabelCount: 0,
                expectedKeyCount: 0
            ),
            ValidTestCase(
                description: "full config with labels, services, bundles, and keys",
                json: #"""
                    {
                        "labels": {"region": "west"},
                        "services": {
                            "acmecorp": {
                                "name": "acmecorp",
                                "url": "https://example.com/api/v1",
                                "credentials": {"bearer": {"token": "test"}}
                            }
                        },
                        "bundles": {
                            "authz": {
                                "service": "acmecorp",
                                "resource": "/bundles/authz"
                            }
                        },
                        "keys": {
                            "global_key": {
                                "algorithm": "HS256",
                                "key": "secret"
                            }
                        }
                    }
                    """#,
                expectedBundleCount: 1,
                expectedServiceCount: 1,
                expectedLabelCount: 1,
                expectedKeyCount: 1
            ),
        ]
    }

    @Test(arguments: validTestCases)
    func testValidConfig(tc: ValidTestCase) throws {
        let data = tc.json.data(using: .utf8)!
        let config = try JSONDecoder().decode(OPA.Config.self, from: data)
        #expect(
            config.bundles.count == tc.expectedBundleCount,
            "Expected \(tc.expectedBundleCount) bundles, got \(config.bundles.count)")
        #expect(
            config.services.count == tc.expectedServiceCount,
            "Expected \(tc.expectedServiceCount) services, got \(config.services.count)")
        #expect(
            config.labels.count == tc.expectedLabelCount,
            "Expected \(tc.expectedLabelCount) labels, got \(config.labels.count)")
        #expect(
            config.keys.count == tc.expectedKeyCount,
            "Expected \(tc.expectedKeyCount) keys, got \(config.keys.count)")
    }

    struct InvalidTestCase: Sendable {
        let description: String
        let json: String
    }

    static var invalidTestCases: [InvalidTestCase] {
        [
            InvalidTestCase(
                description: "bundles config is not an object",
                json: #"""
                    {
                        "bundles": "not-an-object"
                    }
                    """#
            ),
            InvalidTestCase(
                description: "bundle with no service and non-file URL",
                json: #"""
                    {
                        "bundles": {
                            "test": {"resource": "https://example.com/bundle.tar.gz"}
                        }
                    }
                    """#
            ),
            InvalidTestCase(
                description: "bundle references nonexistent service",
                json: #"""
                    {
                        "bundles": {
                            "test": {"service": "ghost", "resource": "/bundle.tar.gz"}
                        }
                    }
                    """#
            ),
            InvalidTestCase(
                description: "bundle with empty resource and no service",
                json: #"""
                    {
                        "bundles": {
                            "test": {}
                        }
                    }
                    """#
            ),
            InvalidTestCase(
                description: "keys config is an array instead of object",
                json: #"""
                    {
                        "keys": [{"algorithm": "HS256"}]
                    }
                    """#
            ),
            InvalidTestCase(
                description: "services config is not a valid type",
                json: #"""
                    {
                        "services": "not-valid"
                    }
                    """#
            ),
            InvalidTestCase(
                description: "completely invalid JSON",
                json: "not json at all"
            ),
            InvalidTestCase(
                description: "top-level JSON array instead of object",
                json: "[]"
            ),
        ]
    }

    @Test(arguments: invalidTestCases)
    func testInvalidConfig(tc: InvalidTestCase) throws {
        let data = tc.json.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(OPA.Config.self, from: data)
        }
    }
}

// MARK: - Config Roundtrip Tests

@Suite("ConfigRoundtripTests")
struct ConfigRoundtripTests {

    struct RoundtripTestCase: Sendable {
        let description: String
        let json: String
    }

    static var roundtripTestCases: [RoundtripTestCase] {
        [
            // MARK: - Minimal / Empty

            RoundtripTestCase(
                description: "empty config",
                json: #"{}"#
            ),

            // MARK: - Labels

            RoundtripTestCase(
                description: "config with labels only",
                json: #"""
                    {
                        "labels": {
                            "region": "west",
                            "environment": "production"
                        }
                    }
                    """#
            ),

            // MARK: - Services

            RoundtripTestCase(
                description: "config with single service (minimal)",
                json: #"""
                    {
                        "services": [
                            {
                                "name": "acmecorp",
                                "url": "https://example.com/api/v1"
                            }
                        ]
                    }
                    """#
            ),
            RoundtripTestCase(
                description: "config with multiple services and headers",
                json: #"""
                    {
                        "services": [
                            {
                                "name": "acmecorp",
                                "url": "https://example.com/control-plane-api/v1",
                                "response_header_timeout_seconds": 5,
                                "headers": {"foo": "bar"}
                            },
                            {
                                "name": "opa.example.com",
                                "url": "https://opa.example.com",
                                "headers": {"foo": "bar"}
                            }
                        ]
                    }
                    """#
            ),
            RoundtripTestCase(
                description: "config with service using bearer token credentials",
                json: #"""
                    {
                        "services": [
                            {
                                "name": "acmecorp",
                                "url": "https://example.com/api/v1",
                                "credentials": {
                                    "bearer": {
                                        "token": "test-token"
                                    }
                                }
                            }
                        ]
                    }
                    """#
            ),

            // MARK: - Keys
            RoundtripTestCase(
                description: "config with symmetric key",
                json: #"""
                    {
                        "keys": {
                            "global_key": {
                                "algorithm": "HS256",
                                "key": "secret"
                            }
                        }
                    }
                    """#
            ),
            RoundtripTestCase(
                description: "config with multiple keys of different types",
                json: #"""
                    {
                        "keys": {
                            "global_key": {
                                "algorithm": "HS256",
                                "key": "secret"
                            },
                            "local_key": {
                                "private_key": "some_private_key"
                            }
                        }
                    }
                    """#
            ),

            // MARK: - Bundles

            RoundtripTestCase(
                description: "config with file URL bundle",
                json: #"""
                    {
                        "bundles": {
                            "authz": {
                                "resource": "file:///tmp/bundle.tar.gz"
                            }
                        }
                    }
                    """#
            ),
            RoundtripTestCase(
                description: "config with service-backed bundle",
                json: #"""
                    {
                        "services": [
                            {
                                "name": "acmecorp",
                                "url": "https://example.com/api/v1"
                            }
                        ],
                        "bundles": {
                            "authz": {
                                "service": "acmecorp",
                                "resource": "/bundles/authz"
                            }
                        }
                    }
                    """#
            ),
            RoundtripTestCase(
                description: "config with multiple bundles",
                json: #"""
                    {
                        "services": [
                            {
                                "name": "acmecorp",
                                "url": "https://example.com/api/v1"
                            }
                        ],
                        "bundles": {
                            "authz": {
                                "service": "acmecorp",
                                "resource": "/bundles/authz"
                            },
                            "data": {
                                "resource": "file:///tmp/data-bundle.tar.gz"
                            }
                        }
                    }
                    """#
            ),

            // MARK: - Discovery

            RoundtripTestCase(
                description: "config with minimal discovery",
                json: #"""
                    {
                        "discovery": {
                            "resource": "https://example.com/discovery"
                        }
                    }
                    """#
            ),
            RoundtripTestCase(
                description: "config with discovery including service and decision",
                json: #"""
                    {
                        "services": [
                            {
                                "name": "acmecorp",
                                "url": "https://example.com/api/v1"
                            }
                        ],
                        "discovery": {
                            "service": "acmecorp",
                            "resource": "/config",
                            "decision": "config/result"
                        }
                    }
                    """#
            ),
            RoundtripTestCase(
                description: "config with discovery and persist",
                json: #"""
                    {
                        "services": [
                            {
                                "name": "acmecorp",
                                "url": "https://example.com/api/v1"
                            }
                        ],
                        "discovery": {
                            "service": "acmecorp",
                            "resource": "/config",
                            "persist": true
                        }
                    }
                    """#
            ),

            // MARK: - Full / Combined Configs

            RoundtripTestCase(
                description: "full config with services, bundles, keys, labels, and discovery",
                json: #"""
                    {
                        "labels": {
                            "region": "west",
                            "environment": "staging"
                        },
                        "services": [
                            {
                                "name": "acmecorp",
                                "url": "https://example.com/control-plane-api/v1",
                                "response_header_timeout_seconds": 5,
                                "headers": {"foo": "bar"},
                                "credentials": {
                                    "bearer": {
                                        "token": "test"
                                    }
                                }
                            },
                            {
                                "name": "opa.example.com",
                                "url": "https://opa.example.com",
                                "headers": {"authorization": "Bearer xyz"}
                            }
                        ],
                        "keys": {
                            "global_key": {
                                "algorithm": "HS256",
                                "key": "secret"
                            },
                            "local_key": {
                                "private_key": "some_private_key"
                            }
                        },
                        "bundles": {
                            "authz": {
                                "service": "acmecorp",
                                "resource": "/bundles/authz"
                            }
                        },
                        "discovery": {
                            "service": "acmecorp",
                            "resource": "/config",
                            "decision": "config/result"
                        }
                    }
                    """#
            ),
            RoundtripTestCase(
                description: "full config with file bundles and no services",
                json: #"""
                    {
                        "labels": {
                            "id": "local-instance"
                        },
                        "keys": {
                            "verification_key": {
                                "algorithm": "HS256",
                                "key": "my-secret"
                            }
                        },
                        "bundles": {
                            "authz": {
                                "resource": "file:///opt/bundles/authz.tar.gz"
                            },
                            "data": {
                                "resource": "file:///opt/bundles/data.tar.gz"
                            }
                        }
                    }
                    """#
            ),
        ]
    }

    @Test(arguments: roundtripTestCases)
    func testRoundtrip(tc: RoundtripTestCase) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = tc.json.data(using: .utf8)!
        let config = try decoder.decode(OPA.Config.self, from: data)
        let encoded = try encoder.encode(config)
        let decoded = try decoder.decode(OPA.Config.self, from: encoded)

        #expect(decoded.bundles.count == config.bundles.count)
        #expect(decoded.services.count == config.services.count)
        #expect(decoded.labels == config.labels)
        #expect(decoded.keys.count == config.keys.count)

        // Verify bundle names and resources survive roundtrip
        for (name, _) in config.bundles {
            let roundtripped = decoded.bundles[name]
            #expect(roundtripped != nil, "Bundle '\(name)' missing after roundtrip")
        }

        // Verify service names and URLs survive roundtrip
        for (name, _) in config.services {
            let roundtripped = decoded.services[name]
            #expect(roundtripped != nil, "Service '\(name)' missing after roundtrip")
        }

        // Verify key names survive roundtrip
        for (name, _) in config.keys {
            let roundtripped = decoded.keys[name]
            #expect(roundtripped != nil, "Key '\(name)' missing after roundtrip")
        }
    }
}

// MARK: - Type Extensions

extension ConfigDecodingTests.ValidTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}

extension ConfigDecodingTests.InvalidTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}

extension ConfigRoundtripTests.RoundtripTestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}
