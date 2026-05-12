// OpalBase.CashTokens.BCMR.Client+LatestSnapshotSelection.swift

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
        let date: Date?
        let migratedDate: Date?
    }
    
    func makeSnapshotTimeline(
        from snapshots: [String: IdentitySnapshot]
    ) -> [SnapshotSelection] {
        snapshots.map { snapshotKey, snapshot in
            SnapshotSelection(
                key: snapshotKey,
                snapshot: snapshot,
                date: parseSnapshotDate(from: snapshotKey),
                migratedDate: snapshot.migrated.flatMap(parseSnapshotDate(from:))
            )
        }
        .sorted { left, right in
            switch (left.date, right.date) {
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
        let datedSnapshots = timeline.compactMap { selection -> (selection: SnapshotSelection, effectiveDate: Date)? in
            guard let effectiveDate = effectiveDate(for: selection) else { return nil }
            return (selection, effectiveDate)
        }
        .sorted {
            if $0.effectiveDate == $1.effectiveDate {
                return $0.selection.key < $1.selection.key
            }
            return $0.effectiveDate < $1.effectiveDate
        }

        if let latestReached = datedSnapshots.last(where: { $0.effectiveDate <= asOf }) {
            return latestReached.selection
        }

        if let oldestFuture = datedSnapshots.first(where: { $0.effectiveDate > asOf }) {
            return oldestFuture.selection
        }

        return timeline.last
    }

    func effectiveDate(for selection: SnapshotSelection) -> Date? {
        switch (selection.date, selection.migratedDate) {
        case (.some(let date), .some(let migratedDate)):
            return max(date, migratedDate)
        case (.some(let date), .none):
            return date
        case (.none, .some(let migratedDate)):
            return migratedDate
        case (.none, .none):
            return nil
        }
    }

    func selectHistoricalSnapshots(
        from timeline: [SnapshotSelection],
        before currentSnapshot: SnapshotSelection
    ) -> [SnapshotSelection] {
        guard let currentDate = effectiveDate(for: currentSnapshot) else { return .init() }
        return timeline.filter { selection in
            guard let date = effectiveDate(for: selection) else { return false }
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

        let iconURL = makeURL(from: selection.snapshot.uris?["icon"])
        let webURL = makeURL(from: selection.snapshot.uris?["web"])
        let registryURL = makeURL(from: selection.snapshot.uris?["registry"])
        let authbase = parseAuthbase(from: identity)
        let lastUpdated = selection.date ?? Date.distantPast

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

    func makeURL(from value: String?) -> URL? {
        guard let value,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["https", "ipfs"].contains(scheme)
        else { return nil }
        return url
    }

    func parseAuthbase(from identity: String) -> OpalBase.Transaction.Hash? {
        guard let data = try? Data(hexadecimalString: identity),
              data.count == OpalBase.Transaction.Hash.expectedByteCount
        else { return nil }

        return OpalBase.Transaction.Hash(dataFromRPC: data)
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
