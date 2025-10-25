// Network+Wallet+SubscriptionHub~Telemetry.swift

import Foundation

extension Network.Wallet.SubscriptionHub {
    func persistInactiveState(address: Address, lastStatus: String?) async {
        guard dependencies.hasPersistenceDeactivator else { return }
        do {
            try await dependencies.deactivate(address: address, lastStatus: lastStatus)
        } catch {
            Task { [telemetry] in
                await telemetry.record(
                    name: "network.wallet.subscription.persistence_failure",
                    category: .storage,
                    message: "Failed to deactivate subscription",
                    metadata: [
                        "subscription.address": .string(address.string)
                    ],
                    metrics: [:],
                    sensitiveKeys: ["subscription.address"]
                )
            }
        }
    }
    
    func recordTelemetry(for address: Address,
                         batch: Notification,
                         reason: String,
                         awaitedOperations: Int) async {
        guard !batch.events.isEmpty else { return }
        let latency = batch.latencyDuration
        let count = Double(batch.events.count)
        let throughput = count / max(calculateSeconds(from: latency), 0.001)
        let ratio = count == 0 ? 0 : Double(awaitedOperations) / count
        
        let metadata: Telemetry.Metadata = [
            "subscription.address": .string(address.string),
            "subscription.flush_reason": .string(reason)
        ]
        
        let slo = configuration.serviceLevelObjective
        let metrics: [String: Double] = [
            "subscription.batch.count": count,
            "subscription.batch.latency_ms": calculateMilliseconds(from: latency),
            "subscription.batch.throughput": throughput,
            "subscription.await_ratio": ratio,
            "subscription.await_ratio.target": 1.5,
            "subscription.slo.target_latency_ms": calculateMilliseconds(from: slo.targetFanOutLatency),
            "subscription.slo.max_latency_ms": calculateMilliseconds(from: slo.maxFanOutLatency),
            "subscription.slo.min_throughput_per_s": slo.minimumThroughputPerSecond
        ]
        
        Task { [telemetry] in
            await telemetry.record(
                name: "network.wallet.subscription.fanout",
                category: .network,
                message: "Flushed subscription batch",
                metadata: metadata,
                metrics: metrics,
                sensitiveKeys: ["subscription.address"]
            )
        }
    }
    
    func calculateSeconds(from duration: Duration) -> Double {
        let components = duration.components
        let attosecondsPerSecond = 1_000_000_000_000_000_000.0
        return Double(components.seconds) + Double(components.attoseconds) / attosecondsPerSecond
    }
    
    func calculateMilliseconds(from duration: Duration) -> Double {
        calculateSeconds(from: duration) * 1_000
    }
}
