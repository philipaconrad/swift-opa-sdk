import AST
import Config
import Foundation
import Rego
import Testing

// MARK: - Disk-based Bundle Loading Tests

@Suite("DiskBasedBundleTests")
struct DiskBasedBundleTests {
    struct TestCase: Sendable {
        let description: String
        let config: String
        let useDirectory: Bool
    }

    @Test("Round-trip through directory format")
    func testBundleRoundTripDirectory() async throws {
        let tempDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        let expectedBundle = try makeExampleBundle()
        let bundleDir = tempDir.appendingPathComponent("bundle-dir")
        // Write bundle to disk as a directory.
        try OPA.Bundle.encodeToDirectory(bundle: expectedBundle, targetURL: bundleDir)

        // Read bundle back in from disk. Confirm it matches the original's contents.
        let actualBundle = try OPA.Bundle.decodeFromDirectory(fromDir: bundleDir)
        #expect(expectedBundle == actualBundle)
    }

    @Test("Round-trip through tarball format")
    func testRoundTripTarball() async throws {
        let expectedBundle = try makeExampleBundle()
        // Write bundle to tarball.
        let tarball = try OPA.Bundle.encodeToTarball(bundle: expectedBundle)

        // Read bundle back from tarball. Confirm it matches the original's contents.
        let actualBundle = try OPA.Bundle.decodeFromTarball(from: tarball)
        #expect(expectedBundle == actualBundle)
    }
}

extension DiskBasedBundleTests.TestCase: CustomTestStringConvertible {
    var testDescription: String { description }
}
