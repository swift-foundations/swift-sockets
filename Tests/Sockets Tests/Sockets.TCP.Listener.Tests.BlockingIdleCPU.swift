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
//  is calling-thread CPU time (CLOCK_THREAD_CPUTIME_ID) accumulated across
//  the actual accept(2) call.
//
//  This test guards against a silent regression: if the .blocking factory
//  ever starts setting O_NONBLOCK on the fd (or if the EAGAIN-retry loop
//  fires under the blocking strategy), the CPU delta during the idle
//  window explodes to approximately the wall-clock delta. The 10ms
//  threshold remains well below the hot-spin signature while excluding
//  work performed by unrelated test-runner threads.
//

// WHY macOS-only: the typed Kernel.Thread.ID surface used to prove both
// samples came from the listener executor thread is currently Darwin-owned.

#if os(macOS)

    import Testing
    import Kernel
    import IO
    import Sockets

    extension Sockets.TCP.Listener.Tests {
        @Suite
        struct `Blocking Idle CPU` {}
    }

    extension Sockets.TCP.Listener.Tests.`Blocking Idle CPU` {

        @Test
        func `blocking listener sleeps in kernel during idle accept`() async throws {
            let measurement = Measurement()
            let baseServerIO = IO<Sockets.Capabilities>.blocking()
            let listenerIO = measurement.wrap.listener(wrapping: baseServerIO)
            let acceptedIO = measurement.wrap.accepted(wrapping: baseServerIO)
            let clientIO = IO<Sockets.Capabilities>.blocking()
            let listener = try Sockets.TCP.Listener.blocking(
                address: Kernel.Socket.Address.IPv4.loopback(port: 0),
                io: listenerIO
            )
            let port = try await listener.port()

            // Structured concurrency: two concurrent tasks inside one group.
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
            // Using withThrowingDiscardingTaskGroup avoids the "copy of
            // noncopyable typed value" compiler bug that `async let` with
            // a ~Copyable return type currently hits (Swift 6.3).
            try await withThrowingDiscardingTaskGroup { group in
                group.addTask {
                    let connection = try await listener.accept(io: acceptedIO)
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
            }

            let samples = measurement.snapshot()
            let before = try #require(samples.before)
            let after = try #require(samples.after)
            #expect(
                before.thread == after.thread,
                "CPU samples must bracket accept(2) on one listener executor thread"
            )

            let cpuDelta = after.instant - before.instant
            #expect(
                cpuDelta < .milliseconds(10),
                "blocking listener must not hot-spin while waiting for a connection; \(cpuDelta) CPU on the listener thread"
            )
        }
    }

#endif
