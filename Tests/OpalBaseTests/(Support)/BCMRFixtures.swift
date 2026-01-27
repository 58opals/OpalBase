import Foundation
@testable import OpalBase

enum BCMRFixtures {
    static let categoryHexadecimal = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    static let publicationHashHexadecimal = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    static let publicationUniformResourceIdentifier = "https://example.com/registry.json"
    static let registryString = "{\"version\":\"1\",\"identities\":{\"example.identity\":{\"2024-01-01T00:00:00Z\":{\"name\":\"Example Token\",\"description\":\"Example token description\",\"token\":{\"category\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\",\"symbol\":\"EXAMPLE\",\"decimals\":2},\"uris\":{\"icon\":\"https://example.com/icon.png\"}}}}}"
    static let registryHashHexadecimal = "21a3688943c9ca4ed3862d6f5e160ddad35955d1cdbe725a3cb830bcb4178be5"
    
    static var publicationHash: Data {
        makeData(from: publicationHashHexadecimal)
    }
    
    static var registryData: Data {
        Data(registryString.utf8)
    }
    
    static var registryHash: Data {
        makeData(from: registryHashHexadecimal)
    }
    
    static var publicationScript: Data {
        let prefix = Data([0x42, 0x43, 0x4d, 0x52])
        let uniformResourceIdentifierData = Data(publicationUniformResourceIdentifier.utf8)
        var script = Data([0x6a])
        script.append(Data.push(prefix))
        script.append(Data.push(publicationHash))
        script.append(Data.push(uniformResourceIdentifierData))
        return script
    }
    
    static var categoryIdentifier: CashTokens.CategoryID {
        do {
            return try CashTokens.CategoryID(hexFromRPC: categoryHexadecimal)
        } catch {
            fatalError("Expected valid category identifier: \(error)")
        }
    }
    
    static var registryIconLocation: URL {
        guard let url = URL(string: "https://example.com/icon.png") else {
            fatalError("Expected registry icon location to be valid.")
        }
        return url
    }
    
    private static func makeData(from hexadecimalString: String) -> Data {
        do {
            return try Data(hexadecimalString: hexadecimalString)
        } catch {
            fatalError("Expected valid hexadecimal string: \(error)")
        }
    }
}
