//
//  IO+Blocking.swift
//  swift-sockets
//
//  Blocking-strategy factory for the sockets domain. Builds an
//  `IO<Sockets.Capabilities>` whose capability closures forward to a
//  `Kernel.Thread.Actor` pinned to a concrete `Kernel.Thread.Executor`.
//  Actor isolation guarantees every syscall runs on that executor's
//  dedicated OS thread — `Task.sleep`, `@MainActor` hops, and
//  unstructured tasks all preserve the binding.
//
//  Phase 2A ships this factory only; the events / completions
//  factories follow in Phase 2B / 2C (see Sockets.TCP).
//

public import Executors
public import IO
internal import Thread_Actor

extension IO where Capabilities == Sockets.Capabilities {

    /// Blocking thread-pool I/O for the sockets domain.
    ///
    /// Rotates through a process-scoped sharded executor pool, pinning
    /// one `Kernel.Thread.Actor` per call. Pass an explicit executor
    /// via ``blocking(on:)`` to share threads across multiple
    /// `IO<Sockets.Capabilities>` values.
    ///
    /// ```swift
    /// let io: IO<Sockets.Capabilities> = .blocking()
    /// let n = try await io.read(from: fd, into: buf)
    /// ```
    public static func blocking() -> IO<Sockets.Capabilities> {
        blocking(on: _sharedExecutors.next())
    }

    /// Blocking I/O strategy bound to an explicit executor.
    ///
    /// Use this overload to co-locate an application actor with the
    /// `IO` on a single executor thread — the runtime elides the per-op
    /// hop when the consumer actor forwards `unownedExecutor` (the
    /// TCA26 shared-executor pattern ``Sockets/TCP/Listener`` uses).
    ///
    /// The caller owns the executor and is responsible for its
    /// shutdown (when applicable). The factory does not shut it down.
    public static func blocking(on executor: Kernel.Thread.Executor) -> IO<Sockets.Capabilities> {
        let actor = Kernel.Thread.Actor(executor: executor)
        let capabilities = Sockets.Capabilities(
            read: { fd, buffer throws(Sockets.Error) -> Int in
                try await actor.read(from: fd, into: buffer)
            },
            write: { fd, buffer throws(Sockets.Error) -> Int in
                try await actor.write(to: fd, from: buffer)
            },
            close: { fd in
                await actor.close(consume fd)
            },
            ready: { _, _ throws(Sockets.Error) -> Void in
                // Blocking strategy treats all fds as always ready — the
                // subsequent syscall is the actual block. Ready-then-
                // syscall composes correctly across strategies with this
                // no-op.
            }
        )
        let runner = unsafe IO.Runner(
            executor: { unsafe actor.unownedExecutor },
            shutdown: {
                // The caller owns the supplied executor's lifecycle
                // (or this executor came from the process-scoped
                // shared pool); the factory does not shut it down.
            }
        )
        return IO(capabilities: capabilities, runner: runner)
    }
}

/// Process-scoped sharded executor pool for the no-argument blocking
/// factory. Lazily initialized; lives for the process lifetime. Each
/// call to `IO<Sockets.Capabilities>.blocking()` pins one shard to a
/// fresh `Kernel.Thread.Actor`.
private let _sharedExecutors: Kernel.Thread.Executor.Sharded = .init()
