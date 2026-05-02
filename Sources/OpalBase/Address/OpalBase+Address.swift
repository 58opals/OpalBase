// OpalBase+Address.swift

import Foundation

extension OpalBase {
    public struct Address {
        public static let prefix: String = "bitcoincash"
        public static let separator: String = ":"
        public let string: String
        public let lockingScript: OpalBase.Script
        public let format: Format
        public let network: OpalBase.Network.Environment

        public init(_ string: String, network: OpalBase.Network.Environment = .mainnet) throws {
            try self.init(string: string, network: network)
        }

        public init(string: String, network: OpalBase.Network.Environment = .mainnet) throws {
            if string.contains(OpalBase.Address.separator) {
                self = try OpalBase.Address.parseCashAddr(from: string, network: network)
                return
            }

            if let cashAddr = try? OpalBase.Address.parseCashAddr(from: string, network: network) {
                self = cashAddr
                return
            }

            if network == .mainnet,
               let legacyAddress = try? OpalBase.Address.parseLegacyAddress(from: string) {
                self = legacyAddress
                return
            }

            throw Error.invalidCashAddrFormat
        }

        public init(
            script: OpalBase.Script,
            format: Format = .standard,
            network: OpalBase.Network.Environment = .mainnet
        ) throws {
            let string = try OpalBase.Address.makeCashAddrString(
                for: script,
                format: format,
                network: network
            )
            self.init(cashAddrPayload: string, lockingScript: script, format: format, network: network)
        }

        init(
            cashAddrPayload: String,
            lockingScript: OpalBase.Script,
            format: Format,
            network: OpalBase.Network.Environment
        ) {
            self.string = cashAddrPayload
            self.lockingScript = lockingScript
            self.format = format
            self.network = network
        }
    }
}

extension _OpalBase.Address {
    public var isTokenAware: Bool {
        format == .tokenAware
    }

    public func converted(to format: Format) throws -> OpalBase.Address {
        try OpalBase.Address(script: lockingScript, format: format, network: network)
    }

    public var tokenAwareString: String {
        (try? OpalBase.Address.makeCashAddrString(
            for: lockingScript,
            format: .tokenAware,
            network: network
        )) ?? string
    }

    public static func cashAddrPrefix(for network: OpalBase.Network.Environment) -> String {
        switch network {
        case .mainnet:
            return "bitcoincash"
        case .chipnet, .testnet:
            return "bchtest"
        }
    }

    static func convertPrefixToFiveBitValues(prefix: String) throws -> [UInt8] {
        var values = [UInt8]()
        for character in prefix {
            guard let asciiValue = character.asciiValue else { throw Error.invalidCharacter(character) }
            let lower5Bits = asciiValue & 0b11111
            values.append(lower5Bits)
        }
        return values
    }

    static func convertPayloadToFiveBitValues(payload: Data) throws -> [UInt8] {
        try BitConversion.convertBits([UInt8](payload), from: 8, to: 5, pad: true)
    }

    static func convertFiveBitValuesToData(fiveBitValues: [UInt8]) throws -> Data {
        let bytes = try BitConversion.convertBits(fiveBitValues, from: 5, to: 8, pad: false)
        return Data(bytes)
    }

    static func generateChecksum(prefix: String, payload5BitValues: [UInt8]) throws -> [UInt8] {
        var values = try OpalBase.Address.convertPrefixToFiveBitValues(prefix: prefix) + [0x00]
        values += payload5BitValues
        let templateForChecksum: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0]
        values += templateForChecksum
        let polymod = OpalCryptoAdapter.computePolymod(values)
        var checksum = [UInt8]()

        for index in 0..<8 {
            let shift = UInt64(5 * (7 - index))
            checksum.append(UInt8((polymod >> shift) & 0x1f))
        }

        return checksum
    }

    private static func makeCashAddrString(
        for script: OpalBase.Script,
        format: Format,
        network: OpalBase.Network.Environment
    ) throws -> String {
        let versionByte = try makeVersionByte(for: script, format: format)
        let payload: Data
        switch script {
        case .p2pkh_OPCHECKSIG(let hash), .p2pkh_OPCHECKDATASIG(hash: let hash):
            payload = Data([versionByte]) + hash.data
        case .p2sh(let scriptHash):
            guard scriptHash.count == 20 else { throw OpalBase.Address.Legacy.Error.invalidScriptType }
            payload = Data([versionByte]) + scriptHash
        default:
            throw OpalBase.Address.Legacy.Error.invalidScriptType
        }

        let payload5BitValues = try OpalBase.Address.convertPayloadToFiveBitValues(payload: payload)
        let checksum = try OpalBase.Address.generateChecksum(
            prefix: OpalBase.Address.cashAddrPrefix(for: network),
            payload5BitValues: payload5BitValues
        )
        let combined = payload5BitValues + checksum
        return try OpalCryptoAdapter.encodeBase32(Data(combined), interpretedAsFiveBitValues: true)
    }

    private static func makeVersionByte(for script: OpalBase.Script, format: Format) throws -> UInt8 {
        switch script {
        case .p2pkh_OPCHECKSIG, .p2pkh_OPCHECKDATASIG:
            return format == .tokenAware ? 0x10 : 0x00
        case .p2sh:
            return format == .tokenAware ? 0x18 : 0x08
        default:
            throw OpalBase.Address.Legacy.Error.invalidScriptType
        }
    }
}

extension _OpalBase.Address {
    public static func filterBase32(
        from string: String,
        network: OpalBase.Network.Environment = .mainnet
    ) -> String {
        let prefixWithSeparator = OpalBase.Address.cashAddrPrefix(for: network) + OpalBase.Address.separator

        let cleanedSubstring: Substring
        if let prefixRange = string.range(
            of: prefixWithSeparator,
            options: [.caseInsensitive, .anchored]
        ) {
            cleanedSubstring = string[prefixRange.upperBound...]
        } else {
            cleanedSubstring = string[string.startIndex...]
        }

        let filteredString = cleanedSubstring.reduce(into: String()) { partialResult, candidate in
            guard let asciiValue = candidate.asciiValue else { return }

            let normalizedAscii: UInt8
            switch asciiValue {
            case 0x41...0x5A:
                normalizedAscii = asciiValue &+ 0x20
            default:
                normalizedAscii = asciiValue
            }

            let normalizedScalar = UnicodeScalar(normalizedAscii)
            let normalizedCharacter = Character(normalizedScalar)

            guard OpalCryptoAdapter.cashAddrCharacters.contains(normalizedCharacter)
            else { return }

            partialResult.append(normalizedCharacter)
        }

        return filteredString
    }
}

extension _OpalBase.Address {
    public func makeScriptHash() -> Data {
        let scriptData = lockingScript.data
        return OpalCryptoAdapter.sha256(scriptData).reversedData
    }
}

extension _OpalBase.Address: CustomStringConvertible {
    public var description: String {
        string
    }

    public func generateString(withPrefix: Bool = false) -> String {
        withPrefix ? (OpalBase.Address.cashAddrPrefix(for: network) + OpalBase.Address.separator + string) : string
    }
}

extension _OpalBase.Address: Hashable {
    public static func == (lhs: OpalBase.Address, rhs: OpalBase.Address) -> Bool {
        lhs.network == rhs.network && lhs.lockingScript == rhs.lockingScript
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(network)
        hasher.combine(lockingScript)
    }
}

extension _OpalBase.Address: Sendable {}
extension _OpalBase.Address: Equatable {}
