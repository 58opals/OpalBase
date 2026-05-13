// ScriptDecodeValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Script decoding", .tags(.unit))
struct ScriptDecodeValidator {
    @Test("decodes sliced P2PKH and P2SH locking bytecode")
    func decodesSlicedStandardLockingBytecode() throws {
        let scripts: [OpalBase.Script] = [
            .p2pkh_OPCHECKSIG(hash: .init(Data(repeating: 0x22, count: 20))),
            .p2sh(scriptHash: Data(repeating: 0x33, count: 20))
        ]

        for script in scripts {
            let slicedLockingScript = makeSlicedData(from: script.data)

            #expect(slicedLockingScript.startIndex != 0)
            #expect(try OpalBase.Script.decode(lockingScript: slicedLockingScript) == script)
        }
    }

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

    @Test("rejects standard scripts with leading bytes")
    func rejectsStandardScriptsWithLeadingBytes() throws {
        var lockingScript = Data([0xff])
        lockingScript.append(OpalBase.Script.p2sh(scriptHash: Data(repeating: 0x11, count: 20)).data)

        do {
            _ = try OpalBase.Script.decode(lockingScript: lockingScript)
            Issue.record("Expected leading bytes to reject standard script decoding")
        } catch OpalBase.Script.Error.cannotDecodeScript {
            return
        } catch {
            Issue.record("Unexpected script decode error: \(error)")
        }
    }

    @Test("hashes invalid public P2MS values without serializing them")
    func hashesInvalidPublicP2MSValuesWithoutSerializingThem() {
        let invalid = OpalBase.Script.p2ms(
            numberOfRequiredSignatures: 0,
            publicKeys: []
        )
        let matchingInvalid = OpalBase.Script.p2ms(
            numberOfRequiredSignatures: 0,
            publicKeys: []
        )
        let distinctInvalid = OpalBase.Script.p2ms(
            numberOfRequiredSignatures: 17,
            publicKeys: []
        )

        #expect(invalid == matchingInvalid)
        #expect(invalid != distinctInvalid)
        #expect(Set([invalid, matchingInvalid, distinctInvalid]).count == 2)
    }

    private func makeSlicedData(from data: Data) -> Data {
        var paddedData = Data([0x00])
        paddedData.append(data)
        return paddedData[paddedData.index(after: paddedData.startIndex)...]
    }
}
