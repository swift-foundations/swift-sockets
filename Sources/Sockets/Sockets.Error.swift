public import Kernel

extension Sockets {

    public enum Error: Swift.Error, Equatable {

        case descriptor(Kernel.Descriptor.Validity.Error)

        case registration(Registration)

        case closed(Direction)

        case connectionReset

        case notConnected

        case cancelled

        case ioShutdown

        case timeout

        case platform(Error_Primitives.Error.Code)
    }
}
