// OpalBase+Account+MosaicPrivateAlphaRuntime+Binding.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Exact protocol identity shared by the application, OpalBase, and OpalFusion.
    @_spi(MosaicPrivateAlpha)
    public struct Binding: Hashable, Sendable {
        @_spi(MosaicPrivateAlpha) public let attemptIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let generationIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let materialIdentifier: Data

        @_spi(MosaicPrivateAlpha)
        public init?(
            attemptIdentifier: Data,
            generationIdentifier: Data,
            materialIdentifier: Data
        ) {
            guard attemptIdentifier.count == 32,
                  generationIdentifier.count == 32,
                  materialIdentifier.count == 32 else {
                return nil
            }
            self.attemptIdentifier = Data(attemptIdentifier)
            self.generationIdentifier = Data(generationIdentifier)
            self.materialIdentifier = Data(materialIdentifier)
        }

        init(_ binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding) {
            attemptIdentifier = binding.attemptIdentifier
            generationIdentifier = binding.generationIdentifier
            materialIdentifier = binding.materialIdentifier
        }

        var fusionBinding: OpalFusion.MosaicPrivateAlphaRuntime.Binding {
            get throws {
                try .init(
                    attemptIdentifier: attemptIdentifier,
                    generationIdentifier: generationIdentifier,
                    materialIdentifier: materialIdentifier
                )
            }
        }
    }
}
#endif
