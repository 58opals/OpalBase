// NetworkModel+ProtocolVersion.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    public struct ProtocolVersion: Comparable, CustomStringConvertible, Sendable, Hashable, Codable {
        public let major: Int
        public let minor: Int
        public let patch: Int
        public let isPatchComponentIncluded: Bool
        
        public init?(major: Int, minor: Int, patch: Int = 0, isPatchComponentIncluded: Bool? = nil) {
            guard major >= 0, minor >= 0, patch >= 0 else { return nil }
            self.major = major
            self.minor = minor
            self.patch = patch
            self.isPatchComponentIncluded = isPatchComponentIncluded ?? (patch != 0)
        }
        
        public init?(string: String) {
            let components = string.split(separator: ".").compactMap { Int($0) }
            switch components.count {
            case 2:
                self.init(major: components[0], minor: components[1], patch: 0, isPatchComponentIncluded: false)
            case 3:
                self.init(major: components[0], minor: components[1], patch: components[2], isPatchComponentIncluded: true)
            default:
                return nil
            }
        }
        
        init(_ protocolVersion: SwiftFulcrum.ProtocolVersion) {
            self.major = protocolVersion.major
            self.minor = protocolVersion.minor
            self.patch = protocolVersion.patch
            self.isPatchComponentIncluded = protocolVersion.description.split(separator: ".").count == 3
        }
        
        public var description: String {
            if !isPatchComponentIncluded && patch == 0 {
                return "\(major).\(minor)"
            }
            
            return "\(major).\(minor).\(patch)"
        }
        
        public static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.major != rhs.major {
                return lhs.major < rhs.major
            }
            
            if lhs.minor != rhs.minor {
                return lhs.minor < rhs.minor
            }
            
            return lhs.patch < rhs.patch
        }
    }
}

extension NetworkModel.ProtocolVersion {
    var swiftFulcrumProtocolVersion: SwiftFulcrum.ProtocolVersion {
        guard let protocolVersion = SwiftFulcrum.ProtocolVersion(
            major: major,
            minor: minor,
            patch: patch,
            isPatchComponentIncluded: isPatchComponentIncluded
        ) else {
            preconditionFailure("NetworkModel.ProtocolVersion must remain valid.")
        }
        
        return protocolVersion
    }
}
