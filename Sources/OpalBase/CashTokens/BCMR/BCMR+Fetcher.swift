// BCMR+Fetcher.swift

import Foundation

extension BitcoinCashMetadataRegistries {
    public struct Fetcher: Sendable {
        public let urlSession: URLSession
        public let ipfsGateway: URL?
        public let maxBytes: Int
        
        public init(urlSession: URLSession = .shared, ipfsGateway: URL? = nil, maxBytes: Int) {
            self.urlSession = urlSession
            self.ipfsGateway = ipfsGateway
            self.maxBytes = maxBytes
        }
    }
}

extension BitcoinCashMetadataRegistries.Fetcher {
    public enum Error: Swift.Error, Sendable {
        case invalidResourceIdentifier(String)
        case unsupportedScheme(String)
        case missingInterPlanetaryFileSystemGateway
        case invalidInterPlanetaryFileSystemGateway(URL)
        case missingRedirectLocation
        case permanentRedirect(location: URL)
        case responseTooLarge(limit: Int, actual: Int)
        case unexpectedResponseStatus(Int)
        case invalidMaximumBytes(Int)
    }
    
    public func fetchRegistryBytes(from uri: String) async throws -> Data {
        let resolvedResourceLocation = try resolveRegistryLocation(from: uri)
        return try await fetchBytes(from: resolvedResourceLocation, remainingRedirects: 5)
    }
}

private extension BitcoinCashMetadataRegistries.Fetcher {
    func fetchBytes(from resourceLocation: URL, remainingRedirects: Int) async throws -> Data {
        guard maxBytes > 0 else {
            throw Error.invalidMaximumBytes(maxBytes)
        }
        
        var redirectsRemaining = remainingRedirects
        var currentResourceLocation = resourceLocation
        
        while true {
            let request = URLRequest(url: currentResourceLocation)
            let (bytes, response) = try await urlSession.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw Error.unexpectedResponseStatus(-1)
            }
            
            if response.statusCode == 301 {
                let location = try resolveRedirectLocation(from: response, currentResourceLocation: currentResourceLocation)
                throw Error.permanentRedirect(location: location)
            }
            
            if response.statusCode == 302 {
                guard redirectsRemaining > 0 else {
                    throw Error.unexpectedResponseStatus(response.statusCode)
                }
                let location = try resolveRedirectLocation(from: response, currentResourceLocation: currentResourceLocation)
                redirectsRemaining -= 1
                currentResourceLocation = location
                continue
            }
            
            guard (200...299).contains(response.statusCode) else {
                throw Error.unexpectedResponseStatus(response.statusCode)
            }
            
            noteCacheControlMaxAge(from: response, resourceLocation: currentResourceLocation)
            let expectedLength = response.expectedContentLength
            if expectedLength > 0, expectedLength > Int64(maxBytes) {
                let actualLength = expectedLength > Int64(Int.max) ? Int.max : Int(expectedLength)
                throw Error.responseTooLarge(limit: maxBytes, actual: actualLength)
            }
            
            var data = Data()
            let reserveCapacity = expectedLength > 0
            ? min(maxBytes, Int(min(expectedLength, Int64(Int.max))))
            : 0
            data.reserveCapacity(reserveCapacity)
            var byteCount = 0
            for try await byte in bytes {
                byteCount += 1
                if byteCount > maxBytes {
                    throw Error.responseTooLarge(limit: maxBytes, actual: byteCount)
                }
                data.append(byte)
            }
            return data
        }
    }
    
    func resolveRegistryLocation(from uri: String) throws -> URL {
        guard let resourceLocation = URL(string: uri),
              let scheme = resourceLocation.scheme?.lowercased() else {
            throw Error.invalidResourceIdentifier(uri)
        }
        
        switch scheme {
        case "https":
            return resourceLocation
        case "ipfs":
            return try resolveInterPlanetaryFileSystemGatewayLocation(from: resourceLocation)
        default:
            throw Error.unsupportedScheme(scheme)
        }
    }
    
    func resolveInterPlanetaryFileSystemGatewayLocation(
        from interPlanetaryFileSystemLocation: URL
    ) throws -> URL {
        guard let gateway = ipfsGateway else {
            throw Error.missingInterPlanetaryFileSystemGateway
        }
        guard let gatewayScheme = gateway.scheme, let gatewayHost = gateway.host else {
            throw Error.invalidInterPlanetaryFileSystemGateway(gateway)
        }
        
        var gatewayComponents = URLComponents()
        gatewayComponents.scheme = gatewayScheme
        gatewayComponents.host = gatewayHost
        gatewayComponents.port = gateway.port
        
        var pathComponents: [String] = .init()
        let gatewayPath = gateway.path.split(separator: "/").map(String.init)
        pathComponents.append(contentsOf: gatewayPath)
        pathComponents.append("ipfs")
        
        let interPlanetaryPathComponents = interPlanetaryFileSystemLocation.path
            .split(separator: "/")
            .map(String.init)
        if let host = interPlanetaryFileSystemLocation.host {
            pathComponents.append(host)
            pathComponents.append(contentsOf: interPlanetaryPathComponents)
        } else if let firstComponent = interPlanetaryPathComponents.first {
            pathComponents.append(firstComponent)
            pathComponents.append(contentsOf: interPlanetaryPathComponents.dropFirst())
        } else {
            throw Error.invalidResourceIdentifier(interPlanetaryFileSystemLocation.absoluteString)
        }
        
        gatewayComponents.path = "/" + pathComponents.joined(separator: "/")
        gatewayComponents.query = interPlanetaryFileSystemLocation.query
        
        guard let resolvedResourceLocation = gatewayComponents.url else {
            throw Error.invalidInterPlanetaryFileSystemGateway(gateway)
        }
        return resolvedResourceLocation
    }
    
    func resolveRedirectLocation(
        from response: HTTPURLResponse,
        currentResourceLocation: URL
    ) throws -> URL {
        guard let locationValue = response.value(forHTTPHeaderField: "Location") else {
            throw Error.missingRedirectLocation
        }
        if let locationResource = URL(string: locationValue, relativeTo: currentResourceLocation) {
            return locationResource
        }
        throw Error.missingRedirectLocation
    }
    
    func noteCacheControlMaxAge(from response: HTTPURLResponse, resourceLocation: URL) {
        guard let cacheControl = response.value(forHTTPHeaderField: "Cache-Control") else { return }
        let directives = cacheControl.split(separator: ",")
        for directive in directives {
            let trimmed = directive.trimmingCharacters(in: .whitespaces)
            let lowercased = trimmed.lowercased()
            if lowercased.hasPrefix("max-age=") {
                let valueString = trimmed.dropFirst("max-age=".count)
                if let seconds = Int(valueString) {
                    print("Cache-Control max-age=\(seconds) for \(resourceLocation.absoluteString)")
                }
            }
        }
    }
}
