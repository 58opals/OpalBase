// Address+Book+Subscription~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Address.Book {
    actor Subscription {
        private let book: Address.Book
        private var isRunning: Bool = false
        private var cancelHandlers: [@Sendable () async -> Void] = .init()
        private var task: Task<Void, Never>?
        private var subscriptionTasks: [Task<Void, Never>] = .init()
        private var newEntriesTask: Task<Void, Never>?
        private var debounceTask: Task<Void, Never>?
        private let debounceDuration: UInt64 = 100_000_000 // 100ms
        private var subscriptionCount: Int = 0
        private let notificationHook: (@Sendable () async -> Void)?
        
        var activeSubscriptionCount: Int { subscriptionCount }
        
        init(book: Address.Book, notificationHook: (@Sendable () async -> Void)? = nil) {
            self.book = book
            self.notificationHook = notificationHook
        }
    }
}

extension Address.Book.Subscription {
    func start(fulcrum: Fulcrum) async {
        guard !isRunning else { return }
        isRunning = true
        
        setNewEntriesTask(
            Task { [weak self] in
                guard let self else { return }
                for await entry in await book.observeNewEntries() {
                    guard await self.isRunning else { break }
                    let task = await self.startSubscription(for: entry, fulcrum: fulcrum)
                    
                    await self.storeSubscriptionTask(task)
                }
            }
        )
        
        task = Task { [weak self] in
            guard let self else { return }
            let entries = await self.book.receivingEntries + self.book.changeEntries
            for entry in entries {
                let task = await self.startSubscription(for: entry, fulcrum: fulcrum)
                await self.storeSubscriptionTask(task)
            }
        }
    }
    
    func stop() async {
        isRunning = false
        for cancel in cancelHandlers { await cancel() }
        cancelHandlers.removeAll()
        task?.cancel()
        task = nil
        for task in subscriptionTasks { task.cancel() }
        subscriptionTasks.removeAll()
        subscriptionCount = 0
        newEntriesTask?.cancel()
        newEntriesTask = nil
        debounceTask?.cancel()
        debounceTask = nil
    }
}

extension Address.Book.Subscription {
    private func storeCancel(_ cancel: @escaping @Sendable () async -> Void) async {
        cancelHandlers.append(cancel)
    }
    
    private func setNewEntriesTask(_ task: Task<Void, Never>) {
        newEntriesTask = task
    }
    
    private func storeSubscriptionTask(_ task: Task<Void, Never>) async {
        subscriptionTasks.append(task)
    }
    
    private func startSubscription(for entry: Address.Book.Entry, fulcrum: Fulcrum) async -> Task<Void, Never> {
        subscriptionCount += 1
        
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let (_, _, stream, cancel) = try await entry.address.subscribe(fulcrum: fulcrum)
                await storeCancel(cancel)
                for try await _ in stream where await self.isRunning {
                    await self.handleNotification(fulcrum: fulcrum)
                }
            } catch {
                // Ignore individual subscription failures
            }
        }
        
        return task
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
    
    func startSubscription(using fulcrum: Fulcrum, notificationHook: (@Sendable () async -> Void)? = nil) async {
        if self.subscription != nil { return }
        let subscription = Subscription(book: self, notificationHook: notificationHook)
        self.subscription = subscription
        await subscription.start(fulcrum: fulcrum)
    }
    
    func stopSubscription() async {
        if let subscription = subscription {
            await subscription.stop()
            self.subscription = nil
        }
    }
}
