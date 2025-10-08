import Foundation
import Testing
@testable import OpalBase

@Suite("Script decoding", .tags(.unit, .script))
struct ScriptDecodingSuite {
    @Test("decodes canonical P2MS scripts", .tags(.unit, .script))
    func decodesCanonicalP2MSScripts() throws {
        let keyHexes = [
            "02a1633caf7bf6c5be0d9c1a48fa84347d2dcdd61e0bba655a957ac7956a16a5bd",
            "03ad1f1d40cbd4c0ca9120d4d6f90e1a5da760c1dd1bac06b9d3170f12e0b4d9f7",
            "0250863ad64a87ae8a2fe83c1af1a8403cb1b07f27f2b8e5e5a7dd4f3c3b3d0152"
        ]
        let publicKeys = try keyHexes.map { try PublicKey(compressedData: Data(hexString: $0)) }
        
        let script = Script.p2ms(numberOfRequiredSignatures: 2, publicKeys: publicKeys)
        let decoded = try Script.decode(lockingScript: script.data)
        
        #expect(decoded == script)
    }
    
    @Test("decodes standard 2-of-3 multisig scripts", .tags(.unit, .script))
    func decodesStandardTwoOfThreeMultisigScripts() throws {
        let keyHexes = [
            "02a1633caf7bf6c5be0d9c1a48fa84347d2dcdd61e0bba655a957ac7956a16a5bd",
            "03ad1f1d40cbd4c0ca9120d4d6f90e1a5da760c1dd1bac06b9d3170f12e0b4d9f7",
            "0250863ad64a87ae8a2fe83c1af1a8403cb1b07f27f2b8e5e5a7dd4f3c3b3d0152"
        ]
        let lockingScript = try Data(hexString: "5221\(keyHexes[0])21\(keyHexes[1])21\(keyHexes[2])53ae")
        
        let decoded = try Script.decode(lockingScript: lockingScript)
        let expectedKeys = try keyHexes.map { try PublicKey(compressedData: Data(hexString: $0)) }
        
        switch decoded {
        case .p2ms(let required, let publicKeys):
            #expect(required == 2)
            #expect(publicKeys == expectedKeys)
        default:
            Issue.record("Unexpected script decoded: \(decoded)")
        }
    }
    
    @Test("throws when the declared key count does not match the script", .tags(.unit, .script))
    func throwsOnMismatchedKeyCounts() throws {
        let keyHexes = [
            "02a1633caf7bf6c5be0d9c1a48fa84347d2dcdd61e0bba655a957ac7956a16a5bd",
            "03ad1f1d40cbd4c0ca9120d4d6f90e1a5da760c1dd1bac06b9d3170f12e0b4d9f7",
            "0250863ad64a87ae8a2fe83c1af1a8403cb1b07f27f2b8e5e5a7dd4f3c3b3d0152"
        ]
        let publicKeys = try keyHexes.map { try PublicKey(compressedData: Data(hexString: $0)) }
        let script = Script.p2ms(numberOfRequiredSignatures: 2, publicKeys: publicKeys)
        
        var mismatched = script.data
        mismatched[mismatched.count - 2] = OP._2.rawValue
        
        #expect(throws: Script.Error.invalidP2MSScript) {
            _ = try Script.decode(lockingScript: mismatched)
        }
    }
}
