//
//  Sockets.TCP.Listener.Tests.BlockingIdleCPU.swift
//  swift-sockets
//

import IO
import Kernel
import Sockets
import Testing

extension Sockets.TCP.Listener.Tests {
    @Suite
    struct `Release Source Laws` {}
}

extension Sockets.TCP.Listener.Tests.`Release Source Laws` {
    @Test
    func `listener release has the downstream nonthrowing async closure shape`() async throws {
        let listenerIO: IO<Sockets.TCP.Listener.Capabilities> = try .events()
        let connectionIO: IO<Sockets.Capabilities> = try .events()
        let listener = try Sockets.TCP.Listener.open(
            address: Kernel.Socket.Address.IPv4.loopback(port: 0),
            listenerIO: listenerIO,
            connectionIO: connectionIO
        )

        let release: @Sendable () async -> Void = {
            await listener.release()
        }
        await release()
        await release()
    }

    @Test
    func `release cancels a pending Event accept before descriptor close`() async throws {
        let listenerIO: IO<Sockets.TCP.Listener.Capabilities> = try .events()
        let connectionIO: IO<Sockets.Capabilities> = try .events()
        let listener = try Sockets.TCP.Listener.open(
            address: Kernel.Socket.Address.IPv4.loopback(port: 0),
            listenerIO: listenerIO,
            connectionIO: connectionIO
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do throws(Sockets.Error) {
                    let connection = try await listener.accept()
                    await connection.close()
                    Issue.record("A released pending accept must not produce a connection.")
                } catch {
                    #expect(error == .cancelled || error == .ioShutdown)
                }
            }
            group.addTask {
                await listener.release()
            }
        }

        do throws(Sockets.Error) {
            _ = try await listener.port()
            Issue.record("A released listener must reject descriptor use.")
        } catch {
            #expect(error == .ioShutdown)
        }
    }
}
