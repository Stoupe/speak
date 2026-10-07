import Testing
@testable import SpeakCore

@Suite struct TriggerStateMachineTests {
    var machine = TriggerStateMachine(holdThreshold: 0.25, doubleTapWindow: 0.3)

    @Test mutating func holdAndRelease() {
        #expect(machine.handle(.fnDown, at: 0) == [.startRecording])
        #expect(machine.handle(.fnUp, at: 1.0) == [.commit])
        #expect(machine.state == .idle)
    }

    @Test mutating func singleShortTapCancelsAfterWindow() {
        #expect(machine.handle(.fnDown, at: 0) == [.startRecording])
        #expect(machine.handle(.fnUp, at: 0.1) == [.scheduleTapWindow(id: 1, seconds: 0.3)])
        #expect(machine.handle(.tapWindowElapsed(id: 1), at: 0.4) == [.cancel])
        #expect(machine.state == .idle)
    }

    @Test mutating func doubleTapEntersHandsFreeAndNextTapCommits() {
        _ = machine.handle(.fnDown, at: 0)
        _ = machine.handle(.fnUp, at: 0.1)
        #expect(machine.handle(.fnDown, at: 0.2) == [.enterHandsFree])
        #expect(machine.handle(.fnUp, at: 0.3) == [])
        #expect(machine.state == .handsFree)
        // Stale window timer must not cancel hands-free.
        #expect(machine.handle(.tapWindowElapsed(id: 1), at: 0.4) == [])
        #expect(machine.handle(.otherKey, at: 2) == [])
        #expect(machine.handle(.fnDown, at: 5) == [.commit])
        #expect(machine.handle(.fnUp, at: 5.1) == [])
        #expect(machine.state == .idle)
    }

    @Test mutating func fnComboCancels() {
        _ = machine.handle(.fnDown, at: 0)
        #expect(machine.handle(.otherKey, at: 0.5) == [.cancel])
        #expect(machine.handle(.fnUp, at: 0.6) == [])
        #expect(machine.state == .idle)
    }

    @Test mutating func escapeCancelsHandsFree() {
        _ = machine.handle(.fnDown, at: 0)
        _ = machine.handle(.fnUp, at: 0.1)
        _ = machine.handle(.fnDown, at: 0.2)
        _ = machine.handle(.fnUp, at: 0.3)
        #expect(machine.handle(.escape, at: 1) == [.cancel])
        #expect(machine.handle(.escape, at: 1.1) == [])
    }

    @Test mutating func staleTimerFromEarlierTapIsIgnored() {
        _ = machine.handle(.fnDown, at: 0)
        _ = machine.handle(.fnUp, at: 0.1) // tap id 1
        _ = machine.handle(.tapWindowElapsed(id: 1), at: 0.4)
        _ = machine.handle(.fnDown, at: 1)
        _ = machine.handle(.fnUp, at: 1.1) // tap id 2
        #expect(machine.handle(.tapWindowElapsed(id: 1), at: 1.2) == [])
        #expect(machine.handle(.tapWindowElapsed(id: 2), at: 1.4) == [.cancel])
    }

    @Test mutating func timeLimitCommitsHeldOrHandsFreeRecording() {
        _ = machine.handle(.fnDown, at: 0)
        #expect(machine.handle(.timeLimitReached, at: 300) == [.commit])
        #expect(machine.state == .idle)
        #expect(machine.handle(.timeLimitReached, at: 301) == [])

        _ = machine.handle(.fnDown, at: 400)
        _ = machine.handle(.fnUp, at: 400.1)
        _ = machine.handle(.fnDown, at: 400.2)
        _ = machine.handle(.fnUp, at: 400.3)
        #expect(machine.handle(.timeLimitReached, at: 700) == [.commit])
    }
}
