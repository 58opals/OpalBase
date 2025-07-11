// Address+Book+Subscription.swift

import Foundation
import SwiftFulcrum

extension Address.Book {
    public actor Subscription {
        private let book: Address.Book
        private var isRunning: Bool = false
        private var cancelClosures: [() async -> Void] = .init()
        private var task: Task<Void, Never>?
        private let notificationHook: (@Sendable () async -> Void)?
        
        init(book: Address.Book, notificationHook: (@Sendable () async -> Void)? = nil) {
            self.book = book
            self.notificationHook = notificationHook
        }
    }
}

extension Address.Book.Subscription {
    public func start(fulcrum: Fulcrum) async {
        guard !isRunning else { return }
        isRunning = true
        task = Task {
            await withTaskGroup { group in
                let entries = await book.receivingEntries + book.changeEntries
                for entry in entries {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        do {
                            let (_, _, _, stream, cancel) = try await entry.address.subscribe(fulcrum: fulcrum)
                            await storeCancel(cancel)
                            for try await _ in stream where await self.isRunning {
                                await self.handleNotification(fulcrum: fulcrum)
                            }
                        } catch {
                            // Ignore individual subscription failures
                        }
                    }
                }
            }
        }
    }
    
    public func stop() async {
        isRunning = false
        for cancel in cancelClosures { await cancel() }
        cancelClosures.removeAll()
        task?.cancel()
        task = nil
    }
}

extension Address.Book.Subscription {
    private func storeCancel(_ cancel: @escaping () async -> Void) async {
        cancelClosures.append(cancel)
    }

    func handleNotification(fulcrum: Fulcrum) async {
        do {
            try await book.refreshUTXOSet(fulcrum: fulcrum)
            try await book.refreshBalances(using: fulcrum)
            try await book.updateAddressUsageStatus(using: fulcrum)
            if let hook = notificationHook { await hook() }
        } catch {
            // Ignore update errors
        }
    }
}

extension Address.Book.Subscription: Sendable {}

extension Address.Book {
    var currentSubscription: Subscription? { self.subscription }
    
    public func startSubscription(using fulcrum: Fulcrum, notificationHook: (@Sendable () async -> Void)? = nil) async {
        let subscription = Subscription(book: self, notificationHook: notificationHook)
        self.subscription = subscription
        await subscription.start(fulcrum: fulcrum)
    }
    
    public func stopSubscription() async {
        if let subscription = subscription {
            await subscription.stop()
            self.subscription = nil
        }
    }
}
