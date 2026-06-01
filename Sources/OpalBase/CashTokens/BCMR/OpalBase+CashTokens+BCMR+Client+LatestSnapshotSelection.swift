// OpalBase+CashTokens+BCMR+Client+LatestSnapshotSelection.swift

import Foundation

extension OpalBase.CashTokens.BCMR.Client {
    public func extractTokenMetadata(from registry: Registry) -> [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] {
        extractTokenMetadata(from: registry, source: .embedded)
    }
    
    public func extractTokenMetadata(
        from registry: Registry,
        source: OpalBase.CashTokens.Metadata.Source = .embedded,
        asOf: Date = Date(),
        includeHistoricalCategories: Bool = true
    ) -> [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] {
        guard let identities = registry.identities else { return .init() }
        
        var metadataByCategory: [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] = .init()
        
        for (identity, snapshots) in identities.sorted(by: { $0.key < $1.key }) {
            let timeline = makeSnapshotTimeline(from: snapshots)
            guard let currentSnapshot = selectCurrentSnapshot(from: timeline, asOf: asOf),
                  let currentMetadata = makeTokenMetadata(
                    identity: identity,
                    selection: currentSnapshot,
                    source: source
                  )
            else { continue }

            upsertCurrentMetadata(currentMetadata, into: &metadataByCategory)

            guard includeHistoricalCategories else { continue }
            for historicalSnapshot in selectHistoricalSnapshots(from: timeline, before: currentSnapshot) {
                guard let historicalMetadata = makeTokenMetadata(
                    identity: identity,
                    selection: historicalSnapshot,
                    source: source
                ),
                      historicalMetadata.category != currentMetadata.category
                else { continue }

                metadataByCategory[historicalMetadata.category] = metadataByCategory[historicalMetadata.category] ?? historicalMetadata
            }
        }
        
        return metadataByCategory
    }
}

private extension OpalBase.CashTokens.BCMR.Client {
    struct SnapshotSelection {
        let key: String
        let snapshot: IdentitySnapshot
        let effectiveDate: Date?
    }
    
    func makeSnapshotTimeline(
        from snapshots: [String: IdentitySnapshot]
    ) -> [SnapshotSelection] {
        snapshots.map { snapshotKey, snapshot in
            let snapshotDate = parseSnapshotDate(from: snapshotKey)
            let migratedDate = snapshot.migrated.flatMap(parseSnapshotDate(from:))
            return SnapshotSelection(
                key: snapshotKey,
                snapshot: snapshot,
                effectiveDate: makeEffectiveDate(snapshotDate: snapshotDate, migratedDate: migratedDate)
            )
        }
        .sorted { left, right in
            switch (left.effectiveDate, right.effectiveDate) {
            case (.some(let leftDate), .some(let rightDate)):
                if leftDate == rightDate {
                    return left.key < right.key
                }
                return leftDate < rightDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left.key < right.key
            }
        }
    }
    
    func selectCurrentSnapshot(
        from timeline: [SnapshotSelection],
        asOf: Date
    ) -> SnapshotSelection? {
        if let latestReached = timeline.last(where: { selection in
            guard let effectiveDate = selection.effectiveDate else { return false }
            return effectiveDate <= asOf
        }) {
            return latestReached
        }

        if let oldestFuture = timeline.first(where: { selection in
            guard let effectiveDate = selection.effectiveDate else { return false }
            return effectiveDate > asOf
        }) {
            return oldestFuture
        }

        return timeline.last
    }

    func makeEffectiveDate(snapshotDate: Date?, migratedDate: Date?) -> Date? {
        switch (snapshotDate, migratedDate) {
        case (.some(let date), .some(let migratedDate)):
            return max(date, migratedDate)
        case (.some(let date), .none), (.none, .some(let date)):
            return date
        case (.none, .none):
            return nil
        }
    }

    func selectHistoricalSnapshots(
        from timeline: [SnapshotSelection],
        before currentSnapshot: SnapshotSelection
    ) -> [SnapshotSelection] {
        guard let currentDate = currentSnapshot.effectiveDate else { return .init() }
        return timeline.filter { selection in
            guard let date = selection.effectiveDate else { return false }
            return date < currentDate
        }
    }

    func makeTokenMetadata(
        identity: String,
        selection: SnapshotSelection,
        source: OpalBase.CashTokens.Metadata.Source
    ) -> OpalBase.CashTokens.Metadata? {
        guard let tokenSnapshot = selection.snapshot.token,
              let categoryHexadecimal = tokenSnapshot.category,
              let categoryIdentifier = try? OpalBase.CashTokens.CategoryID(hexFromRPC: categoryHexadecimal)
        else { return nil }

        let iconURL = makeMetadataURL(from: selection.snapshot.uris?["icon"])
        let webURL = makeMetadataURL(from: selection.snapshot.uris?["web"])
        let registryURL = makeMetadataURL(from: selection.snapshot.uris?["registry"])
        let authbase = parseAuthbase(from: identity)
        let lastUpdated = selection.effectiveDate ?? Date.distantPast

        return OpalBase.CashTokens.Metadata(
            category: categoryIdentifier,
            name: selection.snapshot.name,
            symbol: tokenSnapshot.symbol,
            decimals: tokenSnapshot.decimals,
            iconURL: iconURL,
            lastUpdated: lastUpdated,
            source: source,
            description: selection.snapshot.description,
            webURL: webURL,
            identity: identity,
            authbase: authbase,
            registryURL: registryURL
        )
    }

    func makeMetadataURL(from value: String?) -> URL? {
        guard let value else { return nil }
        return OpalBase.CashTokens.Metadata.makeSafeMetadataURL(URL(string: value))
    }

    func parseAuthbase(from identity: String) -> OpalBase.Transaction.Hash? {
        try? OpalBase.Network.decodeTransactionHash(from: identity, label: "metadata identity")
    }

    func upsertCurrentMetadata(
        _ metadata: OpalBase.CashTokens.Metadata,
        into metadataByCategory: inout [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata]
    ) {
        guard let current = metadataByCategory[metadata.category],
              current.lastUpdated > metadata.lastUpdated
        else {
            metadataByCategory[metadata.category] = metadata
            return
        }
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
