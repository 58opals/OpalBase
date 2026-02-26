// NetworkModel+AddressReadable.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    public typealias AddressReadable = AddressQueryClient & AddressSubscriptionClient
    public typealias TokenFilter = SwiftFulcrum.FulcrumMethodRequest.BlockchainModel.CashTokensModel.TokenFilterModel
}
