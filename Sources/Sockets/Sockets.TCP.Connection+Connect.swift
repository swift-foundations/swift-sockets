//
//  Sockets.TCP.Connection+Connect.swift
//  swift-sockets
//
//  Client-side construction for Sockets.TCP.Connection: the `connect`
//  factories (IPv4 / IPv6) and the reactive (non-blocking) connect
//  sequence they compose through `io`.
//

public import IO
public import Kernel

// MARK: - Client Construction

extension Sockets.TCP.Connection {

    /// Connects to an IPv4 peer, returning the established connection.
    ///
    /// Creates a `.stream` socket in the `.inet` domain, connects it to
    /// `address` through the supplied `io`, and returns a
    /// ``Sockets/TCP/Connection`` owning the connected descriptor. Byte-level
    /// read/write/close then flow through the same `io`.
    ///
    /// ## Strategy pairing
    ///
    /// The `io` determines how the connect blocks — the compiler cannot
    /// verify the pairing, exactly as for ``Sockets/TCP/Listener``:
    ///
    /// - `io: .blocking()` — the descriptor stays in blocking mode and
    ///   `connect(2)` sleeps in the kernel until the handshake completes
    ///   (EINTR-safe via the POSIX completion policy).
    /// - A reactor-backed `io` — the connect capability switches the
    ///   descriptor to `O_NONBLOCK`, initiates the connect, and awaits
    ///   write-readiness before checking `SO_ERROR`
    ///   (``connectReactively(_:to:length:ready:)``).
    ///
    /// Match `io` to the strategy at the call site.
    public static func connect(
        to address: Kernel.Socket.Address.IPv4,
        io: IO<Sockets.Capabilities>
    ) async throws(Sockets.Error) -> sending Sockets.TCP.Connection {
        let socket: Kernel.Descriptor
        do throws(Kernel.Socket.Error) {
            socket = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
        } catch {
            throw Sockets.Error(error)
        }
        try await io.connect(socket, to: address.storage, length: Kernel.Socket.Address.IPv4.size)
        return Sockets.TCP.Connection(descriptor: consume socket, peer: address.storage, io: io)
    }

    /// Connects to an IPv6 peer, returning the established connection.
    ///
    /// The IPv6 companion of the IPv4 `connect(to:io:)` factory — creates a
    /// `.stream` socket in the `.inet6` domain; the strategy pairing is
    /// identical.
    public static func connect(
        to address: Kernel.Socket.Address.IPv6,
        io: IO<Sockets.Capabilities>
    ) async throws(Sockets.Error) -> sending Sockets.TCP.Connection {
        let socket: Kernel.Descriptor
        do throws(Kernel.Socket.Error) {
            socket = try Kernel.Socket.Create.create(domain: .inet6, kind: .stream)
        } catch {
            throw Sockets.Error(error)
        }
        try await io.connect(socket, to: address.storage, length: Kernel.Socket.Address.IPv6.size)
        return Sockets.TCP.Connection(descriptor: consume socket, peer: address.storage, io: io)
    }
}

// MARK: - Reactive Connect Sequence

extension Sockets.TCP.Connection {

    /// Non-blocking connect sequence, parameterized by a readiness primitive.
    ///
    /// The reactor-path counterpart of the blocking `connect` binding on
    /// ``Kernel/Thread/Actor``. It switches the descriptor to `O_NONBLOCK`,
    /// initiates the connect, and — when the handshake is still in progress
    /// — awaits write-readiness through the injected `ready` closure before
    /// reading `SO_ERROR` to determine the outcome. Because readiness is a
    /// parameter, a future reactor- / proactor-backed factory reuses this
    /// sequence unchanged, supplying its own kernel-readiness primitive in
    /// place of the test-support poll.
    ///
    /// `package` rather than `public`: it is the wiring seam for
    /// strategy factories (including the tests' reactive factory), not part
    /// of the consumer-facing surface.
    package static func connectReactively(
        _ descriptor: borrowing Kernel.Descriptor,
        to address: Kernel.Socket.Address.Storage,
        length: Kernel.Socket.Address.Length,
        ready: (borrowing Kernel.Descriptor, Kernel.Event.Interest) async throws(Sockets.Error) -> Void
    ) async throws(Sockets.Error) {
        // 1. Switch to non-blocking so connect(2) returns immediately.
        do throws(Kernel.File.Control.Error) {
            try Kernel.File.Control.setNonBlocking(descriptor)
        } catch {
            switch error {
            case .platform(let err): throw .platform(err.code)
            case .handle(let err): throw .platform(err.code)
            }
        }

        // 2. Initiate the connect. On a non-blocking socket this either
        //    completes immediately (typical on loopback) or reports the
        //    attempt is in progress (EINPROGRESS) / was interrupted (EINTR).
        //    Any other error is a hard failure surfaced to the caller.
        do throws(Kernel.Socket.Error) {
            try ISO_9945.Kernel.Socket.Connect.connect(descriptor, address: address, length: length)
            return
        } catch {
            let code = error.code
            guard code.isInterrupted || Self.isInProgress(code) else {
                throw Sockets.Error(error)
            }
        }

        // 3. Await write-readiness via the injected primitive (a poll under
        //    the test-support reactor; a kernel readiness event under a
        //    real one).
        try await ready(descriptor, .write)

        // 4. Read the pending socket error: SO_ERROR == 0 means connected,
        //    anything else is the connect failure (ECONNREFUSED, etc.).
        let pending: Error_Primitives.Error.Code
        do throws(Kernel.Socket.Error) {
            pending = try ISO_9945.Kernel.Socket.getError(descriptor)
        } catch {
            throw Sockets.Error(error)
        }
        guard pending == .posix(0) else {
            throw .platform(pending)
        }
    }

    /// `EINPROGRESS` test — the "connect in progress" sentinel is absent
    /// from the shared error vocabulary and its value differs by platform
    /// (Darwin 36, Linux / Musl 115).
    private static func isInProgress(_ code: Error_Primitives.Error.Code) -> Bool {
        #if canImport(Darwin)
            return code == .posix(36)
        #else
            return code == .posix(115)
        #endif
    }
}
