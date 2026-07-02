# swift-sockets

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

TCP socket endpoints for Swift — a listener actor and move-only connections with typed throws, half-close, and syscalls pinned to a dedicated OS thread.

---

## Key Features

- **Typed throws end-to-end** — Every operation throws `Sockets.Error`; no `any Error` escapes the API surface
- **Move-only connections** — `Sockets.TCP.Connection` is `~Copyable`: single ownership by construction, `close()` consumes the value, and a dropped connection closes its descriptor deterministically
- **Half-close** — `shutdown(how: .write)` sends a TCP FIN while the connection remains valid for reading — the standard graceful-teardown pattern, expressed as a `borrowing` method
- **Off the cooperative pool** — Blocking syscalls run on a dedicated OS thread behind an actor executor, so `accept(2)`, `read(2)`, and `write(2)` never stall Swift's cooperative thread pool
- **Strategy-parametric** — Endpoints compose over an `IO<Sockets.Capabilities>` capability bundle; the blocking strategy ships today, and readiness-based strategies plug in through the same surface

---

## Quick Start

An echo server: bind to an ephemeral port, accept a connection, echo the bytes back, and tear down gracefully with a half-close. The connection's `~Copyable` ownership makes the descriptor lifecycle checkable by the compiler — `close()` consumes the value, so use-after-close does not compile.

```swift
import IO
import Kernel
import Sockets
import Span_Raw_Primitives

let io: IO<Sockets.Capabilities> = .blocking()
let listener = try Sockets.TCP.Listener.blocking(
    address: .loopback(port: 0),
    io: io
)
let port = try await listener.port()  // kernel-assigned ephemeral port

let connection = try await listener.accept()

let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
defer { buffer.deallocate() }

let count = try await connection.read(into: .init(buffer))
_ = try await connection.write(
    from: .init(UnsafeRawBufferPointer(start: buffer.baseAddress, count: count))
)

try connection.shutdown(how: .write)  // half-close: FIN to the peer, reads stay valid
await connection.close()              // consuming — the connection cannot be used again
```

The buffer parameters are non-owning raw spans; the caller keeps the memory alive and at a stable address for the duration of each call.

---

## Installation

Add swift-sockets to your Package.swift:

```swift
dependencies: [
    .package(url: "https://github.com/swift-foundations/swift-sockets.git", branch: "main")
]
```

Add the product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Sockets", package: "swift-sockets")
    ]
)
```

### Requirements

- Swift 6.3+
- macOS 26+ / iOS 26+ / tvOS 26+ / watchOS 26+ / visionOS 26+

---

## Architecture

Single module (`Sockets`) with a small surface:

| Type | Role |
|------|------|
| `Sockets.TCP.Listener` | Actor bound to a local IPv4 address; `accept()` produces connections, `port()` recovers the bound port |
| `Sockets.TCP.Connection` | `~Copyable` accepted connection; `read` / `write` / `shutdown` / consuming `close` |
| `Sockets.Error` | Typed error domain thrown by every operation |
| `Sockets.Capabilities` | The four operation closures (`read`, `write`, `close`, `ready`) a strategy supplies |
| `IO<Sockets.Capabilities>.blocking()` | Blocking-strategy factory; `blocking(on:)` accepts an explicit executor for thread sharing |

The listener forwards its `unownedExecutor` to the `IO`'s executor, so accept handling and byte-level I/O run on the same dedicated thread. An application actor that forwards its own `unownedExecutor` the same way elides the per-call executor hop:

```swift
import IO
import Sockets

actor Server {
    let io: IO<Sockets.Capabilities>
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        io.unownedExecutor
    }
}
```

Two listener factories make the fd-mode-to-strategy pairing explicit: `blocking(address:io:backlog:)` keeps the fd in kernel blocking mode (pair with `.blocking()`), and `reactive(address:io:backlog:)` sets `O_NONBLOCK` for readiness-based strategies. The compiler cannot verify the pairing — match factory to strategy at the call site.

---

## Error Handling

Every throwing operation throws `Sockets.Error`:

```
Sockets.Error
├── .connectionReset    // ECONNRESET — peer reset the stream
├── .notConnected       // ENOTCONN — reserved; not produced by the blocking strategy
├── .cancelled          // task cancelled (readiness-based strategies)
├── .ioShutdown         // IO runtime shutting down (readiness-based strategies)
└── .platform(code)     // any other platform error code
```

Typed throws makes exhaustive handling checkable:

```swift
do {
    let count = try await connection.read(into: .init(buffer))
} catch .connectionReset {
    // Peer reset — tear down this connection
} catch .cancelled, .ioShutdown {
    // The IO runtime is going away — stop serving
} catch .notConnected {
    // Socket operation on an unconnected socket
} catch .platform(let code) {
    // Inspect the platform error code
}
```

---

## Scope

The current surface is the blocking strategy over IPv4 TCP: listener, accepted connections, half-close, and local-port discovery. Client `connect`, UDP, DNS resolution, IPv6 and Unix-domain addresses, and readiness-based (reactor / proactor) strategies are not part of the current surface — the `reactive` listener factory exists ahead of those strategies. Public type names may change in 0.x.

---

## Community

<!-- BEGIN: discussion -->
*Discussion thread will be created at first public release.*
<!-- END: discussion -->

---

## License

Apache 2.0. See [LICENSE.md](LICENSE.md) for details.
