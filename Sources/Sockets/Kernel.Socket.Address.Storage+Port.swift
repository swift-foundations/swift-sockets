internal import Kernel

extension Kernel.Socket.Address.Storage {

    internal var _port: UInt16 {
        precondition(
            family == .inet || family == .inet6,
            "Storage._port is only valid for IPv4/IPv6 addresses; got \(family)."
        )

        return unsafe withUnsafeBytes { raw, _ in
            let networkPort = unsafe raw.load(fromByteOffset: 2, as: UInt16.self)
            return UInt16(bigEndian: networkPort)
        }
    }
}
