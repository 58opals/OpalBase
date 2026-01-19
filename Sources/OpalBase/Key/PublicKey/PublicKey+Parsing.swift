// PublicKey+Parsing.swift

import Foundation

extension PublicKey {
    enum Parsing {
        enum Error: Swift.Error, Equatable {
            case invalidLength(actual: Int)
            case invalidPrefix(byte: UInt8)
            case invalidPoint
        }
        
        static func parsePublicKey(_ data: Data) throws -> AffinePoint {
            switch data.count {
            case 33:
                return try parseCompressed(data)
            case 65:
                return try parseUncompressed(data)
            default:
                throw Error.invalidLength(actual: data.count)
            }
        }
        
        private static func parseCompressed(_ data: Data) throws -> AffinePoint {
            guard let prefix = data.first else {
                throw Error.invalidLength(actual: data.count)
            }
            guard prefix == 0x02 || prefix == 0x03 else {
                throw Error.invalidPrefix(byte: prefix)
            }
            let xData = data.dropFirst()
            let xCoordinate = try FieldElement(data32: Data(xData))
            let ySquared = xCoordinate.square().mul(xCoordinate).add(.seven)
            guard var yCoordinate = ySquared.sqrt() else {
                throw Error.invalidPoint
            }
            let shouldBeOdd = prefix == 0x03
            if yCoordinate.isOdd != shouldBeOdd {
                yCoordinate = yCoordinate.negate()
            }
            let point = AffinePoint(x: xCoordinate, y: yCoordinate)
            guard point.isOnCurve else {
                throw Error.invalidPoint
            }
            return point
        }
        
        private static func parseUncompressed(_ data: Data) throws -> AffinePoint {
            guard let prefix = data.first else {
                throw Error.invalidLength(actual: data.count)
            }
            guard prefix == 0x04 else {
                throw Error.invalidPrefix(byte: prefix)
            }
            let xData = data.subdata(in: 1..<33)
            let yData = data.subdata(in: 33..<65)
            let xCoordinate = try FieldElement(data32: xData)
            let yCoordinate = try FieldElement(data32: yData)
            let point = AffinePoint(x: xCoordinate, y: yCoordinate)
            guard point.isOnCurve else {
                throw Error.invalidPoint
            }
            return point
        }
    }
}
