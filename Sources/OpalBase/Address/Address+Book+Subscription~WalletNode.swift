// Address+Book+Subscription~WalletNode.swift

import Foundation

extension Address.Book {
    actor Subscription {
        private let book: Address.Book
        private let hub: any Network.Wallet.SubscriptionService
        private let notificationHook: (@Sendable () async -> Void)?
        private var isRunning: Bool = false
        private var streamTask: Task<Void, Never>?
        private var newEntriesTask: Task<Void, Never>?
        private var debounceTask: Task<Void, Never>?
        private let debounceDuration: UInt64 = 100_000_000 // 100ms
        private var consumerID: UUID?
        private var subscriptionCount: Int = 0
        
        private var node: (any Network.Wallet.Node)?
        
        var activeSubscriptionCount: Int { subscriptionCount }
        
        init(book: Address.Book,
             hub: any Network.Wallet.SubscriptionService,
             notificationHook: (@Sendable () async -> Void)? = nil) {
            self.book = book
            self.hub = hub
            self.notificationHook = notificationHook
        }
    }
}

extension Address.Book.Subscription {
    func start(node: any Network.Wallet.Node) async {
        guard !isRunning else { return }
        isRunning = true
        
        self.node = node
        
        let initialAddresses = await (book.receivingEntries + book.changeEntries).map(\.address)
        let consumerID = UUID()
        
        do {
            let handle = try await hub.makeStream(for: initialAddresses,
                                                  using: node,
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
                                               using: node)
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
        node = nil
        isRunning = false
    }
    
    private func incrementSubscriptionCount() {
        subscriptionCount += 1
    }
    
    private func processNotification() async {
        guard let node else { return }
        await triggerDebouncedNotification(using: node)
    }
    
    private func scheduleNotification(node: any Network.Wallet.Node) async {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceDuration)
            await self.handleNotification(node: node)
            await self.clearDebounce()
        }
    }
    
    private func clearDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }
    
    func triggerDebouncedNotification(using node: any Network.Wallet.Node) async {
            await scheduleNotification(node: node)
        }
    
    func handleNotification(node: any Network.Wallet.Node) async {
        do {
            try await book.refreshUTXOSet(node: node)
            try await book.refreshBalances(using: node)
            try await book.updateAddressUsageStatus(using: node)
            if let hook = notificationHook { await hook() }
        } catch {
            // Ignore update errors
        }
    }
}

extension Address.Book.Subscription: Sendable {}

extension Address.Book {
    var currentSubscription: Subscription? { self.subscription }
    
    func startSubscription(using node: any Network.Wallet.Node,
                           hub: any Network.Wallet.SubscriptionService,
                           notificationHook: (@Sendable () async -> Void)? = nil) async {
        if self.subscription != nil { return }
        let newSubscription = Subscription(book: self, hub: hub, notificationHook: notificationHook)
        self.subscription = newSubscription
        await newSubscription.start(node: node)
    }
    
    func stopSubscription() async {
        if let subscription = subscription {
            await subscription.stop()
            self.subscription = nil
        }
    }
}
