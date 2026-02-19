// Network+AddressReadable.swift

import Foundation
import SwiftFulcrum

extension Network {
    public typealias AddressReadable = AddressQueryClient & AddressSubscriptionClient
    public typealias TokenFilter = SwiftFulcrum.FulcrumMethodRequest.BlockchainModel.CashTokensModel.TokenFilterModel
}
