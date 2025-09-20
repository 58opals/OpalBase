// Address+Book+Subscription~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Address.Book {
    actor Subscription {
        private let book: Address.Book
        private let hub: Network.Wallet.SubscriptionHub
        private let notificationHook: (@Sendable () async -> Void)?
        private var isRunning: Bool = false
        private var streamTask: Task<Void, Never>?
        private var newEntriesTask: Task<Void, Never>?
        private var debounceTask: Task<Void, Never>?
        private let debounceDuration: UInt64 = 100_000_000 // 100ms
        private var consumerID: UUID?
        private var subscriptionCount: Int = 0
        
        private var fulcrum: Fulcrum?
        
        var activeSubscriptionCount: Int { subscriptionCount }
        
        init(book: Address.Book,
             hub: Network.Wallet.SubscriptionHub,
             notificationHook: (@Sendable () async -> Void)? = nil) {
            self.book = book
            self.hub = hub
            self.notificationHook = notificationHook
        }
    }
}

extension Address.Book.Subscription {
    func start(fulcrum: Fulcrum) async {
        guard !isRunning else { return }
        isRunning = true
        
        self.fulcrum = fulcrum
        
        let initialAddresses = await (book.receivingEntries + book.changeEntries).map(\.address)
        let consumerID = UUID()
        
        do {
            let handle = try await hub.makeStream(for: initialAddresses,
                                                  using: fulcrum,
                                                  consumerID: consumerID)
            self.consumerID = handle.id
            subscriptionCount = initialAddresses.count
            
            streamTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await _ in handle.notifications {
                        guard await self.isRunning else { break }
                        await self.processNotification()
                    }
                } catch {
                    await resetState(cancelStream: false)
                }
            }
            
            newEntriesTask = Task { [weak self] in
                guard let self else { return }
                for await entry in await self.book.observeNewEntries() {
                    guard await self.isRunning else { break }
                    do {
                        try await self.hub.add(addresses: [entry.address],
                                               for: consumerID,
                                               using: fulcrum)
                        await self.incrementSubscriptionCount()
                    } catch {
                        await resetState(cancelStream: false)
                        break
                    }
                }
            }
        } catch {
            await resetState(cancelStream: false)
        }
    }
    
    func stop() async {
        await resetState(cancelStream: true)
    }
}

extension Address.Book.Subscription {
    private func resetState(cancelStream: Bool) async {
        debounceTask?.cancel()
        debounceTask = nil
        if cancelStream { streamTask?.cancel() }
        streamTask = nil
        newEntriesTask?.cancel()
        newEntriesTask = nil
        if let consumerID { await hub.remove(consumerID: consumerID) }
        consumerID = nil
        subscriptionCount = 0
        fulcrum = nil
        isRunning = false
    }
    
    private func incrementSubscriptionCount() {
        subscriptionCount += 1
    }
    
    private func processNotification() async {
        guard let fulcrum else { return }
        await triggerDebouncedNotification(for: fulcrum)
    }
    
    private func scheduleNotification(fulcrum: Fulcrum) async {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceDuration)
            await self.handleNotification(fulcrum: fulcrum)
            await self.clearDebounce()
        }
    }
    
    private func clearDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }
    
    func triggerDebouncedNotification(for fulcrum: Fulcrum) async {
        await scheduleNotification(fulcrum: fulcrum)
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
    
    func startSubscription(using fulcrum: Fulcrum,
                           hub: Network.Wallet.SubscriptionHub,
                           notificationHook: (@Sendable () async -> Void)? = nil) async {
        if self.subscription != nil { return }
        let newSubscription = Subscription(book: self, hub: hub, notificationHook: notificationHook)
        self.subscription = newSubscription
        await newSubscription.start(fulcrum: fulcrum)
    }
    
    func stopSubscription() async {
        if let subscription = subscription {
            await subscription.stop()
            self.subscription = nil
        }
    }
}
