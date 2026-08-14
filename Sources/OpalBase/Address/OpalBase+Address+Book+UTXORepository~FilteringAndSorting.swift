// OpalBase+Address+Book+UTXORepository~FilteringAndSorting.swift

import Foundation

extension _OpalBase.Address.Book.UTXORepository {
    func listUTXOs() -> Set<OpalBase.Transaction.Output.Unspent> {
        allUTXOs
    }
    
    func listSpendableUTXOs() -> [OpalBase.Transaction.Output.Unspent] {
        spendableUTXOs.sorted { $0.compareOrder(before: $1) }
    }
    
    func listUTXOs(for address: OpalBase.Address) -> [OpalBase.Transaction.Output.Unspent] {
        let lockingScript = address.lockingScript.data
        guard let utxos = utxosByLockingScript[lockingScript] else {
            return .init()
        }
        return utxos.sorted { $0.compareOrder(before: $1) }
    }
    
    func sortUTXOs(by areInIncreasingOrder: (OpalBase.Transaction.Output.Unspent, OpalBase.Transaction.Output.Unspent) -> Bool) -> [OpalBase.Transaction.Output.Unspent] {
        allUTXOs.sorted(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: (OpalBase.Transaction.Output.Unspent, OpalBase.Transaction.Output.Unspent) -> Bool) -> [OpalBase.Transaction.Output.Unspent] {
        spendableUTXOs.sorted(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: (OpalBase.Transaction.Output.Unspent, OpalBase.Transaction.Output.Unspent) -> Bool,
                            tokenSelectionPolicy: OpalBase.Address.Book.CoinSelection.TokenSelectionPolicy) -> [OpalBase.Transaction.Output.Unspent] {
        let filteredSpendable = filterUTXOs(spendableUTXOs, tokenSelectionPolicy: tokenSelectionPolicy)
        return filteredSpendable.sorted(by: areInIncreasingOrder)
    }
    
    var allUTXOs: Set<OpalBase.Transaction.Output.Unspent> {
        Set(utxosByOutpoint.values)
    }
    
    var spendableUTXOs: Set<OpalBase.Transaction.Output.Unspent> {
        var spendable = allUTXOs
        spendable.subtract(reservedUTXOs)
        let quarantinedOutpoints = allMosaicQuarantinedOutpoints
        return Set(spendable.filter {
            !quarantinedOutpoints.contains(Outpoint($0))
        })
    }

    var allMosaicQuarantinedOutpoints: Set<Outpoint> {
        mosaicQuarantinedOutpointsByOwnerIdentifier.values.reduce(
            into: Set<Outpoint>()
        ) { result, quarantinedOutpointsByGeneration in
            for quarantinedOutpoints
                    in quarantinedOutpointsByGeneration.values {
                result.formUnion(quarantinedOutpoints)
            }
        }
    }
    
    func filterUTXOs(_ utxos: Set<OpalBase.Transaction.Output.Unspent>,
                     tokenSelectionPolicy: OpalBase.Address.Book.CoinSelection.TokenSelectionPolicy) -> Set<OpalBase.Transaction.Output.Unspent> {
        switch tokenSelectionPolicy {
        case .excludeTokenUTXOs:
            return Set(utxos.filter { $0.tokenData == nil })
        case .allowTokenUTXOs:
            return utxos
        }
    }
}
