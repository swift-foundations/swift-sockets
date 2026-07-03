//
//  Sockets.TCP.Listener.Tests.BlockingIdleCPU.swift
//  swift-sockets
//
//  Idle-accept CPU test — proves that a .blocking-factory Listener paired
//  with the blocking-strategy IO sleeps in kernel accept(2) rather than
//  hot-spinning on EAGAIN retries.
//
//  Wall-clock alone cannot distinguish "thread sleeping in kernel" from
//  "thread hot-spinning on EAGAIN" — both take the same wall time between
//  `listener.accept()` call and client connect. The distinguishing metric
//  is process CPU time (CLOCK_PROCESS_CPUTIME_ID) accumulated during the
//  idle window.
//
//  This test guards against a silent regression: if the .blocking factory
//  ever starts setting O_NONBLOCK on the fd (or if the EAGAIN-retry loop
//  fires under the blocking strategy), the CPU delta during the idle
//  window explodes to ~= wall-clock delta. The threshold on a 50ms window
//  is heuristic — comfortable above baseline test-scaffolding noise and
//  well below hot-spin signature. Tighten if 3C benchmarks surface a
//  tighter idle budget.
//

// WHY macOS-only: CLOCK_PROCESS_CPUTIME_ID measures all threads in the
// process. In Docker after a cold build, swift-testing runner threads
// inflate the baseline (~100 ms) past the hot-spin delta (~50 ms),
// making the assertion unreliable. The code path through
// Listener.accept() → io.ready → accept(2) is platform-identical;
// if macOS catches a hot-spin regression, Linux has the same path.
// The Echo parameterized test proves blocking-strategy correctness
// (round-trip, no hang) on Linux independently.

#if os(macOS)

    import Testing
    import Kernel
    import IO
    import Sockets

    extension Sockets.TCP.Listener.Tests {
        @Suite("Sockets.TCP.Listener — blocking-strategy no-hot-spin")
        struct BlockingIdleCPU {}
    }

    extension Sockets.TCP.Listener.Tests.BlockingIdleCPU {

        @Test
        func `blocking listener sleeps in kernel during idle accept`() async throws {
            let serverIO = IO<Sockets.Capabilities>.blocking()
            let clientIO = IO<Sockets.Capabilities>.blocking()
            let listener = try Sockets.TCP.Listener.blocking(
                address: .loopback(port: 0),
                io: serverIO
            )
            let port = try await listener.port()

            // Structured concurrency: three concurrent tasks inside one group.
            //
            // 1. Server task: calls listener.accept() and closes the connection.
            //    With a blocking fd + blocking strategy, accept(2) sleeps in
            //    the kernel until a connection arrives. The Connection is
            //    ~Copyable and consumed inside the task; nothing crosses the
            //    task boundary.
            //
            // 2. Client task: sleeps 100 ms (async, no CPU burn), then
            //    connects and closes. The 100 ms delay is the idle window
            //    during which the server should be sleeping in kernel, not
            //    spinning.
            //
            // 3. Measurement task: measures process CPU delta across the
            //    first 50 ms of the idle window. If the blocking path is
            //    correct, no thread in the process is consuming CPU
            //    (server sleeps in kernel, client sleeps in Task.sleep,
            //    test runner itself is sleeping too).
            //
            // Using withThrowingDiscardingTaskGroup avoids the "copy of
            // noncopyable typed value" compiler bug that `async let` with
            // a ~Copyable return type currently hits (Swift 6.3).
            try await withThrowingDiscardingTaskGroup { group in
                group.addTask {
                    let connection = try await listener.accept()
                    await connection.close()
                }
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(100))
                    let socket = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
                    try POSIX.Kernel.Socket.Connect.connect(
                        socket,
                        address: Kernel.Socket.Address.IPv4.loopback(port: port)
                    )
                    let descriptor = consume socket
                    await clientIO.close(consume descriptor)
                }
                group.addTask {
                    let cpuBefore = Clock.CPU.Process.now()
                    try? await Task.sleep(for: .milliseconds(50))
                    let cpuAfter = Clock.CPU.Process.now()

                    let cpuDelta = cpuAfter - cpuBefore
                    // Threshold is heuristic — 20% of window. Concurrent
                    // threads from sibling test cells add ~1-2 ms baseline
                    // process CPU noise; 10 ms absorbs that while remaining
                    // 5x below a hot-spin signature (~50 ms from one
                    // spinning thread). Tighten if 3C benchmarks surface a
                    // tighter blocking-strategy idle budget.
                    #expect(
                        cpuDelta < .milliseconds(10),
                        "blocking listener must not hot-spin while waiting for a connection; \(cpuDelta) CPU in 50 ms window"
                    )
                }
            }
        }
    }

#endif
