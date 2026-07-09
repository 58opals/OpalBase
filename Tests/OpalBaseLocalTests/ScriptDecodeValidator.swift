// ScriptDecodeValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Script decoding", .tags(.unit))
struct ScriptDecodeValidator {
    @Test(
        "decodes sliced P2PKH and P2SH locking bytecode",
        arguments: [
            OpalBase.Script.p2pkh_OPCHECKSIG(hash: .init(Data(repeating: 0x22, count: 20))),
            OpalBase.Script.p2sh(scriptHash: Data(repeating: 0x33, count: 20))
        ]
    )
    func decodesSlicedStandardLockingBytecode(script: OpalBase.Script) throws {
        let slicedLockingScript = makeSlicedData(from: script.data)

        #expect(slicedLockingScript.startIndex != 0)
        #expect(try OpalBase.Script.decode(lockingScript: slicedLockingScript) == script)
    }

    @Test("rejects standard scripts with trailing bytes")
    func rejectsStandardScriptsWithTrailingBytes() throws {
        var lockingScript = OpalBase.Script.p2sh(scriptHash: Data(repeating: 0x11, count: 20)).data
        lockingScript.append(ScriptOperationCode._1.data)

        #expect(throws: OpalBase.Script.Error.cannotDecodeScript) {
            _ = try OpalBase.Script.decode(lockingScript: lockingScript)
        }
    }

    @Test("rejects standard scripts with leading bytes")
    func rejectsStandardScriptsWithLeadingBytes() throws {
        var lockingScript = Data([0xff])
        lockingScript.append(OpalBase.Script.p2sh(scriptHash: Data(repeating: 0x11, count: 20)).data)

        #expect(throws: OpalBase.Script.Error.cannotDecodeScript) {
            _ = try OpalBase.Script.decode(lockingScript: lockingScript)
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

    @Test("invalid public P2MS values do not trap during serialization", arguments: invalidP2MSFixtures)
    func invalidPublicP2MSValuesDoNotTrapDuringSerialization(fixture: InvalidP2MSFixture) throws {
        let publicKeys = try (0..<fixture.publicKeyCount).map {
            try makePublicKey(privateKeyByte: UInt8($0 + 1))
        }
        let script = OpalBase.Script.p2ms(
            numberOfRequiredSignatures: fixture.numberOfRequiredSignatures,
            publicKeys: publicKeys
        )

        #expect(script.data.isEmpty)
    }

    @Test(
        "invalid standard hash lengths do not serialize malformed scripts",
        arguments: invalidStandardHashScriptFixtures
    )
    func invalidStandardHashLengthsDoNotSerializeMalformedScripts(fixture: InvalidStandardHashScriptFixture) {
        let script = fixture.makeScript(from: Data(repeating: 0x11, count: fixture.byteCount))

        #expect(script.data.isEmpty)
    }

    @Test("serializes largest standard P2MS script")
    func serializesLargestStandardP2MSScript() throws {
        let publicKeys = try (1...16).map { try makePublicKey(privateKeyByte: UInt8($0)) }
        let script = OpalBase.Script.p2ms(
            numberOfRequiredSignatures: 16,
            publicKeys: publicKeys
        )
        let lockingScript = script.data
        let publicKeyCountIndex = lockingScript.index(lockingScript.endIndex, offsetBy: -2)

        #expect(lockingScript.first == ScriptOperationCode._16.rawValue)
        #expect(lockingScript[publicKeyCountIndex] == ScriptOperationCode._16.rawValue)
        #expect(lockingScript.last == ScriptOperationCode._CHECKMULTISIG.rawValue)
        #expect(try OpalBase.Script.decode(lockingScript: lockingScript) == script)
    }

    private func makeSlicedData(from data: Data) -> Data {
        var paddedData = Data([0x00])
        paddedData.append(data)
        return paddedData[paddedData.index(after: paddedData.startIndex)...]
    }

    private func makePublicKey(privateKeyByte: UInt8) throws -> OpalBase.Key.PublicKey {
        let privateKeyData = Data(repeating: privateKeyByte, count: 32)
        return try OpalBase.Key.PublicKey(privateKeyData: privateKeyData)
    }

    private static let invalidP2MSFixtures: [InvalidP2MSFixture] = [
        .init(numberOfRequiredSignatures: 0, publicKeyCount: 0),
        .init(numberOfRequiredSignatures: 0, publicKeyCount: 1),
        .init(numberOfRequiredSignatures: 2, publicKeyCount: 1),
        .init(numberOfRequiredSignatures: 17, publicKeyCount: 1)
    ]

    private static let invalidStandardHashScriptFixtures: [InvalidStandardHashScriptFixture] = [
        .init(kind: .p2pkhCheckSignature, byteCount: 0),
        .init(kind: .p2pkhCheckSignature, byteCount: 19),
        .init(kind: .p2pkhCheckSignature, byteCount: 21),
        .init(kind: .p2pkhCheckDataSignature, byteCount: 0),
        .init(kind: .p2pkhCheckDataSignature, byteCount: 19),
        .init(kind: .p2pkhCheckDataSignature, byteCount: 21),
        .init(kind: .p2sh, byteCount: 0),
        .init(kind: .p2sh, byteCount: 19),
        .init(kind: .p2sh, byteCount: 21)
    ]

    struct InvalidP2MSFixture: Sendable {
        let numberOfRequiredSignatures: Int
        let publicKeyCount: Int
    }

    struct InvalidStandardHashScriptFixture: CustomStringConvertible, Sendable {
        let kind: StandardHashScriptKind
        let byteCount: Int

        var description: String {
            "\(kind), \(byteCount) bytes"
        }

        func makeScript(from data: Data) -> OpalBase.Script {
            switch kind {
            case .p2pkhCheckSignature:
                .p2pkh_OPCHECKSIG(hash: .init(data))
            case .p2pkhCheckDataSignature:
                .p2pkh_OPCHECKDATASIG(hash: .init(data))
            case .p2sh:
                .p2sh(scriptHash: data)
            }
        }
    }

    enum StandardHashScriptKind: String, CustomStringConvertible, Sendable {
        case p2pkhCheckSignature
        case p2pkhCheckDataSignature
        case p2sh

        var description: String {
            rawValue
        }
    }
}
