//
//  Sockets.Event.Tests.Stream.swift
//  swift-sockets
//

import IO
import Kernel
import Span_Raw_Primitives
import Testing

@testable import Sockets

extension Sockets.Event.Tests {
    @Test
    func `IPv4 event connect preserves partial write counts and all bytes through EOF`() async {
        let io: IO<Sockets.Capabilities>
        do throws(Kernel.Event.Failure) {
            io = try .events()
        } catch {
            Issue.record("Owned events factory unavailable: \(error)")
            return
        }

        let listener: Sockets.TCP.Listener
        let port: UInt16
        do throws(Sockets.Error) {
            listener = try Sockets.TCP.Listener.reactive(
                address: Kernel.Socket.Address.IPv4.loopback(port: 0),
                io: io
            )
            port = try await listener.port()
        } catch {
            Issue.record("Reactive listener setup failed: \(error)")
            await io.runner.shutdown()
            return
        }
        let gate = Gate()
        let count = 8 * 1_024 * 1_024

        let failures = await withTaskGroup(of: Sockets.Error?.self, returning: [Sockets.Error].self) { group in
            group.addTask {
                do throws(Sockets.Error) {
                    let connection = try await listener.accept(io: io)
                    await gate.wait()

                    let buffer = UnsafeMutableRawBufferPointer.allocate(
                        byteCount: 64 * 1_024,
                        alignment: 1
                    )
                    defer { unsafe buffer.deallocate() }

                    var received = 0
                    while received < count {
                        let read = try await connection.read(into: unsafe .init(buffer))
                        #expect(read > 0)
                        (0..<read).forEach { index in
                            #expect(unsafe buffer[index] == UInt8(truncatingIfNeeded: received + index))
                        }
                        received += read
                    }

                    let eof = try await connection.read(into: unsafe .init(buffer))
                    #expect(eof == 0)
                    #expect(received == count)
                    await connection.close()
                    return nil
                } catch {
                    return error
                }
            }

            group.addTask {
                do throws(Sockets.Error) {
                    let connection = try await Sockets.TCP.Connection.connect(
                        to: Kernel.Socket.Address.IPv4.loopback(port: port),
                        io: io
                    )
                    do throws(Kernel.Socket.Error) {
                        try ISO_9945.Kernel.Socket.Option.set(
                            connection.descriptor,
                            level: .socket,
                            name: .sendBuffer,
                            value: 4_096
                        )
                    } catch {
                        throw Sockets.Error(error)
                    }

                    let buffer = UnsafeMutableRawBufferPointer.allocate(
                        byteCount: count,
                        alignment: 1
                    )
                    defer { unsafe buffer.deallocate() }
                    (0..<count).forEach { index in
                        unsafe buffer[index] = UInt8(truncatingIfNeeded: index)
                    }

                    let first = try await connection.write(
                        from: unsafe .init(UnsafeRawBufferPointer(buffer))
                    )
                    #expect(first > 0)
                    #expect(first < count, "A constrained non-blocking send buffer must expose a partial write.")

                    await gate.open()
                    var written = first
                    while written < count {
                        let remaining = unsafe UnsafeRawBufferPointer(
                            start: buffer.baseAddress!.advanced(by: written),
                            count: count - written
                        )
                        let next = try await connection.write(from: unsafe .init(remaining))
                        #expect(next > 0)
                        written += next
                    }
                    #expect(written == count)

                    try connection.shutdown(how: .write)
                    await connection.close()
                    return nil
                } catch {
                    await gate.open()
                    return error
                }
            }

            var failures: [Sockets.Error] = []
            for await failure in group {
                if let failure {
                    failures.append(failure)
                    group.cancelAll()
                }
            }
            return failures
        }
        failures.forEach { Issue.record("IPv4 event stream fixture failed: \($0)") }

        await io.runner.shutdown()
    }

    @Test
    func `IPv6 event connect reads writes and observes peer EOF`() async {
        let io: IO<Sockets.Capabilities>
        do throws(Kernel.Event.Failure) {
            io = try .events()
        } catch {
            Issue.record("Owned events factory unavailable: \(error)")
            return
        }

        let listener: Sockets.TCP.Listener
        let port: UInt16
        do throws(Sockets.Error) {
            listener = try Sockets.TCP.Listener.reactive(
                address: Kernel.Socket.Address.IPv6.loopback(port: 0),
                io: io
            )
            port = try await listener.port()
        } catch {
            Issue.record("Reactive listener setup failed: \(error)")
            await io.runner.shutdown()
            return
        }
        let payload: [UInt8] = [0x20, 0x01, 0x0d, 0xb8, 0x06]

        let failures = await withTaskGroup(of: Sockets.Error?.self, returning: [Sockets.Error].self) { group in
            group.addTask {
                do throws(Sockets.Error) {
                    let connection = try await listener.accept(io: io)
                    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 64, alignment: 1)
                    defer { unsafe buffer.deallocate() }

                    var read = 0
                    while read < payload.count {
                        let remaining = unsafe UnsafeMutableRawBufferPointer(
                            start: buffer.baseAddress!.advanced(by: read),
                            count: payload.count - read
                        )
                        let next = try await connection.read(into: unsafe .init(remaining))
                        #expect(next > 0)
                        read += next
                    }
                    let eof = try await connection.read(into: unsafe .init(buffer))
                    #expect(eof == 0)

                    let echoed = try await connection.write(
                        from: unsafe .init(
                            UnsafeRawBufferPointer(start: buffer.baseAddress, count: read)
                        )
                    )
                    #expect(echoed == read)
                    try connection.shutdown(how: .write)
                    await connection.close()
                    return nil
                } catch {
                    return error
                }
            }

            group.addTask {
                do throws(Sockets.Error) {
                    let connection = try await Sockets.TCP.Connection.connect(
                        to: Kernel.Socket.Address.IPv6.loopback(port: port),
                        io: io
                    )
                    let write = UnsafeMutableRawBufferPointer.allocate(
                        byteCount: payload.count,
                        alignment: 1
                    )
                    defer { unsafe write.deallocate() }
                    for (index, byte) in payload.enumerated() {
                        unsafe write[index] = byte
                    }
                    let written = try await connection.write(
                        from: unsafe .init(UnsafeRawBufferPointer(write))
                    )
                    #expect(written == payload.count)
                    try connection.shutdown(how: .write)

                    let read = UnsafeMutableRawBufferPointer.allocate(byteCount: 64, alignment: 1)
                    defer { unsafe read.deallocate() }
                    var echoed = 0
                    while echoed < payload.count {
                        let remaining = unsafe UnsafeMutableRawBufferPointer(
                            start: read.baseAddress!.advanced(by: echoed),
                            count: payload.count - echoed
                        )
                        let next = try await connection.read(into: unsafe .init(remaining))
                        #expect(next > 0)
                        echoed += next
                    }
                    payload.indices.forEach { index in
                        #expect(unsafe read[index] == payload[index])
                    }
                    let eof = try await connection.read(into: unsafe .init(read))
                    #expect(eof == 0)
                    await connection.close()
                    return nil
                } catch {
                    return error
                }
            }

            var failures: [Sockets.Error] = []
            for await failure in group {
                if let failure {
                    failures.append(failure)
                    group.cancelAll()
                }
            }
            return failures
        }
        failures.forEach { Issue.record("IPv6 event stream fixture failed: \($0)") }

        await io.runner.shutdown()
    }
}
