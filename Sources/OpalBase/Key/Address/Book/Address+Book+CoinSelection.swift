// Address+Book+CoinSelection.swift

import Foundation

extension Address.Book {
    enum CoinSelection: Sendable {
        case greedyLargestFirst
        case branchAndBound
        case sweepAll
    }
}
