// OpalBase.PrivateKey+ExtendedModel~Derivation.swift

import Foundation

extension _OpalBase.PrivateKey.ExtendedModel {
    private func deriveChildPrivateKey(at index: UInt32, computeParentFingerprint: Bool) throws -> OpalBase.PrivateKey.ExtendedModel {
        let parentPrivateKey = privateKey
        let isHardened = HardenModel.checkHardened(index)
        let shouldComputeParentPublicKey = computeParentFingerprint || !isHardened
        let parentPublicKey: Data?

        if shouldComputeParentPublicKey {
            parentPublicKey = try OpalBase.PublicKey(privateKey: .init(data: parentPrivateKey)).compressedData
        } else {
            parentPublicKey = nil
        }

        var data = Data()
        data.reserveCapacity(37)

        if isHardened {
            data.append(Data([0x00]))
            data.append(parentPrivateKey)
        } else {
            guard let parentPublicKey else { throw OpalBase.PrivateKey.Error.invalidDerivedKey }
            data.append(parentPublicKey)
        }

        data.append(index.bigEndianData)

        let hashMessageAuthenticationCode = HMACSHA512Model.hash(data, key: chainCode)
        let leftHashMessageAuthenticationCodePart = Data(hashMessageAuthenticationCode.prefix(32))
        let rightHashMessageAuthenticationCodePart = Data(hashMessageAuthenticationCode.suffix(32))

        let childPrivateKey: Data
        do {
            childPrivateKey = try Secp256k1Model.OperationModel.tweakAddPrivateKey32(parentPrivateKey, tweak32: leftHashMessageAuthenticationCodePart)
        } catch {
            throw OpalBase.PrivateKey.Error.invalidDerivedKey
        }
        let childChainCode = rightHashMessageAuthenticationCodePart
        let childDepth = depth + 1
        let childParentFingerprint: Data

        if computeParentFingerprint {
            guard let parentPublicKey else { throw OpalBase.PrivateKey.Error.invalidDerivedKey }
            childParentFingerprint = Data(HASH160Model.hash(parentPublicKey).prefix(4))
        } else {
            childParentFingerprint = Data(repeating: 0, count: 4)
        }
        let childIndexNumber = index

        return .init(privateKey: childPrivateKey, chainCode: childChainCode, depth: childDepth, parentFingerprint: childParentFingerprint, childIndexNumber: childIndexNumber)
    }

    func deriveNonHardenedChildUsingParentKey(at index: UInt32,
                                              parentCompressedPublicKey: Data,
                                              parentFingerprint: Data) throws -> OpalBase.PrivateKey.ExtendedModel {
        guard !HardenModel.checkHardened(index) else { throw OpalBase.PrivateKey.Error.invalidDerivedKey }

        var data = Data()
        data.reserveCapacity(37)
        data.append(parentCompressedPublicKey)
        data.append(index.bigEndianData)

        let hmac = HMACSHA512Model.hash(data, key: chainCode)
        let leftHMACPart = Data(hmac.prefix(32))
        let rightHMACPart = Data(hmac.suffix(32))

        let childPrivateKey: Data
        do {
            childPrivateKey = try Secp256k1Model.OperationModel.tweakAddPrivateKey32(privateKey, tweak32: leftHMACPart)
        } catch {
            throw OpalBase.PrivateKey.Error.invalidDerivedKey
        }

        return .init(privateKey: childPrivateKey,
                     chainCode: rightHMACPart,
                     depth: depth + 1,
                     parentFingerprint: parentFingerprint,
                     childIndexNumber: index)
    }

    func deriveChild(at path: OpalBase.DerivationPath) throws -> OpalBase.PrivateKey.ExtendedModel {
        try deriveChild(at: path.makeIndices())
    }

    func deriveChild(at indices: [UInt32]) throws -> OpalBase.PrivateKey.ExtendedModel {
        var extendedKey = self
        let startingDepth = Int(depth)

        guard indices.count >= startingDepth else {
            throw OpalBase.PrivateKey.Error.derivationPathTooShort
        }

        for index in indices.dropFirst(startingDepth) {
            extendedKey = try extendedKey.deriveChildPrivateKey(at: index, computeParentFingerprint: true)
        }

        return extendedKey
    }

    func deriveChildFast(at indices: [UInt32]) throws -> OpalBase.PrivateKey.ExtendedModel {
        var extendedKey = self
        let startingDepth = Int(depth)

        guard indices.count >= startingDepth else {
            throw OpalBase.PrivateKey.Error.derivationPathTooShort
        }

        for index in indices.dropFirst(startingDepth) {
            extendedKey = try extendedKey.deriveChildPrivateKey(at: index, computeParentFingerprint: false)
        }

        return extendedKey
    }
}
