import Foundation

/// Injectable time source (plan-glm V01). Components must never call
/// `Date()` or read the process uptime directly: they receive a `Clock` so
/// tests can drive wall and elapsed time deterministically without sleeping.
protocol Clock: Sendable {
    /// Wall-clock time, used for timestamps persisted in history/logs/caches.
    var now: Date { get }
    /// Monotonic elapsed seconds since an arbitrary epoch, immune to wall-clock
    /// jumps (NTP adjustments, manual date changes). Use for durations.
    var uptimeSeconds: Double { get }
}

/// Production clock. Monotonic source is `DispatchTime` (process uptime).
struct SystemClock: Clock {
    var now: Date { Date() }
    var uptimeSeconds: Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

/// Deterministic clock for pure tests (V01-AC02). Time advances only when
/// `advance` is called — no `Thread.sleep` is ever needed to observe elapsed
/// behavior.
///
/// Class semantics on purpose: components capture the injected clock by
/// reference, so a test advances ONE instance and every holder observes it.
/// `@unchecked Sendable` is justified, not cosmetic: every mutable byte is
/// guarded by `lock`, which is precisely how absence of data races is proven.
final class FixedClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var wall: Date
    private var elapsed: Double

    init(wall: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.wall = wall
        self.elapsed = 0
    }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return wall
    }

    var uptimeSeconds: Double {
        lock.lock(); defer { lock.unlock() }
        return elapsed
    }

    /// Advances both sources. `wallSeconds` defaults to `seconds` so tests
    /// usually move wall and elapsed together; pass different values to
    /// simulate wall-clock jumps (which must not affect elapsed time).
    func advance(seconds: Double, wallSeconds: Double? = nil) {
        lock.lock(); defer { lock.unlock() }
        elapsed += seconds
        wall = wall.addingTimeInterval(wallSeconds ?? seconds)
    }
}
