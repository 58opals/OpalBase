// OpalBase+CashTokens+BCMR+Client+Fetcher.swift

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
            self.bytes = Data(bytes)
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
    
    public func fetchRegistry(from resourceIdentifier: String) async throws -> RegistryFetchResult {
        let resolvedResourceLocation = try resolveRegistryLocation(from: resourceIdentifier)
        do {
            return try await fetchRegistry(from: resolvedResourceLocation, remainingRedirects: 5)
        } catch where OpalBaseCancellation.isCancellationError(error) {
            throw CancellationError()
        }
    }

    public func fetchRegistryBytes(from resourceIdentifier: String) async throws -> Data {
        try await fetchRegistry(from: resourceIdentifier).bytes
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
            try validateFetchLocation(currentResourceLocation)
            let request = URLRequest(url: currentResourceLocation)
            let (bytes, response) = try await urlSession.bytes(
                for: request,
                delegate: RedirectPreservingDelegate()
            )
            guard let response = response as? HTTPURLResponse else {
                throw Error.unexpectedResponseStatus(-1)
            }
            try validateFetchLocation(response.url ?? currentResourceLocation)
            
            if let redirectKind = RedirectKind(statusCode: response.statusCode) {
                guard redirectsRemaining > 0 else {
                    throw Error.unexpectedResponseStatus(response.statusCode)
                }
                let location = try resolveRedirectLocation(from: response, currentResourceLocation: currentResourceLocation)
                if case .permanent = redirectKind {
                    permanentRedirectLocation = permanentRedirectLocation ?? location
                }
                redirectsRemaining -= 1
                currentResourceLocation = location
                continue
            }
            
            guard (200...299).contains(response.statusCode) else {
                throw Error.unexpectedResponseStatus(response.statusCode)
            }
            
            let cacheExpiration = parseCacheExpiration(from: response, now: Date())
            let expectedLength = response.expectedContentLength
            let expectedByteCount = expectedLength > 0
                ? min(expectedLength, Int64(Int.max))
                : 0
            if expectedByteCount > Int64(maxBytes) {
                let actualLength = Int(expectedByteCount)
                throw Error.responseTooLarge(limit: maxBytes, actual: actualLength)
            }
            
            var data = Data()
            let reserveCapacity = expectedByteCount > 0 ? min(maxBytes, Int(expectedByteCount)) : 0
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
    
    func resolveRegistryLocation(from resourceIdentifier: String) throws -> URL {
        let trimmedResourceIdentifier = resourceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResourceIdentifier.isEmpty else {
            throw Error.invalidResourceIdentifier(resourceIdentifier)
        }

        if let resourceComponents = URLComponents(string: trimmedResourceIdentifier),
           let scheme = resourceComponents.scheme?.lowercased() {
            switch scheme {
            case "https":
                return try resolveHTTPSRegistryLocation(from: resourceComponents, originalURI: trimmedResourceIdentifier)
            case "ipfs":
                guard let resourceLocation = resourceComponents.url else {
                    throw Error.invalidResourceIdentifier(trimmedResourceIdentifier)
                }
                return try resolveInterPlanetaryFileSystemGatewayLocation(from: resourceLocation)
            case _ where trimmedResourceIdentifier.contains("://"):
                throw Error.unsupportedScheme(scheme)
            default:
                break
            }
        }

        guard let bareComponents = URLComponents(string: "https://\(trimmedResourceIdentifier)") else {
            throw Error.invalidResourceIdentifier(resourceIdentifier)
        }
        return try resolveHTTPSRegistryLocation(from: bareComponents, originalURI: trimmedResourceIdentifier)
    }

    func resolveHTTPSRegistryLocation(
        from resourceComponents: URLComponents,
        originalURI: String
    ) throws -> URL {
        guard let rawResourceLocation = resourceComponents.url,
              Self.makeHypertextTransferProtocolSecureAuthority(from: rawResourceLocation) != nil,
              !URLPathTraversal.containsPathTraversal(in: rawResourceLocation) else {
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
        guard interPlanetaryFileSystemLocation.user == nil,
              interPlanetaryFileSystemLocation.password == nil else {
            throw Error.invalidResourceIdentifier(interPlanetaryFileSystemLocation.absoluteString)
        }
        guard let gateway = ipfsGateway else {
            throw Error.missingInterPlanetaryFileSystemGateway
        }
        guard let gatewayAuthority = Self.makeHypertextTransferProtocolSecureAuthority(from: gateway) else {
            throw Error.invalidInterPlanetaryFileSystemGateway(gateway)
        }
        
        var gatewayComponents = URLComponents()
        gatewayComponents.scheme = gatewayAuthority.scheme
        gatewayComponents.host = gatewayAuthority.host
        gatewayComponents.port = gateway.port
        
        let interPlanetaryPathComponents = interPlanetaryFileSystemLocation.path
            .split(separator: "/")
            .map(String.init)
        guard !URLPathTraversal.containsPathTraversal(interPlanetaryPathComponents) else {
            throw Error.invalidResourceIdentifier(interPlanetaryFileSystemLocation.absoluteString)
        }
        let contentPathComponents: [String]
        if let host = interPlanetaryFileSystemLocation.host {
            guard !URLPathTraversal.containsPathTraversal([host]) else {
                throw Error.invalidResourceIdentifier(interPlanetaryFileSystemLocation.absoluteString)
            }
            contentPathComponents = [host] + interPlanetaryPathComponents
        } else if !interPlanetaryPathComponents.isEmpty {
            contentPathComponents = interPlanetaryPathComponents
        } else {
            throw Error.invalidResourceIdentifier(interPlanetaryFileSystemLocation.absoluteString)
        }
        
        let gatewayPathComponents = gateway.path.split(separator: "/").map(String.init)
        guard !URLPathTraversal.containsPathTraversal(gatewayPathComponents) else {
            throw Error.invalidInterPlanetaryFileSystemGateway(gateway)
        }
        let pathComponents = gatewayPathComponents + ["ipfs"] + contentPathComponents
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
        guard !URLPathTraversal.containsPathTraversal(inLocationValue: locationValue) else {
            throw Error.invalidResourceIdentifier(locationValue)
        }
        if let locationResource = URL(string: locationValue, relativeTo: currentResourceLocation) {
            let resolvedLocation = locationResource.absoluteURL
            try validateFetchLocation(resolvedLocation)
            return resolvedLocation
        }
        throw Error.missingRedirectLocation
    }

    func validateFetchLocation(_ resourceLocation: URL) throws {
        let scheme = resourceLocation.scheme?.lowercased()
        guard scheme == "https" else {
            throw Error.unsupportedScheme(scheme ?? "")
        }
        guard Self.makeHypertextTransferProtocolSecureAuthority(from: resourceLocation) != nil else {
            throw Error.invalidResourceIdentifier(resourceLocation.absoluteString)
        }
        guard !URLPathTraversal.containsPathTraversal(in: resourceLocation) else {
            throw Error.invalidResourceIdentifier(resourceLocation.absoluteString)
        }
    }
    
    func parseCacheExpiration(from response: HTTPURLResponse, now: Date) -> Date? {
        guard let cacheControl = response.value(forHTTPHeaderField: "Cache-Control") else { return nil }
        var cacheExpiration: Date?

        for directive in cacheControl.split(separator: ",") {
            let parsedDirective = parseCacheControlDirective(String(directive))
            switch parsedDirective.name {
            case "no-store", "no-cache":
                return nil
            case "max-age" where cacheExpiration == nil:
                if let value = parsedDirective.value,
                   isCacheControlDeltaSeconds(value),
                   let seconds = TimeInterval(value),
                   seconds.isFinite {
                    cacheExpiration = now.addingTimeInterval(seconds)
                }
            default:
                break
            }
        }

        return cacheExpiration
    }

    func isCacheControlDeltaSeconds(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (0x30...0x39).contains($0) }
    }

    static func makeHypertextTransferProtocolSecureAuthority(from url: URL) -> (scheme: String, host: String)? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host,
              isValidAuthorityHost(host),
              isValidPort(url.port),
              url.user == nil,
              url.password == nil else { return nil }
        return (scheme, host)
    }

    static func isValidAuthorityHost(_ host: String) -> Bool {
        guard !host.isEmpty,
              !URLPathTraversal.containsPathTraversal([host]) else {
            return false
        }
        return URLHostValidation.isValidUnbracketedHostLiteralOrName(host)
    }

    static func isValidPort(_ port: Int?) -> Bool {
        guard let port else { return true }
        return (1...65_535).contains(port)
    }

    func parseCacheControlDirective(_ directive: String) -> (name: String, value: String?) {
        let parts = directive.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let name = (parts.first?.trimmingCharacters(in: .whitespaces) ?? directive).lowercased()
        let value = parts.dropFirst().first?.trimmingCharacters(in: .whitespaces)
        return (name: name, value: value)
    }

    enum RedirectKind {
        case permanent
        case temporary

        init?(statusCode: Int) {
            switch statusCode {
            case 301, 308:
                self = .permanent
            case 302, 303, 307:
                self = .temporary
            default:
                return nil
            }
        }

    }
}
