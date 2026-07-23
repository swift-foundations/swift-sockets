//
//  Sockets.Event.Tests.Lifecycle.swift
//  swift-sockets
//

import IO
import Kernel
import Testing

@testable import Sockets

extension Sockets.Event.Tests {
    @Test
    func `owned shutdown is idempotent rejects new work and still closes descriptors`() async {
        let io: IO<Sockets.Capabilities>
        do throws(Kernel.Event.Failure) {
            io = try .events()
        } catch {
            Issue.record("Owned events factory unavailable: \(error)")
            return
        }
        let descriptor: Kernel.Socket.Descriptor
        do throws(Kernel.Socket.Error) {
            descriptor = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
        } catch {
            Issue.record("Socket creation failed: \(error)")
            return
        }
        do throws(Sockets.Error) {
            try io.prepare(descriptor)
        } catch {
            Issue.record("Initial preparation failed: \(error)")
            return
        }

        unsafe (_ = io.runner.executor())
        await io.runner.shutdown()
        await io.runner.shutdown()
        unsafe (_ = io.runner.executor())

        do throws(Sockets.Error) {
            try io.prepare(descriptor)
            Issue.record("Owned IO must reject preparation after its lifecycle stops.")
        } catch {
            #expect(error == .ioShutdown)
        }

        await io.close(consume descriptor)
    }

    @Test
    func `owned shutdown stops loop but retains actor and executor until owner deinit`() async throws(Kernel.Event.Failure) {
        var actor: Kernel.Event.Actor? = try Kernel.Event.Actor()
        weak var weakActor: Kernel.Event.Actor?
        weakActor = actor
        var owner: Sockets.Event.Owner? = Sockets.Event.Owner(actor!)
        actor = nil

        #expect(weakActor != nil)
        await owner!.shutdown()
        await owner!.shutdown()
        unsafe (_ = owner!.executor)
        #expect(weakActor != nil, "Shutdown must retain the actor backing runner.executor for the owner lifetime.")

        owner = nil

        for _ in 0..<100 where weakActor != nil {
            await Task.yield()
        }
        #expect(weakActor == nil, "Actor release belongs to owner/IO deinitialization, not shutdown.")
    }

    @Test
    func `concurrent owned shutdown callers all join actor shutdown completion`() async throws(Kernel.Event.Failure) {
        let actor = try Kernel.Event.Actor()
        let owner = Sockets.Event.Owner(actor)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await owner.shutdown()
                }
            }
        }

        do throws(Sockets.Error) {
            _ = try owner.snapshot()
            Issue.record("Every completed shutdown caller must leave new operations rejected.")
        } catch {
            #expect(error == .ioShutdown)
        }
        unsafe (_ = owner.executor)
    }

    @Test
    func `caller owned runner shutdown leaves actor usable and caller controlled`() async {
        let actor: Kernel.Event.Actor
        do throws(Kernel.Event.Failure) {
            actor = try Kernel.Event.Actor()
        } catch {
            Issue.record("Caller-owned actor unavailable: \(error)")
            return
        }
        let io = IO<Sockets.Capabilities>.events(on: actor)
        let descriptor: Kernel.Socket.Descriptor
        do throws(Kernel.Socket.Error) {
            descriptor = try Kernel.Socket.Create.create(domain: .inet, kind: .stream)
        } catch {
            Issue.record("Socket creation failed: \(error)")
            return
        }

        await io.runner.shutdown()
        do throws(Sockets.Error) {
            try io.prepare(descriptor)
        } catch {
            Issue.record("Caller-owned runner shutdown must leave preparation usable: \(error)")
        }
        await io.close(consume descriptor)

        await actor.shutdown()
    }
}
