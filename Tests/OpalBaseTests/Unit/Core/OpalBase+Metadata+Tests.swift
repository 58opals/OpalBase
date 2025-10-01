import Foundation
import Testing
@testable import OpalBase

@Suite("Opal Base Metadata", .tags(.unit, .core))
struct OpalBaseMetadataSuite {
    @Test("exposes semantic version string", .tags(.unit, .core))
    func exposesSemanticVersionString() {
        let components = OpalBase.version.split(separator: ".")
        #expect(components.count == 3)
        #expect(components.allSatisfy { component in
            component.allSatisfy { $0.isNumber }
        })
    }
}
