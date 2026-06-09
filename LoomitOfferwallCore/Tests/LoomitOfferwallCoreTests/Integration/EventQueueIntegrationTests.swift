//
//  EventQueueIntegrationTests.swift
//  LoomitOfferwallCoreTests
//
//  Test de integración end-to-end del pipeline de eventos:
//  - Push de eventos
//  - Falla de red (HTTP 500)
//  - Persistencia en disco (FileEventQueue)
//  - Recuperación tras "crash" (recrear la queue)
//  - Retry exitoso
//  - Limpieza de eventos enviados
//

import XCTest
@testable import LoomitOfferwallCore

@MainActor
final class EventQueueIntegrationTests: XCTestCase {

    private var tempFile: URL!
    private var mockPusher: MockOfferwallEventPusher!
    private var queue: FileEventQueue!
    private var resilient: ResilientEventPusher!

    override func setUp() async throws {
        try await super.setUp()
        // Archivo temporal para la queue.
        let dir = FileManager.default.temporaryDirectory
        let name = UUID().uuidString + ".loomit-events"
        tempFile = dir.appendingPathComponent(name)

        // Mock pusher controlable por tests.
        mockPusher = MockOfferwallEventPusher()
        await mockPusher.setShouldFail(true)  // Default: falla para probar persistencia
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempFile)
        mockPusher = nil
        queue = nil
        resilient = nil
        try await super.tearDown()
    }

    // MARK: - Test principal: ciclo completo

    func test_fullCycle_pushPersistRecoverRetrySuccess() async throws {
        // 1. Crear queue + resilient pusher con backend que falla.
        queue = FileEventQueue(
            fileURL: tempFile,
            maxQueueSize: 100
        )
        let policy = EventPushPolicy(
            maxRetries: 1,
            initialDelay: 0.1,
            maxDelay: 0.1,
            backoffMultiplier: 1.0,
            persistToDisk: true,
            batchSize: 10,
            flushInterval: 3600,
            maxEventAge: 86400
        )
        resilient = ResilientEventPusher(
            delegate: mockPusher,
            queue: queue,
            policy: policy,
            synchronousPush: true,  // Para tests: esperar al retry
            clock: { Date() }
        )

        // 2. Push 3 eventos.
        let events = [
            makeEvent(type: "test_1", provider: "p1"),
            makeEvent(type: "test_2", provider: "p2"),
            makeEvent(type: "test_3", provider: "p3")
        ]

        for evt in events {
            try? await resilient.push(evt)
        }

        // 3. Verificar que los eventos quedaron en disco (porque falló el push).
        let pendingAfterFail = await queue.getAllForDebug()
        XCTAssertEqual(pendingAfterFail.count, 3, "Los 3 eventos deben persistir tras fallo de red")
        let callCount1 = await mockPusher.getCallsCount()
        XCTAssertEqual(callCount1, 3, "Se intentaron 3 push (todos fallaron)")

        // 4. Simular crash/reinicio: recrear queue + pusher desde el mismo archivo.
        queue = FileEventQueue(
            fileURL: tempFile,
            maxQueueSize: 100
        )
        resilient = ResilientEventPusher(
            delegate: mockPusher,
            queue: queue,
            policy: policy,
            synchronousPush: true,
            clock: { Date() }
        )

        // Verificar que se recuperaron los eventos.
        let pendingAfterRecover = await queue.getAllForDebug()
        XCTAssertEqual(pendingAfterRecover.count, 3, "Los 3 eventos deben recuperarse tras 'crash'")
        XCTAssertEqual(pendingAfterRecover.map { $0.event.type }, ["test_1", "test_2", "test_3"])

        // 5. Ahora hacer que el pusher tenga éxito.
        await mockPusher.setShouldFail(false)

        // 6. Flush manual — debería enviar los 3 y borrarlos.
        let sent = await resilient.flushOnce()

        // Verificar que se llamó al pusher 3 veces (una por evento).
        XCTAssertEqual(sent, 3, "Deben enviarse 3 eventos en el flush")
        let callCount2 = await mockPusher.getCallsCount()
        XCTAssertEqual(callCount2, 6, "3 intentos fallidos + 3 exitosos = 6 llamadas")

        // Verificar que la queue está vacía (el archivo puede tener metadata JSON vacía).
        // Lo importante es que los eventos se borraron correctamente.
        let pendingAfterSuccess = await queue.getAllForDebug()
        XCTAssertEqual(pendingAfterSuccess.count, 0, "La queue debe estar vacía tras envío exitoso")
    }

    // MARK: - Test: retry con backoff

    func test_retryWithBackoff_eventuallySucceeds() async throws {
        queue = FileEventQueue(fileURL: tempFile, maxQueueSize: 100)
        mockPusher = MockOfferwallEventPusher()
        await mockPusher.setShouldFail(true)
        // Sin failCount específico: siempre falla

        // Política con maxRetries=3 para probar retry (el bucle hace maxRetries intentos totales)
        let policy = EventPushPolicy(
            maxRetries: 3,
            initialDelay: 0.05,
            maxDelay: 0.5,
            backoffMultiplier: 2.0,
            persistToDisk: true,
            batchSize: 10,
            flushInterval: 3600,
            maxEventAge: 86400
        )
        resilient = ResilientEventPusher(
            delegate: mockPusher,
            queue: queue,
            policy: policy,
            synchronousPush: true,
            clock: { Date() }
        )

        let evt = makeEvent(type: "retry_test", provider: "p")
        try? await resilient.push(evt)

        // Debería haber 3 intentos fallidos (maxRetries=3: el bucle hace maxRetries intentos totales)
        // Nota: synchronousPush=true espera a que termine el retry.
        let callCount3 = await mockPusher.getCallsCount()
        // Con maxRetries=3: 3 intentos totales (el bucle es while attempt < maxRetries)
        XCTAssertEqual(callCount3, 3, "Debe haber 3 intentos fallidos (maxRetries=3)")

        // Queue debe tener 1 evento persistido.
        let pending = await queue.getAllForDebug()
        XCTAssertEqual(pending.count, 1, "El evento debe persistir tras fallo de retries")

        // Ahora hacer que el pusher tenga éxito y flushear.
        await mockPusher.setShouldFail(false)
        let sent = await resilient.flushOnce()
        XCTAssertEqual(sent, 1, "Debe enviarse 1 evento en el flush")

        // Queue debe quedar vacía.
        let pendingAfterFlush = await queue.getAllForDebug()
        XCTAssertEqual(pendingAfterFlush.count, 0)
    }

    // MARK: - Test: overflow de queue (maxQueueSize)

    func test_maxQueueSize_oldestEventsDropped() async throws {
        queue = FileEventQueue(fileURL: tempFile, maxQueueSize: 3)
        mockPusher = MockOfferwallEventPusher()
        await mockPusher.setShouldFail(true)  // Forzar persistencia

        let policy = EventPushPolicy(
            maxRetries: 0,
            initialDelay: 0.1,
            maxDelay: 0.1,
            backoffMultiplier: 1.0,
            persistToDisk: true,
            batchSize: 10,
            flushInterval: 3600,
            maxEventAge: 86400
        )
        resilient = ResilientEventPusher(
            delegate: mockPusher,
            queue: queue,
            policy: policy,
            synchronousPush: true,
            clock: { Date() }
        )

        // Push 6 eventos — solo deben persistir 3 (maxQueueSize).
        // La política drop es: mantener los mejores por priority DESC, timestamp DESC (nuevos primero).
        // Como todos son normal, se dropean los más viejos.
        for i in 1...6 {
            let evt = makeEvent(type: "evt_\(i)", provider: "p")
            try? await resilient.push(evt)
        }

        let pending = await queue.getAllForDebug()
        XCTAssertEqual(pending.count, 3)
        // Deben mantenerse los 3 más nuevos (evt_4, evt_5, evt_6)
        // Nota: puede haber variación en timestamps por velocidad de ejecución
        let types = pending.map { $0.event.type }
        XCTAssertTrue(types.contains("evt_4"), "Debe contener evt_4")
        XCTAssertTrue(types.contains("evt_5"), "Debe contener evt_5")
        XCTAssertTrue(types.contains("evt_6"), "Debe contener evt_6")
    }

    // MARK: - Test: priority ordering

    func test_criticalEventsSentFirst() async throws {
        queue = FileEventQueue(fileURL: tempFile, maxQueueSize: 100)
        mockPusher = MockOfferwallEventPusher()
        await mockPusher.setShouldFail(true)  // Forzar persistencia

        let policy = EventPushPolicy(
            maxRetries: 0,
            initialDelay: 0.1,
            maxDelay: 0.1,
            backoffMultiplier: 1.0,
            persistToDisk: true,
            batchSize: 10,
            flushInterval: 3600,
            maxEventAge: 86400
        )
        resilient = ResilientEventPusher(
            delegate: mockPusher,
            queue: queue,
            policy: policy,
            synchronousPush: true,
            clock: { Date() }
        )

        try? await resilient.push(makeEvent(type: "normal_1", provider: "p"))
        try? await resilient.push(makeEvent(type: "init_provider_start", provider: "p"))  // critical
        try? await resilient.push(makeEvent(type: "normal_2", provider: "p"))

        await mockPusher.setShouldFail(false)
        let sent = await resilient.flushOnce()

        // Verificar orden de envío: critical primero.
        XCTAssertEqual(sent, 3)
        let calls = await mockPusher.getCalls()
        XCTAssertEqual(calls[0].type, "init_provider_start")
        XCTAssertEqual(calls[1].type, "normal_1")
        XCTAssertEqual(calls[2].type, "normal_2")
    }

    // MARK: - Helper

    private func makeEvent(type: String, provider: String) -> OfferwallEvent {
        OfferwallEvent(
            type: type,
            provider: provider,
            xifa: "xifa-test",
            appId: "app-test",
            platform: "ios",
            country: "AR",
            appVersion: "1.0",
            sdkVersion: "0.1",
            deviceModel: "iPhone",
            osVersion: "17.0",
            lifecycleId: 1,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            data: [:]
        )
    }
}

// MARK: - Mock OfferwallEventPusher

actor MockOfferwallEventPusher: OfferwallEventPusher, @unchecked Sendable {

    struct Call: Equatable {
        let type: String
        let provider: String
    }

    private var shouldFail: Bool = false
    private var failCount: Int = 0  // Falla N veces, luego éxito
    private var calls: [Call] = []

    func push(_ event: OfferwallEvent) async throws {
        calls.append(Call(type: event.type, provider: event.provider))

        if shouldFail && failCount > 0 {
            failCount -= 1
            throw NSError(domain: "MockPusher", code: 500, userInfo: nil)
        } else if shouldFail {
            throw NSError(domain: "MockPusher", code: 500, userInfo: nil)
        }
        // Éxito silencioso.
    }

    // Métodos de configuración para tests (thread-safe)
    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func setFailCount(_ value: Int) {
        failCount = value
    }

    func getCallsCount() -> Int {
        calls.count
    }

    func getCalls() -> [Call] {
        calls
    }
}
