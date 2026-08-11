//
//  Sockets.Error+Event.swift
//  swift-sockets
//

internal import IO
internal import Kernel

extension Sockets.Error {
    #if !os(Windows)
        /// Maps the exact terminal domains of an Event-enlisted socket attempt.
        internal init(_ error: Event.Wait.Error<Kernel.Socket.Error>) {
            switch error {
            case .event(let failure): self.init(failure)
            case .thread(let failure): self.init(failure)
            case .operation(let failure): self.init(failure)
            }
        }
    #endif

    /// Maps structured worker creation/join failure without erasure.
    internal init(_ error: Kernel.Thread.Error) {
        #if os(Windows)
            switch error {
            case .create(let failure): self = .platform(failure.code)
            }
        #else
            switch error {
            case .create(let code),
                 .join(let code),
                 .detach(let code),
                 .keyCreate(let code),
                 .keySet(let code):
                self = .platform(code)
            }
        #endif
    }

    /// Maps a strategy-level reactor failure into the sockets domain.
    ///
    /// Exhaustive semantic mapping:
    ///
    /// | Event error | Sockets error |
    /// | --- | --- |
    /// | `platform(code)` | existing platform-code disposition |
    /// | `invalidDescriptor` | `descriptor(.invalid)` |
    /// | `alreadyRegistered` | `registration(.duplicate)` |
    /// | `notRegistered` | `registration(.missing)` |
    /// | `deregistered` | `registration(.removed)` |
    /// | `readClosed` / `writeClosed` | `closed(.read)` / `closed(.write)` |
    /// | `notConnected` | `notConnected` |
    internal init(_ failure: Kernel.Event.Failure) {
        switch failure {
        case .left(.cancelled):
            self = .cancelled
        case .left(.shutdown):
            self = .ioShutdown
        case .left(.timeout):
            self = .timeout
        case .right(let error):
            switch error {
            case .platform(let code):
                self.init(code: code)
            case .invalidDescriptor:
                self = .descriptor(.invalid)
            case .alreadyRegistered:
                self = .registration(.duplicate)
            case .notRegistered:
                self = .registration(.missing)
            case .deregistered:
                self = .registration(.removed)
            case .readClosed:
                self = .closed(.read)
            case .writeClosed:
                self = .closed(.write)
            case .notConnected:
                self = .notConnected
            }
        }
    }
}
