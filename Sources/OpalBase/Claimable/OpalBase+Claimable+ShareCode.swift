// OpalBase+Claimable+ShareCode.swift

import Foundation

extension _OpalBase.Claimable {
    public enum ShareCode {
        private static let prefix = "OPALCLAIM"
        private static let version = "1"
        private static let separator: Character = ":"
        private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

        public static func encode(envelope: OpalBase.Claimable.Envelope) throws -> String {
            [
                prefix,
                version,
                networkToken(for: envelope.contract.network),
                encodeBase32(envelope.encode())
            ].joined(separator: String(separator))
        }

        public static func decode(_ text: String) throws -> OpalBase.Claimable.Envelope {
            let parsedCode = try parse(text)
            return try OpalBase.Claimable.Envelope.decode(
                from: parsedCode.envelopeData,
                on: parsedCode.network
            )
        }

        public static func decodeEnvelopeData(_ text: String) throws -> Data {
            let parsedCode = try parse(text)
            _ = try OpalBase.Claimable.Envelope.decode(
                from: parsedCode.envelopeData,
                on: parsedCode.network
            )
            return parsedCode.envelopeData
        }

        private static func parse(
            _ text: String
        ) throws -> (network: OpalBase.Network.Environment, envelopeData: Data) {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let components = trimmedText.split(
                separator: separator,
                omittingEmptySubsequences: false
            )
            guard components.count == 4 else {
                throw OpalBase.Claimable.Error.invalidShareCodeFormat
            }

            guard components[0].caseInsensitiveCompare(prefix) == .orderedSame else {
                throw OpalBase.Claimable.Error.invalidShareCodeFormat
            }
            guard components[1] == version else {
                throw OpalBase.Claimable.Error.unsupportedShareCodeVersion(String(components[1]))
            }

            let networkToken = String(components[2])
            let network = try network(from: networkToken)
            let payload = String(components[3])
            guard !payload.isEmpty else {
                throw OpalBase.Claimable.Error.emptyShareCodePayload
            }

            return (
                network: network,
                envelopeData: try decodeBase32(payload)
            )
        }

        private static func networkToken(
            for network: OpalBase.Network.Environment
        ) -> String {
            switch network {
            case .mainnet:
                return "MAINNET"
            case .testnet:
                return "TESTNET"
            case .chipnet:
                return "CHIPNET"
            }
        }

        private static func network(
            from token: String
        ) throws -> OpalBase.Network.Environment {
            switch token.uppercased() {
            case "MAINNET":
                return .mainnet
            case "TESTNET":
                return .testnet
            case "CHIPNET":
                return .chipnet
            default:
                throw OpalBase.Claimable.Error.invalidShareCodeNetwork(token)
            }
        }

        private static func encodeBase32(_ data: Data) -> String {
            var output = String()
            output.reserveCapacity((data.count * 8 + 4) / 5)

            var accumulator = 0
            var bitCount = 0

            for byte in data {
                accumulator = (accumulator << 8) | Int(byte)
                bitCount += 8

                while bitCount >= 5 {
                    bitCount -= 5
                    output.append(base32Alphabet[(accumulator >> bitCount) & 0x1f])
                    accumulator &= (1 << bitCount) - 1
                }
            }

            if bitCount > 0 {
                output.append(base32Alphabet[(accumulator << (5 - bitCount)) & 0x1f])
            }

            return output
        }

        private static func decodeBase32(_ text: String) throws -> Data {
            switch text.utf8.count % 8 {
            case 1, 3, 6:
                throw OpalBase.Claimable.Error.invalidShareCodePayload
            default:
                break
            }

            var output = Data()
            output.reserveCapacity(text.utf8.count * 5 / 8)

            var accumulator = 0
            var bitCount = 0

            for byte in text.utf8 {
                let value = try base32Value(for: byte)
                accumulator = (accumulator << 5) | Int(value)
                bitCount += 5

                while bitCount >= 8 {
                    bitCount -= 8
                    output.append(UInt8((accumulator >> bitCount) & 0xff))
                    accumulator &= (1 << bitCount) - 1
                }
            }

            guard accumulator == 0 else {
                throw OpalBase.Claimable.Error.invalidShareCodePayload
            }

            return output
        }

        private static func base32Value(for byte: UInt8) throws -> UInt8 {
            switch byte {
            case 0x41 ... 0x5a:
                return byte - 0x41
            case 0x32 ... 0x37:
                return byte - 0x32 + 26
            default:
                throw OpalBase.Claimable.Error.invalidShareCodePayload
            }
        }
    }
}
