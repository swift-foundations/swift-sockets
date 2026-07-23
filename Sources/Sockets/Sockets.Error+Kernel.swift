//
//  Sockets.Error+Kernel.swift
//  swift-sockets
//
//  Cross-layer mapping from the kernel byte-op error types onto
//  Sockets.Error. Used by the blocking strategy's capability closures;
//  the event factory's strategy-failure mapping lives in
//  Sockets.Error+Event.swift; a future completions factory adds its own.
//

internal import Kernel

extension Sockets.Error {

    /// Maps a kernel read error onto the sockets domain.
    ///
    /// `ECONNRESET` surfaces as ``Sockets/Error/connectionReset`` — the
    /// TCP-specific semantic the fd-generic kernel layer cannot name
    /// (swift-io's Basic domain explicitly delegates this case to the
    /// socket layer). Other codes fold into ``Sockets/Error/platform(_:)``.
    internal init(_ error: Kernel.IO.Read.Error) {
        self.init(code: error.code)
    }

    /// Maps a kernel write error onto the sockets domain.
    ///
    /// `ECONNRESET` surfaces as ``Sockets/Error/connectionReset``; other
    /// codes — including `EPIPE`, which is fd-generic rather than
    /// socket-specific — fold into ``Sockets/Error/platform(_:)``.
    internal init(_ error: Kernel.IO.Write.Error) {
        self.init(code: error.code)
    }

    /// Maps a kernel socket-op error onto the sockets domain.
    ///
    /// The disposition matches the byte-op mappings above: `ECONNRESET`
    /// surfaces as ``Sockets/Error/connectionReset``, and every other
    /// code folds into ``Sockets/Error/platform(_:)``. Used by the
    /// `connect` / `send` / `receive` capability bindings on
    /// ``Kernel/Thread/Actor`` and by the reactive connect sequence.
    internal init(_ error: Kernel.Socket.Error) {
        self.init(code: error.code)
    }

    /// Maps a descriptor-control failure produced by the strategy prepare
    /// hook onto the sockets domain.
    internal init(_ error: Kernel.File.Control.Error) {
        switch error {
        case .handle(let error):
            self = .descriptor(error)
        case .platform(let error):
            self.init(code: error.code)
        }
    }

    /// Shared platform-code disposition for the kernel byte-op errors.
    internal init(code: Error_Primitives.Error.Code) {
        if Error_Primitives.Error.Code.POSIX.isECONNRESET(code) {
            self = .connectionReset
        } else {
            self = .platform(code)
        }
    }
}
