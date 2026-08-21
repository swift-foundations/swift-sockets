internal import Kernel

extension Sockets.Error {

    internal init(_ error: Kernel.IO.Read.Error) {
        self.init(code: error.code)
    }

    internal init(_ error: Kernel.IO.Write.Error) {
        self.init(code: error.code)
    }

    internal init(_ error: Kernel.Socket.Error) {
        self.init(code: error.code)
    }

    internal init(_ error: Kernel.File.Control.Error) {
        switch error {
        case .handle(let error):
            self = .descriptor(error)

        case .platform(let error):
            self.init(code: error.code)
        }
    }

    internal init(code: Error_Primitives.Error.Code) {
        if Error_Primitives.Error.Code.POSIX.isECONNRESET(code) {
            self = .connectionReset
        } else {
            self = .platform(code)
        }
    }
}
