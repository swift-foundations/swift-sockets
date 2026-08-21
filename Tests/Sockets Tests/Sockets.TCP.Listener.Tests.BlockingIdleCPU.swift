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
