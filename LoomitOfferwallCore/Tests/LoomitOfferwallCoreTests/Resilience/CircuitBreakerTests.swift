//
//  CircuitBreakerTests.swift
//  LoomitOfferwallCoreTests
//

import XCTest
@testable import LoomitOfferwallCore

final class CircuitBreakerTests: XCTestCase {

    private struct DummyError: Error {}

    func test_initialState_isClosed() async {
        let cb = CircuitBreaker(name: "t")
        let state = await cb.getState()
        XCTAssertEqual(state, .closed)
    }

    func test_consecutiveFailures_openCircuit() async throws {
        let cb = CircuitBreaker(name: "t", config: CircuitBreakerConfig(failureThreshold: 3))
        for _ in 0..<3 {
            do {
                _ = try await cb.execute { throw DummyError() }
                XCTFail("expected throw")
            } catch is DummyError {
                // expected
            }
        }
        let state = await cb.getState()
        XCTAssertEqual(state, .open)
    }

    func test_openCircuit_rejectsImmediately() async throws {
        let cb = CircuitBreaker(name: "t", config: CircuitBreakerConfig(failureThreshold: 1, openDuration: 60))
        // Force OPEN
        do { _ = try await cb.execute { throw DummyError() } } catch {}
        let s1 = await cb.getState()
        XCTAssertEqual(s1, .open)

        // Now should reject without invoking operation
        let invoked = Locked(false)
        do {
            _ = try await cb.execute { () -> Int in invoked.set(true); return 42 }
            XCTFail("expected rejection")
        } catch is CircuitOpenError {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertFalse(invoked.get(), "operation must not run when circuit is OPEN")
    }

    func test_halfOpen_transition_afterOpenDuration() async throws {
        let clock = TestClock()
        let cb = CircuitBreaker(
            name: "t",
            config: CircuitBreakerConfig(failureThreshold: 1, successThreshold: 1, openDuration: 10),
            clock: { clock.now }
        )

        // Abrir circuito
        do { _ = try await cb.execute { throw DummyError() } } catch {}
        let opened = await cb.getState()
        XCTAssertEqual(opened, .open)

        // Avanzar 11s → debería permitir HALF_OPEN
        clock.advance(11)

        // Una operación exitosa lo cierra (successThreshold=1)
        let result: Int = try await cb.execute { 7 }
        XCTAssertEqual(result, 7)

        let closed = await cb.getState()
        XCTAssertEqual(closed, .closed)
    }

    func test_halfOpen_failure_reopens() async throws {
        let clock = TestClock()
        let cb = CircuitBreaker(
            name: "t",
            config: CircuitBreakerConfig(failureThreshold: 1, successThreshold: 2, openDuration: 5),
            clock: { clock.now }
        )
        do { _ = try await cb.execute { throw DummyError() } } catch {}
        clock.advance(6)

        // Primera ejecución en HALF_OPEN falla
        do {
            _ = try await cb.execute { throw DummyError() }
            XCTFail("expected throw")
        } catch is DummyError { }

        let reopened = await cb.getState()
        XCTAssertEqual(reopened, .open, "single failure in HALF_OPEN must reopen")
    }

    func test_reset_returnsToClosed() async throws {
        let cb = CircuitBreaker(name: "t", config: CircuitBreakerConfig(failureThreshold: 1))
        do { _ = try await cb.execute { throw DummyError() } } catch {}
        let opened = await cb.getState()
        XCTAssertEqual(opened, .open)
        await cb.reset()
        let closed = await cb.getState()
        XCTAssertEqual(closed, .closed)
    }
}

// MARK: - helpers

private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ initial: T) { self.value = initial }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: T) { lock.lock(); defer { lock.unlock() }; value = v }
}
