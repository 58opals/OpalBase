// OpalBase+Address+Book+KeyOrigin.swift

import OpalCrypto

extension _OpalBase.Address.Book {
    enum KeyOrigin {
        case rootPrivate(OpalCrypto.Key.ExtendedPrivate)
        case accountPublic(OpalCrypto.Key.ExtendedPublic)
    }
}
