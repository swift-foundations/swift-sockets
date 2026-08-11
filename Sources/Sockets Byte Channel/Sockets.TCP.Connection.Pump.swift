public import Byte_Chunk
public import Sockets

extension Sockets.TCP.Connection {
    /// The full-duplex relation between one TCP connection and one byte-channel endpoint.
    ///
    /// A pump owns exactly one connection, one channel endpoint, and one task for
    /// each direction. It does not introduce another byte queue, a transport
    /// provider, or TLS policy. Socket EOF finishes the channel writer; channel
    /// EOF half-closes the socket write direction. Any cancellation or terminal
    /// failure closes the connection and finishes the applicable channel end.
    public struct Pump<Failure: Swift.Error & Sendable>: ~Copyable, Sendable {
        @usableFromInline
        let storage: __SocketsTCPConnectionPumpStorage<Failure>

        @usableFromInline
        let socketToChannel: Task<Void, Never>

        @usableFromInline
        let channelToSocket: Task<Void, Never>

        @usableFromInline
        init(
            storage: __SocketsTCPConnectionPumpStorage<Failure>,
            socketToChannel: Task<Void, Never>,
            channelToSocket: Task<Void, Never>
        ) {
            self.storage = storage
            self.socketToChannel = socketToChannel
            self.channelToSocket = channelToSocket
        }

        /// Cancels both directions, awaits them, and releases the endpoint once.
        public consuming func close() async {
            socketToChannel.cancel()
            channelToSocket.cancel()
            await storage.close()
            await socketToChannel.value
            await channelToSocket.value
        }
    }

    /// Starts one event-backed task in each direction.
    ///
    /// `maximum` must be nonzero and no greater than the channel's declared
    /// byte capacity. The failure mapper is used only for `Sockets.Error`
    /// produced while reading or writing the TCP connection.
    public consuming func pump<Failure: Swift.Error & Sendable>(
        _ channel: consuming Byte.Channel<Failure>,
        maximum: Index<Byte>.Count,
        failure: @escaping @Sendable (Sockets.Error) -> Failure
    ) -> Sockets.TCP.Connection.Pump<Failure> {
        precondition(maximum != .zero, "pump maximum must be nonzero")
        precondition(
            maximum <= channel.capacity.count,
            "pump maximum must not exceed channel byte capacity"
        )

        let storage = __SocketsTCPConnectionPumpStorage(
            connection: consume self,
            channel: consume channel,
            maximum: maximum,
            failure: failure
        )
        let socketToChannel = Task { await storage.socketToChannel() }
        let channelToSocket = Task { await storage.channelToSocket() }
        return .init(
            storage: storage,
            socketToChannel: socketToChannel,
            channelToSocket: channelToSocket
        )
    }
}

@usableFromInline
actor __SocketsTCPConnectionPumpStorage<Failure: Swift.Error & Sendable> {
    @usableFromInline
    var connection: Sockets.TCP.Connection?

    @usableFromInline
    var channel: Byte.Channel<Failure>?

    @usableFromInline
    let maximum: Index<Byte>.Count

    @usableFromInline
    let failure: @Sendable (Sockets.Error) -> Failure

    @usableFromInline
    init(
        connection: consuming Sockets.TCP.Connection,
        channel: consuming Byte.Channel<Failure>,
        maximum: Index<Byte>.Count,
        failure: @escaping @Sendable (Sockets.Error) -> Failure
    ) {
        self.connection = consume connection
        self.channel = consume channel
        self.maximum = maximum
        self.failure = failure
    }

    @usableFromInline
    func socketToChannel() async {
        do {
            while !Task.isCancelled {
                guard let chunk = try await connection?.read(maximum: maximum) else {
                    channel?.writer.finish()
                    return
                }
                try await channel?.writer.send(consume chunk)
            }
        } catch let error as Sockets.Error {
            channel?.writer.fail(consume failure(error))
        } catch {
            await close()
        }
        await close()
    }

    @usableFromInline
    func channelToSocket() async {
        do {
            while !Task.isCancelled {
                guard let chunk = try await channel?.reader.receive() else {
                    try connection?.shutdown(how: .write)
                    return
                }
                try await connection?.write(consume chunk)
            }
        } catch let error as Sockets.Error {
            channel?.reader.fail(consume failure(error))
        } catch {
            await close()
        }
        await close()
    }

    @usableFromInline
    func close() async {
        guard let connection = consume connection else { return }
        channel?.reader.finish()
        channel?.writer.finish()
        await connection.close()
    }
}
