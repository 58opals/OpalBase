// Network+Security+TLS.swift

import Foundation
import Security

extension Network.Security {
    public enum TLS {}
}

extension Network.Security.TLS {
    public struct Configuration: Sendable {
        public var pinnedCertificates: [Data]
        public var allowlist: Set<String>
        public var proxy: URL?
        
        public init(pinnedCertificates: [Data] = .init(),
                    allowlist: Set<String> = .init(),
                    proxy: URL? = nil) {
            self.pinnedCertificates = pinnedCertificates
            self.allowlist = allowlist
            self.proxy = proxy
        }
        
        public func isHostAllowed(_ host: String) -> Bool {
            allowlist.isEmpty || allowlist.contains(host)
        }
        
        public func validate(trust: SecTrust, for host: String) throws {
            let hostname = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard isHostAllowed(hostname) else { throw Network.Security.Error.untrustedHost(host) }
            
            let policy = SecPolicyCreateSSL(true, hostname as CFString)
            SecTrustSetPolicies(trust, policy)
            var cfError: CFError?
            guard SecTrustEvaluateWithError(trust, &cfError) else {
                throw Network.Security.Error.untrustedCertificate
            }
            
            guard !pinnedCertificates.isEmpty else { return }
            
            guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
                throw Network.Security.Error.untrustedCertificate
            }
            let pins = Set(pinnedCertificates)
            for cert in chain {
                let der = SecCertificateCopyData(cert) as Data
                if pins.contains(der) { return }
            }
            throw Network.Security.Error.untrustedCertificate
        }
    }
}

extension Network.Security {
    public enum Error: Swift.Error, Sendable {
        case untrustedHost(String)
        case untrustedCertificate
        case proxyFailure(URL, Swift.Error)
    }
}
