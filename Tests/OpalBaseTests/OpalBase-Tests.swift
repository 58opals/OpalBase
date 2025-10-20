import Testing
@testable import OpalBase

@Suite("Opal Base")
struct OpalBaseTests {}

extension OpalBaseTests {
    @Test("version is non-empty", .tags(.unit))
    func versionIsNonEmpty() {
        #expect(OpalBase.version.isEmpty == false)
    }
}
