// OpalBase+Network+ProtocolVersion.swift

import SwiftFulcrum

extension _OpalBase.Network {
    public struct ProtocolVersion: Comparable, CustomStringConvertible, Sendable, Hashable, Codable {
        public let major: Int
        public let minor: Int
        public let patch: Int
        public let isPatchComponentIncluded: Bool
        
        public init?(major: Int, minor: Int, patch: Int = 0, isPatchComponentIncluded: Bool? = nil) {
            guard major >= 0, minor >= 0, patch >= 0 else { return nil }
            guard patch == 0 || isPatchComponentIncluded != false else { return nil }
            self.major = major
            self.minor = minor
            self.patch = patch
            self.isPatchComponentIncluded = isPatchComponentIncluded ?? (patch != 0)
        }
        
        public init?(string: String) {
            let versionComponents = string.split(separator: ".", omittingEmptySubsequences: false)
            let parsedComponents = versionComponents.compactMap(Self.parseCanonicalDecimalComponent)
            guard parsedComponents.count == versionComponents.count else { return nil }
            switch versionComponents.count {
            case 2:
                self.init(
                    major: parsedComponents[0],
                    minor: parsedComponents[1],
                    patch: 0,
                    isPatchComponentIncluded: false
                )
            case 3:
                self.init(
                    major: parsedComponents[0],
                    minor: parsedComponents[1],
                    patch: parsedComponents[2],
                    isPatchComponentIncluded: true
                )
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

        private static func parseCanonicalDecimalComponent(_ component: Substring) -> Int? {
            guard !component.isEmpty else { return nil }
            if component.count > 1, component.first == "0" { return nil }
            guard component.unicodeScalars.allSatisfy({ scalar in
                scalar.value >= 48 && scalar.value <= 57
            }) else { return nil }
            return Int(component)
        }
    }
}

extension _OpalBase.Network.ProtocolVersion {
    private enum CodingKeys: String, CodingKey {
        case major
        case minor
        case patch
        case isPatchComponentIncluded
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let major = try container.decode(Int.self, forKey: .major)
        let minor = try container.decode(Int.self, forKey: .minor)
        let patch = try container.decode(Int.self, forKey: .patch)
        let isPatchComponentIncluded = try container.decode(Bool.self, forKey: .isPatchComponentIncluded)
        
        guard let version = Self(
            major: major,
            minor: minor,
            patch: patch,
            isPatchComponentIncluded: isPatchComponentIncluded
        ) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid protocol version components")
            )
        }
        
        self = version
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(major, forKey: .major)
        try container.encode(minor, forKey: .minor)
        try container.encode(patch, forKey: .patch)
        try container.encode(isPatchComponentIncluded, forKey: .isPatchComponentIncluded)
    }
}

extension _OpalBase.Network.ProtocolVersion {
    var swiftFulcrumProtocolVersion: SwiftFulcrum.ProtocolVersion? {
        SwiftFulcrum.ProtocolVersion(
            major: major,
            minor: minor,
            patch: patch,
            isPatchComponentIncluded: isPatchComponentIncluded
        )
    }
}
