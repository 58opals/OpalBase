import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Script decoding", .tags(.unit))
struct ScriptDecodeValidator {
    @Test("rejects standard scripts with trailing bytes")
    func rejectsStandardScriptsWithTrailingBytes() throws {
        var lockingScript = OpalBase.Script.p2sh(scriptHash: Data(repeating: 0x11, count: 20)).data
        lockingScript.append(ScriptOperationCode._1.data)

        do {
            _ = try OpalBase.Script.decode(lockingScript: lockingScript)
            Issue.record("Expected trailing bytes to reject standard script decoding")
        } catch OpalBase.Script.Error.cannotDecodeScript {
            return
        } catch {
            Issue.record("Unexpected script decode error: \(error)")
        }
    }
}
