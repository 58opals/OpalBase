import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

extension Tag {
    @Tag static var unit: Self
    @Tag static var integration: Self
    @Tag static var fulcrum: Self
    @Tag static var slow: Self
    @Tag static var flaky: Self
    @Tag static var crypto: Self
    @Tag static var policy: Self
    @Tag static var serialization: Self
    @Tag static var script: Self
    @Tag static var address: Self
    @Tag static var transaction: Self
    @Tag static var wallet: Self
    @Tag static var key: Self
    @Tag static var network: Self
    @Tag static var core: Self
}

enum Environment {
    private static let environment = ProcessInfo.processInfo.environment
    
    private static let networkOverride: Bool? = {
        guard let value = environment["OPAL_NETWORK_TESTS"] else { return nil }
        return value == "1"
    }()
    
    private static let fulcrumOverride: String? = {
        guard let value = environment["OPAL_FULCRUM_URL"] else { return nil }
        return FulcrumEndpointResolver.sanitized(urlString: value)
    }()
    
    private static let cachedFulcrumEndpoint: String? = {
        if let override = fulcrumOverride { return override }
        guard let fallback = FulcrumEndpointResolver.fallbackEndpoint else { return nil }
        return fallback.absoluteString
    }()
    
    static let network: Bool = networkOverride ?? (cachedFulcrumEndpoint != nil)
    static let fulcrumURL: String? = cachedFulcrumEndpoint
    static let fixtureDirectory = environment["OPAL_FIXTURE_DIRECTORY"] ?? "Tests/Fixtures"
    static let walletWIF = environment["OPAL_WALLET_WIF"]
    static let transactionRecipient = environment["OPAL_TX_RECIPIENT"]
    static let transactionSatoshis: UInt64? = environment["OPAL_TX_SATOSHIS"].flatMap(UInt64.init)
    static let transactionFeePerByte: UInt64? = environment["OPAL_TX_FEE_PER_BYTE"].flatMap(UInt64.init)
    static let sendAddress: Address? = parseSendAddress()
    static let sendAmount: Satoshi? = parseSendAmount()
    static let testBalanceAccountIndex: Int = getTestBalanceAccountIndex()
    
    static func getTestBalanceAccountIndex(default defaultIndex: Int = 0) -> Int {
        guard let value = ProcessInfo.processInfo.environment["OPAL_TEST_BALANCE_ACCOUNT"],
              let parsed = Int(value)
        else { return defaultIndex }
        
        return parsed
    }
    
    static func parseSendAddress() -> Address? {
        guard let value = ProcessInfo.processInfo.environment["OPAL_TEST_SEND_ADDRESS"], !value.isEmpty else { return nil }
        
        do { return try Address(value) }
        catch { return nil }
    }
    
    static func parseSendAmount() -> Satoshi? {
        guard let value = ProcessInfo.processInfo.environment["OPAL_TEST_SEND_AMOUNT_SATS"],
              let parsed = UInt64(value)
        else { return nil }
        
        return try? Satoshi(parsed)
    }
}

private enum FulcrumEndpointResolver {
    private struct Server: Decodable {
        let host: String
        let port: Int
        
        var secureURL: URL? {
            var components = URLComponents()
            components.scheme = "wss"
            components.host = self.host
            components.port = self.port
            return components.url
        }
    }
    
    static let fallbackEndpoint: URL? = {
        guard let resourceURL = locateServersJSON() else { return nil }
        do {
            let data = try Data(contentsOf: resourceURL)
            let servers = try JSONDecoder().decode([Server].self, from: data)
            return servers.compactMap(\.secureURL).randomElement()
        } catch {
            return nil
        }
    }()
    
    static func sanitized(urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["ws", "wss"].contains(scheme)
        else { return nil }
        return url.absoluteString
    }
    
    private static func locateServersJSON() -> URL? {
        let fileManager = FileManager.default
        let resourceName = "servers"
        let resourceExtension = "json"
        let bundles = Bundle.allBundles + Bundle.allFrameworks
        
        for bundle in bundles {
            if let direct = bundle.url(forResource: resourceName, withExtension: resourceExtension) {
                return direct
            }
            
            guard let resourceURL = bundle.resourceURL else { continue }
            
            let candidateBundleNames = [
                "SwiftFulcrum_SwiftFulcrum.bundle",
                "SwiftFulcrum_SwiftFulcrum.resources"
            ]
            
            for bundleName in candidateBundleNames {
                let bundleURL = resourceURL.appendingPathComponent(bundleName)
                if let nestedBundle = Bundle(url: bundleURL),
                   let nestedResource = nestedBundle.url(forResource: resourceName, withExtension: resourceExtension) {
                    return nestedResource
                }
            }
            
            guard let enumerator = fileManager.enumerator(at: resourceURL, includingPropertiesForKeys: nil) else { continue }
            for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "servers.json" {
                return fileURL
            }
        }
        
        return nil
    }
}

extension TimeInterval {
    static let fast: TimeInterval = 2      // unit
    static let io: TimeInterval = 15       // integration I/O
    static let network: TimeInterval = 30  // live network
}
