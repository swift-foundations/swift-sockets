internal import IO
internal import Kernel

extension Sockets.Error {

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
