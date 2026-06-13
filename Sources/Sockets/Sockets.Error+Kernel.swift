//
//  Sockets.Error+Kernel.swift
//  swift-sockets
//
//  Cross-layer mapping from the kernel byte-op error types onto
//  Sockets.Error. Used by the blocking strategy's capability closures;
//  the events / completions factories (Phase 2B / 2C) add their own
//  strategy-failure mappings alongside.
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

    /// Shared platform-code disposition for the kernel byte-op errors.
    private init(code: Error_Primitives.Error.Code) {
        if Error_Primitives.Error.Code.POSIX.isECONNRESET(code) {
            self = .connectionReset
        } else {
            self = .platform(code)
        }
    }
}
