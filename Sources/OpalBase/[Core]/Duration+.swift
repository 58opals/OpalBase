// Duration+.swift

import Foundation

extension Duration {
    var secondsDouble: Double {
        let breakdown = components
        let seconds = Double(breakdown.seconds)
        let attoseconds = Double(breakdown.attoseconds) / 1_000_000_000_000_000_000
        return seconds + attoseconds
    }
}
