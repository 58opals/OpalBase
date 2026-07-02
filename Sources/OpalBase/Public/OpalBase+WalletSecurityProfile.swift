// OpalBase+WalletSecurityProfile.swift

public extension OpalBase {
    /// Security posture contract for wallet apps that need explicit secret, network, and signing boundaries.
    struct WalletSecurityProfile: Sendable, Equatable {
        public enum NetworkAccess: Sendable, Equatable {
            case offline
            case publicChainSync
            case publicChainSyncAndBroadcast
        }

        public enum SigningAccess: Sendable, Equatable {
            case inProcess
            case externalReviewRequired
        }

        public enum Error: Swift.Error, Equatable, Sendable {
            case broadcastUnavailable(networkAccess: NetworkAccess)
            case externalSigningReviewUnavailable(signingAccess: SigningAccess)
            case offlineNetworkAccessRequired(actual: NetworkAccess)
            case secureEnclaveSecretPersistenceRequired(actual: OpalBase.Storage.Security.PersistencePolicy)
        }

        public let secretPersistencePolicy: OpalBase.Storage.Security.PersistencePolicy
        public let networkAccess: NetworkAccess
        public let signingAccess: SigningAccess

        public init(
            secretPersistencePolicy: OpalBase.Storage.Security.PersistencePolicy,
            networkAccess: NetworkAccess,
            signingAccess: SigningAccess
        ) {
            self.secretPersistencePolicy = secretPersistencePolicy
            self.networkAccess = networkAccess
            self.signingAccess = signingAccess
        }

        /// Profile for app layers that keep a Bitcoin Cash savings signer offline and fail closed on weak secret storage.
        public static let offlineSavingsSigner = Self(
            secretPersistencePolicy: .requireSecureEnclave,
            networkAccess: .offline,
            signingAccess: .externalReviewRequired
        )

        public var requiresSecureEnclaveSecretPersistence: Bool {
            secretPersistencePolicy == .requireSecureEnclave
        }

        public var requiresExternalSigningReview: Bool {
            signingAccess == .externalReviewRequired
        }

        public var allowsBroadcasting: Bool {
            networkAccess == .publicChainSyncAndBroadcast
        }

        public var requiresOfflineNetworkAccess: Bool {
            networkAccess == .offline
        }

        public func requireSecureEnclaveSecretPersistence() throws {
            guard requiresSecureEnclaveSecretPersistence else {
                throw Error.secureEnclaveSecretPersistenceRequired(actual: secretPersistencePolicy)
            }
        }

        public func requireExternalSigningReview() throws {
            guard requiresExternalSigningReview else {
                throw Error.externalSigningReviewUnavailable(signingAccess: signingAccess)
            }
        }

        public func requireOfflineNetworkAccess() throws {
            guard requiresOfflineNetworkAccess else {
                throw Error.offlineNetworkAccessRequired(actual: networkAccess)
            }
        }

        public func requireBroadcastingAllowed() throws {
            guard allowsBroadcasting else {
                throw Error.broadcastUnavailable(networkAccess: networkAccess)
            }
        }
    }
}
