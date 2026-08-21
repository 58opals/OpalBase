// MosaicPrivateDeploymentDocumentFixture.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

enum MosaicPrivateDeploymentDocumentFixture {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha

    static func make() throws -> (
        opaquePoolDocument: Data,
        relaySetDocument: Data
    ) {
        let pool = try Alpha.OpaquePoolDocument(
            appGeneratedOpaqueIdentifier: [UInt8](
                repeating: 0x31,
                count: 32
            )
        )
        let registrations = try (1...3).map { index in
            try Alpha.RelayRegistrationDocument(
                endpoint: Alpha.PrivateRelayEndpoint(
                    normalizing: "wss://relay-\(index).example/"
                ),
                operatorIdentity: Alpha.RelayOperatorIdentity(
                    appReviewedRegistryLabel: "fixture operator \(index)"
                ),
                requiresNIP42Authentication: false,
                requiresProofOfWork: false
            )
        }
        let relaySet = try Alpha.RelaySetDocument(
            registrations: registrations
        )
        return (
            Data(pool.canonicalBytes),
            Data(relaySet.canonicalBytes)
        )
    }
}
#endif
