//
//  Sockets.Event.Tests.Failure.swift
//  swift-sockets
//

import IO
import Kernel
import Span_Raw_Primitives
import Testing

@testable import Sockets

extension Sockets.Event.Tests {
    @Test
    func `refused event connect completes readiness through typed SO_ERROR`() async {
        let io: IO<Sockets.Capabilities>
        do throws(Kernel.Event.Failure) {
            io = try .events()
        } catch {
            Issue.record("Owned events factory unavailable: \(error)")
            return
        }

        let port: UInt16
        do throws(Sockets.Error) {
            let listener = try Sockets.TCP.Listener.reactive(
                address: Kernel.Socket.Address.IPv4.loopback(port: 0),
                io: io
            )
            port = try await listener.port()
        } catch {
            Issue.record("Reactive listener setup failed: \(error)")
            await io.runner.shutdown()
            return
        }

        let descriptor: Kernel.Socket.Descriptor
        do throws(Kernel.Socket.Error) {
            descriptor = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
        } catch {
            Issue.record("Socket creation failed: \(error)")
            await io.runner.shutdown()
            return
        }
        do throws(Sockets.Error) {
            try io.prepare(descriptor)
        } catch {
            Issue.record("Preparation failed: \(error)")
            await io.runner.shutdown()
            return
        }
        let address = Kernel.Socket.Address.IPv4.loopback(port: port)

        do throws(Kernel.Socket.Error) {
            try ISO_9945.Kernel.Socket.Connect.connect(
                descriptor,
                address: address.storage,
                length: Kernel.Socket.Address.IPv4.size
            )
            Issue.record("A non-blocking connection to the closed local port completed without refusal.")
        } catch {
            #expect(error.code.isInProgress || error.code.isInterrupted)
            do throws(Sockets.Error) {
                try await io.ready(from: descriptor, interest: .write)
            } catch {
                Issue.record("Write-readiness completion failed: \(error)")
            }
            do throws(Kernel.Socket.Error) {
                let pending = try ISO_9945.Kernel.Socket.getError(descriptor)
                #expect(pending != .posix(0), "Write readiness alone is not connection success; SO_ERROR must carry the refusal.")
            } catch {
                Issue.record("SO_ERROR retrieval failed: \(error)")
            }
        }
        await io.close(consume descriptor)

        do throws(Sockets.Error) {
            let connection = try await Sockets.TCP.Connection.connect(
                to: address,
                io: io
            )
            await connection.close()
            Issue.record("The public event-backed connect factory must surface the refused SO_ERROR.")
        } catch {
            guard case .platform(let code) = error else {
                Issue.record("Expected a typed platform refusal, got \(error).")
                await io.runner.shutdown()
                return
            }
            #expect(code != .posix(0))
        }

        await io.runner.shutdown()
    }

    @Test
    func `event read cancellation deregisters before close and peer observes EOF`() async {
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

        let failures = await withTaskGroup(of: Sockets.Error?.self, returning: [Sockets.Error].self) { group in
            group.addTask {
                do throws(Sockets.Error) {
                    let connection = try await listener.accept(io: io)
                    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1, alignment: 1)
                    defer { unsafe buffer.deallocate() }
                    let eof = try await connection.read(into: unsafe .init(buffer))
                    #expect(eof == 0, "Closing after cancelled read must deliver EOF to the peer.")
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
                    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1, alignment: 1)
                    defer { unsafe buffer.deallocate() }

                    unsafe withUnsafeCurrentTask { task in unsafe task?.cancel() }
                    do throws(Sockets.Error) {
                        _ = try await connection.read(into: unsafe .init(buffer))
                        Issue.record("Cancelled event read must not remain enlisted.")
                    } catch {
                        #expect(error == .cancelled)
                    }
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
        failures.forEach { Issue.record("Cancellation fixture failed: \($0)") }

        await io.runner.shutdown()
    }

    @Test
    func `deadline task drives event read cancellation without adding timeout policy`() async {
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
        let started = Gate()

        let failures = await withTaskGroup(of: Sockets.Error?.self, returning: [Sockets.Error].self) { group in
            group.addTask {
                do throws(Sockets.Error) {
                    let connection = try await listener.accept(io: io)
                    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1, alignment: 1)
                    defer { unsafe buffer.deallocate() }
                    let eof = try await connection.read(into: unsafe .init(buffer))
                    #expect(eof == 0)
                    await connection.close()
                    return nil
                } catch {
                    return error
                }
            }

            group.addTask {
                let operation = Task { () -> Sockets.Error? in
                    do throws(Sockets.Error) {
                        let connection = try await Sockets.TCP.Connection.connect(
                            to: Kernel.Socket.Address.IPv4.loopback(port: port),
                            io: io
                        )
                        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1, alignment: 1)
                        defer { unsafe buffer.deallocate() }
                        await started.open()
                        do throws(Sockets.Error) {
                            _ = try await connection.read(into: unsafe .init(buffer))
                            await connection.close()
                            return nil
                        } catch {
                            await connection.close()
                            return error
                        }
                    } catch {
                        return error
                    }
                }

                await started.wait()
                let deadline = Task { try await Task.sleep(for: .milliseconds(20)) }
                _ = await deadline.result
                operation.cancel()
                let error = await operation.value
                #expect(error == .cancelled)
                return nil
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
        failures.forEach { Issue.record("Deadline fixture failed: \($0)") }

        await io.runner.shutdown()
    }
}
