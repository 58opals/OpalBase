// OpalBase.CashTokens.BCMR.Client+Fetcher.swift

import Foundation

extension OpalBase.CashTokens.BCMR.Client {
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

extension OpalBase.CashTokens.BCMR.Client.Fetcher {
    public struct RegistryFetchResult: Sendable {
        public let bytes: Data
        public let finalURL: URL
        public let cacheExpiration: Date?
        public let permanentRedirectLocation: URL?

        public init(
            bytes: Data,
            finalURL: URL,
            cacheExpiration: Date?,
            permanentRedirectLocation: URL?
        ) {
            self.bytes = bytes
            self.finalURL = finalURL
            self.cacheExpiration = cacheExpiration
            self.permanentRedirectLocation = permanentRedirectLocation
        }
    }

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
    
    public func fetchRegistry(from uri: String) async throws -> RegistryFetchResult {
        let resolvedResourceLocation = try resolveRegistryLocation(from: uri)
        return try await fetchRegistry(from: resolvedResourceLocation, remainingRedirects: 5)
    }

    public func fetchRegistryBytes(from uri: String) async throws -> Data {
        try await fetchRegistry(from: uri).bytes
    }
}

private extension OpalBase.CashTokens.BCMR.Client.Fetcher {
    static let registryWellKnownPath = "/.well-known/bitcoin-cash-metadata-registry.json"

    func fetchRegistry(
        from resourceLocation: URL,
        remainingRedirects: Int
    ) async throws -> RegistryFetchResult {
        guard maxBytes > 0 else {
            throw Error.invalidMaximumBytes(maxBytes)
        }
        
        var redirectsRemaining = remainingRedirects
        var currentResourceLocation = resourceLocation
        var permanentRedirectLocation: URL?
        
        while true {
            try validateFetchScheme(for: currentResourceLocation)
            let request = URLRequest(url: currentResourceLocation)
            let (bytes, response) = try await urlSession.bytes(
                for: request,
                delegate: RedirectPreservingDelegate()
            )
            guard let response = response as? HTTPURLResponse else {
                throw Error.unexpectedResponseStatus(-1)
            }
            try validateFetchScheme(for: response.url ?? currentResourceLocation)
            
            if response.statusCode == 301 {
                let location = try resolveRedirectLocation(from: response, currentResourceLocation: currentResourceLocation)
                permanentRedirectLocation = permanentRedirectLocation ?? location
                guard redirectsRemaining > 0 else {
                    throw Error.unexpectedResponseStatus(response.statusCode)
                }
                redirectsRemaining -= 1
                currentResourceLocation = location
                continue
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
            
            let cacheExpiration = parseCacheExpiration(from: response, now: Date())
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
            return RegistryFetchResult(
                bytes: data,
                finalURL: response.url ?? currentResourceLocation,
                cacheExpiration: cacheExpiration,
                permanentRedirectLocation: permanentRedirectLocation
            )
        }
    }
    
    func resolveRegistryLocation(from uri: String) throws -> URL {
        let trimmedURI = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURI.isEmpty else {
            throw Error.invalidResourceIdentifier(uri)
        }

        if let resourceComponents = URLComponents(string: trimmedURI),
           let scheme = resourceComponents.scheme?.lowercased() {
            return try resolveRegistryLocation(
                from: resourceComponents,
                scheme: scheme,
                originalURI: trimmedURI
            )
        }

        guard let bareComponents = URLComponents(string: "https://\(trimmedURI)") else {
            throw Error.invalidResourceIdentifier(uri)
        }
        return try resolveHTTPSRegistryLocation(from: bareComponents, originalURI: trimmedURI)
    }

    func resolveRegistryLocation(
        from resourceComponents: URLComponents,
        scheme: String,
        originalURI: String
    ) throws -> URL {
        switch scheme {
        case "https":
            return try resolveHTTPSRegistryLocation(from: resourceComponents, originalURI: originalURI)
        case "ipfs":
            guard let resourceLocation = resourceComponents.url else {
                throw Error.invalidResourceIdentifier(originalURI)
            }
            return try resolveInterPlanetaryFileSystemGatewayLocation(from: resourceLocation)
        default:
            throw Error.unsupportedScheme(scheme)
        }
    }

    func resolveHTTPSRegistryLocation(
        from resourceComponents: URLComponents,
        originalURI: String
    ) throws -> URL {
        guard resourceComponents.scheme?.lowercased() == "https",
              let host = resourceComponents.host,
              !host.isEmpty
        else {
            throw Error.invalidResourceIdentifier(originalURI)
        }

        var normalizedComponents = resourceComponents
        if normalizedComponents.path.isEmpty || normalizedComponents.path == "/" {
            normalizedComponents.path = Self.registryWellKnownPath
        }

        guard let resourceLocation = normalizedComponents.url else {
            throw Error.invalidResourceIdentifier(originalURI)
        }
        return resourceLocation
    }
    
    func resolveInterPlanetaryFileSystemGatewayLocation(
        from interPlanetaryFileSystemLocation: URL
    ) throws -> URL {
        guard let gateway = ipfsGateway else {
            throw Error.missingInterPlanetaryFileSystemGateway
        }
        guard let gatewayScheme = gateway.scheme,
              gatewayScheme.lowercased() == "https",
              let gatewayHost = gateway.host,
              !gatewayHost.isEmpty else {
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
            let resolvedLocation = locationResource.absoluteURL
            try validateFetchScheme(for: resolvedLocation)
            return resolvedLocation
        }
        throw Error.missingRedirectLocation
    }

    func validateFetchScheme(for resourceLocation: URL) throws {
        let scheme = resourceLocation.scheme?.lowercased()
        guard scheme == "https" else {
            throw Error.unsupportedScheme(scheme ?? "")
        }
    }
    
    func parseCacheExpiration(from response: HTTPURLResponse, now: Date) -> Date? {
        guard let cacheControl = response.value(forHTTPHeaderField: "Cache-Control") else { return nil }
        let directives = cacheControl.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard !directives.contains("no-store") else { return nil }
        guard !directives.contains("no-cache") else { return nil }

        for directive in directives {
            if directive.hasPrefix("max-age=") {
                let valueString = directive.dropFirst("max-age=".count)
                if let seconds = TimeInterval(String(valueString)), seconds >= 0 {
                    return now.addingTimeInterval(seconds)
                }
            }
        }
        return nil
    }
}

private final class RedirectPreservingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
