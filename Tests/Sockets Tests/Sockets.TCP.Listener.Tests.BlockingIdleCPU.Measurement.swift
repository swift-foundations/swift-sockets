//
//  Sockets.TCP.Listener.Tests.BlockingIdleCPU.Measurement.swift
//  swift-sockets
//

#if os(macOS)

    import IO
    import Kernel
    import Sockets
    import Synchronization

    extension Sockets.TCP.Listener.Tests.`Blocking Idle CPU` {
        final class Measurement: Sendable {
            fileprivate let samples = Mutex<(
                before: (instant: Clock.CPU.Thread.Instant, thread: Kernel.Thread.ID)?,
                after: (instant: Clock.CPU.Thread.Instant, thread: Kernel.Thread.ID)?
            )>((nil, nil))
        }
    }

    extension Sockets.TCP.Listener.Tests.`Blocking Idle CPU`.Measurement {
        /// Nested accessor for phase-sample capture.
        var record: Record { Record(measurement: self) }

        /// Nested accessor for measurement-instrumented IO wrappers.
        var wrap: Wrap { Wrap(measurement: self) }

        func snapshot() -> (
            before: (instant: Clock.CPU.Thread.Instant, thread: Kernel.Thread.ID)?,
            after: (instant: Clock.CPU.Thread.Instant, thread: Kernel.Thread.ID)?
        ) {
            samples.withLock { $0 }
        }
    }

    extension Sockets.TCP.Listener.Tests.`Blocking Idle CPU`.Measurement {
        struct Record: Sendable {
            fileprivate let measurement: Sockets.TCP.Listener.Tests.`Blocking Idle CPU`.Measurement
        }

        struct Wrap: Sendable {
            fileprivate let measurement: Sockets.TCP.Listener.Tests.`Blocking Idle CPU`.Measurement
        }
    }

    extension Sockets.TCP.Listener.Tests.`Blocking Idle CPU`.Measurement.Record {
        /// Samples the reactor thread just before accept readiness returns.
        func before() {
            measurement.samples.withLock { samples in
                samples.before = (Clock.CPU.Thread.now(), Kernel.Thread.ID.current)
            }
        }

        /// Samples the preparing thread as the accepted connection arrives.
        func after() {
            measurement.samples.withLock { samples in
                samples.after = (Clock.CPU.Thread.now(), Kernel.Thread.ID.current)
            }
        }
    }

    extension Sockets.TCP.Listener.Tests.`Blocking Idle CPU`.Measurement.Wrap {
        func listener(wrapping inner: IO<Sockets.Capabilities>) -> IO<Sockets.Capabilities> {
            let measurement = measurement
            let capabilities = Sockets.Capabilities(
                prepare: inner.capabilities.prepare,
                read: inner.capabilities.read,
                write: inner.capabilities.write,
                close: inner.capabilities.close,
                ready: { fd, interest throws(Sockets.Error) in
                    try await inner.ready(from: fd, interest: interest)
                    measurement.record.before()
                },
                connect: inner.capabilities.connect,
                send: inner.capabilities.send,
                receive: inner.capabilities.receive
            )
            return IO(capabilities: capabilities, runner: inner.runner)
        }

        func accepted(wrapping inner: IO<Sockets.Capabilities>) -> IO<Sockets.Capabilities> {
            let measurement = measurement
            let capabilities = Sockets.Capabilities(
                prepare: { fd throws(Sockets.Error) in
                    measurement.record.after()
                    try inner.prepare(fd)
                },
                read: inner.capabilities.read,
                write: inner.capabilities.write,
                close: inner.capabilities.close,
                ready: inner.capabilities.ready,
                connect: inner.capabilities.connect,
                send: inner.capabilities.send,
                receive: inner.capabilities.receive
            )
            return IO(capabilities: capabilities, runner: inner.runner)
        }
    }

#endif
