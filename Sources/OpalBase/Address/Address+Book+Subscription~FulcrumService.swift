// Address+Book+Subscription~FulcrumService.swift

import Foundation

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
        
        private var service: Network.FulcrumService?
        
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
    func start(service: Network.FulcrumService) async {
        guard !isRunning else { return }
        isRunning = true
        
        self.service = service
        
        let initialAddresses = await (book.receivingEntries + book.changeEntries).map(\.address)
        let consumerID = UUID()
        
        do {
            let handle = try await hub.makeStream(for: initialAddresses,
                                                  using: service,
                                                  consumerID: consumerID)
            self.consumerID = handle.id
            subscriptionCount = initialAddresses.count
            
            streamTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await _ in handle.eventStream {
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
                                               using: service)
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
        service = nil
        isRunning = false
    }
    
    private func incrementSubscriptionCount() {
        subscriptionCount += 1
    }
    
    private func processNotification() async {
        guard let service else { return }
        await triggerDebouncedNotification(using: service)
    }
    
    private func scheduleNotification(service: Network.FulcrumService) async {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceDuration)
            await self.handleNotification(service: service)
            await self.clearDebounce()
        }
    }
    
    private func clearDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }
    
    func triggerDebouncedNotification(using service: Network.FulcrumService) async {
        await scheduleNotification(service: service)
    }
    
    func handleNotification(service: Network.FulcrumService) async {
        do {
            try await book.refreshUTXOSet(service: service)
            try await book.refreshBalances(using: service)
            try await book.updateAddressUsageStatus(using: service)
            if let hook = notificationHook { await hook() }
        } catch {
            // Ignore update errors
        }
    }
}

extension Address.Book.Subscription: Sendable {}

extension Address.Book {
    var currentSubscription: Subscription? { self.subscription }
    
    func startSubscription(using service: Network.FulcrumService,
                           hub: Network.Wallet.SubscriptionHub,
                           notificationHook: (@Sendable () async -> Void)? = nil) async {
        if self.subscription != nil { return }
        let newSubscription = Subscription(book: self, hub: hub, notificationHook: notificationHook)
        self.subscription = newSubscription
        await newSubscription.start(service: service)
    }
    
    func stopSubscription() async {
        if let subscription = subscription {
            await subscription.stop()
            self.subscription = nil
        }
    }
}
