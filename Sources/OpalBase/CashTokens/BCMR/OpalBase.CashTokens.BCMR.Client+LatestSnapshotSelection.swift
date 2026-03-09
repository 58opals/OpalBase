// OpalBase.CashTokens.BCMR.Client+LatestSnapshotSelection.swift

import Foundation

extension OpalBase.CashTokens.BCMR.Client {
    public func extractTokenMetadata(from registry: Registry) -> [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] {
        extractTokenMetadata(from: registry, source: .embedded)
    }
    
    public func extractTokenMetadata(
        from registry: Registry,
        source: OpalBase.CashTokens.Metadata.Source
    ) -> [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] {
        guard let identities = registry.identities else { return .init() }
        
        var metadataByCategory: [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] = .init()
        
        for snapshots in identities.values {
            guard let latestSnapshot = selectLatestSnapshot(from: snapshots) else { continue }
            guard let tokenSnapshot = latestSnapshot.snapshot.token,
                  let categoryHexadecimal = tokenSnapshot.category else { continue }
            
            let categoryIdentifier: OpalBase.CashTokens.CategoryID
            do {
                categoryIdentifier = try OpalBase.CashTokens.CategoryID(hexFromRPC: categoryHexadecimal)
            } catch {
                continue
            }
            
            let iconURL = latestSnapshot.snapshot.uris.flatMap { $0["icon"] }.flatMap(URL.init(string:))
            let lastUpdated = latestSnapshot.date ?? Date.distantPast
            
            let tokenMetadata = OpalBase.CashTokens.Metadata(
                category: categoryIdentifier,
                name: latestSnapshot.snapshot.name,
                symbol: tokenSnapshot.symbol,
                decimals: tokenSnapshot.decimals,
                iconURL: iconURL,
                lastUpdated: lastUpdated,
                source: source
            )
            
            metadataByCategory[categoryIdentifier] = tokenMetadata
        }
        
        return metadataByCategory
    }
}

private extension OpalBase.CashTokens.BCMR.Client {
    struct LatestSnapshotSelection {
        let key: String
        let snapshot: IdentitySnapshot
        let date: Date?
    }
    
    func selectLatestSnapshot(
        from snapshots: [String: IdentitySnapshot]
    ) -> LatestSnapshotSelection? {
        var latestSelection: LatestSnapshotSelection?
        
        for (snapshotKey, snapshot) in snapshots {
            let snapshotDate = parseSnapshotDate(from: snapshotKey)
            let candidate = LatestSnapshotSelection(key: snapshotKey, snapshot: snapshot, date: snapshotDate)
            guard let currentSelection = latestSelection else {
                latestSelection = candidate
                continue
            }
            
            if compareSnapshotKeys(candidate.key, laterThan: currentSelection.key) {
                latestSelection = candidate
            }
        }
        
        return latestSelection
    }
    
    func compareSnapshotKeys(_ left: String, laterThan right: String) -> Bool {
        if let leftDate = parseSnapshotDate(from: left),
           let rightDate = parseSnapshotDate(from: right) {
            return leftDate > rightDate
        }
        
        return left > right
    }
    
    func parseSnapshotDate(from snapshotKey: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: snapshotKey) {
            return date
        }
        
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: snapshotKey)
    }
}

