import Testing
@testable import OpalBase

@Suite("Telemetry", .tags(.unit, .telemetry))
struct TelemetryTests {
    @Test("disabled pipeline does not emit events")
    func testDisabledPipelineDoesNotEmitEvents() async {
        let recorder = RecordingTelemetryStore()
        let handler = Telemetry.Handler { event in
            await recorder.append(event)
        }
        let telemetry = Telemetry(isEnabled: false, handlers: [handler])
        
        await telemetry.record(name: "disabled", category: .diagnostics)
        
        let captured = await recorder.events
        #expect(captured.isEmpty)
    }
    
    @Test("recording redacts sensitive metadata")
    func testRedactSensitiveMetadata() async {
        let recorder = RecordingTelemetryStore()
        let handler = Telemetry.Handler { event in
            await recorder.append(event)
        }
        let telemetry = Telemetry(isEnabled: true, handlers: [handler])
        
        await telemetry.record(
            name: "wallet.event",
            category: .wallet,
            message: "Submitted 123456 transaction deadbeefcafefeed",
            metadata: [
                "transaction.id": .string("deadbeefcafefeed"),
                "status": .string("ok")
            ],
            sensitiveKeys: ["transaction.id"]
        )
        
        let captured = await recorder.events
        #expect(captured.count == 1)
        let event = captured[0]
        #expect(event.message?.contains("‹redacted›") == true)
        #expect(event.metadata["transaction.id"] == .redacted)
        #expect(event.metadata["status"] == .string("ok"))
    }
    
    @Test("metrics snapshot aggregates events")
    func testAggregateMetricsSnapshot() async {
        let telemetry = Telemetry(isEnabled: true, handlers: [Telemetry.Handler { _ in }])
        
        await telemetry.record(
            name: "latency",
            category: .network,
            metrics: ["latency.ms": 10]
        )
        await telemetry.record(
            name: "latency",
            category: .network,
            metrics: ["latency.ms": 30]
        )
        
        let snapshot = await telemetry.makeMetricsSnapshot()
        let counters = snapshot.eventCounters["network.latency"]
        #expect(counters?.total == 2)
        #expect(counters?.failures == 0)
        #expect(counters?.successRate == Double(1))
        
        let aggregate = snapshot.valueAggregates["latency.ms"]
        #expect(aggregate?.count == 2)
        #expect(aggregate?.sum == Double(40))
        #expect(aggregate?.minimum == Double(10))
        #expect(aggregate?.maximum == Double(30))
        #expect(aggregate?.average == Double(20))
    }
}

private actor RecordingTelemetryStore {
    private var capturedEvents: [Telemetry.Event] = .init()
    
    func append(_ event: Telemetry.Event) {
        capturedEvents.append(event)
    }
    
    var events: [Telemetry.Event] { capturedEvents }
}
