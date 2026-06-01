// DataExtensionsValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Data extensions", .tags(.unit))
struct DataExtensionsValidator {
    @Test("reversedData matches reverse iteration")
    func reversedDataMatchesStandardReverse() throws {
        let bytes = Array(0...255).map(UInt8.init)
        let data = Data(bytes)
        
        let reversed = data.reversedData
        let expected = Data(bytes.reversed())
        
        #expect(reversed == expected)
    }
    
    @Test(
        "hexadecimal initializer decodes valid strings",
        arguments: validHexadecimalStringCases
    )
    func hexadecimalInitializerDecodesValidStrings(_ validCase: ValidHexadecimalStringCase) throws {
        let data = try Data(hexadecimalString: validCase.hexadecimalString)

        #expect(data == validCase.expectedData)
    }
    
    @Test(
        "hexadecimal initializer rejects malformed strings",
        arguments: malformedHexadecimalStrings
    )
    func hexadecimalInitializerRejectsMalformedStrings(_ hexadecimalString: String) {
        #expect(throws: Data.Error.cannotConvertHexadecimalStringToData) {
            _ = try Data(hexadecimalString: hexadecimalString)
        }
    }

    @Test("reader rejects negative read lengths")
    func readerRejectsNegativeReadLengths() {
        var reader = Data.Reader(Data([0x01, 0x02, 0x03]))

        #expect(throws: Data.Reader.Error.negativeReadCount(-1)) {
            _ = try reader.readData(count: -1)
        }
    }

    @Test("reader decodes signed little-endian values without trapping")
    func readerDecodesSignedLittleEndianValues() throws {
        var int8Reader = Data.Reader(Data([0xff]))
        let int8Value: Int8 = try int8Reader.readLittleEndian()
        #expect(int8Value == -1)

        var int32Reader = Data.Reader(Data([0xff, 0xff, 0xff, 0xff]))
        let int32Value: Int32 = try int32Reader.readLittleEndian()
        #expect(int32Value == -1)
    }

    @Test("reader remaining data is zero-based after consuming a slice")
    func readerRemainingDataIsZeroBasedAfterConsumingSlice() throws {
        let data = Data([0x00, 0x01, 0x02, 0x03])
        let slicedData = data[data.index(after: data.startIndex)...]
        var reader = Data.Reader(slicedData)

        try reader.advance(by: 1)
        let remainingData = reader.remainingData

        #expect(remainingData == Data([0x02, 0x03]))
        #expect(remainingData.startIndex == 0)
    }

    @Test("bit string conversion decodes binary text")
    func bitStringConversionDecodesBinaryText() throws {
        let converted = try "1010101000001111".convertBitsToData()

        #expect(converted == Data([0xaa, 0x0f]))
    }

    @Test("bit string conversion rejects non-binary characters")
    func bitStringConversionRejectsNonBinaryCharacters() {
        #expect(throws: String.BitDataConversionError.invalidBit("x")) {
            _ = try "1010x001".convertBitsToData()
        }
    }

    @Test("bit conversion rejects invalid bit widths", arguments: invalidBitWidthCases)
    func bitConversionRejectsInvalidBitWidths(_ invalidCase: InvalidBitWidthCase) {
        #expect(throws: BitConversion.Error.invalidBitWidth) {
            _ = try BitConversion.convertBits(
                [],
                from: invalidCase.fromBits,
                to: invalidCase.toBits,
                pad: true
            )
        }
    }

    private static let malformedHexadecimalStrings = [
        "0x123g",
        "abc",
        String(repeating: "a", count: 129),
        "0x",
        "0X"
    ]

    private static let validHexadecimalStringCases = [
        ValidHexadecimalStringCase(
            hexadecimalString: "deadbeef",
            expectedData: Data([0xde, 0xad, 0xbe, 0xef])
        ),
        ValidHexadecimalStringCase(
            hexadecimalString: "0xCAFEBABE",
            expectedData: Data([0xca, 0xfe, 0xba, 0xbe])
        ),
        ValidHexadecimalStringCase(
            hexadecimalString: "0XDEADBEEF",
            expectedData: Data([0xde, 0xad, 0xbe, 0xef])
        )
    ]

    struct ValidHexadecimalStringCase: CustomStringConvertible, Sendable {
        let hexadecimalString: String
        let expectedData: Data

        var description: String {
            hexadecimalString
        }
    }

    private static let invalidBitWidthCases = [
        InvalidBitWidthCase(fromBits: 0, toBits: 8),
        InvalidBitWidthCase(fromBits: 1, toBits: 0),
        InvalidBitWidthCase(fromBits: Int.bitWidth, toBits: 8)
    ]

    struct InvalidBitWidthCase: CustomStringConvertible, Sendable {
        let fromBits: Int
        let toBits: Int

        var description: String {
            "from \(fromBits) to \(toBits)"
        }
    }
}
