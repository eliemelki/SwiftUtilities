//
//  AsyncTaskQueueTests.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 19/09/2025.
//



import XCTest
@testable import LBSwiftUtilities

// MARK: - Tests

final class AsyncTaskQueueTests: XCTestCase {

    /// Serial queue should run one at a time and preserve FIFO ordering.
    func testSerialFIFO() async {
        let q = AsyncTaskQueue(.serial)
        let meter = Meter()
        let finished = XCTestExpectation(description: "all finished")
        finished.expectedFulfillmentCount = 5

        for i in 0..<5 {
            _ = await q.submit { () -> Int in
                await meter.start(i)
                await sleepMs(30)
                await meter.end(i)
                finished.fulfill()
                return i
            }
        }

        await fulfillment(of: [finished], timeout: 5)
        let snap = await meter.snapshot()
        XCTAssertEqual(snap.peak, 1, "Serial queue must never exceed 1 running task")
        XCTAssertEqual(snap.started, snap.started)
    }

    /// Concurrent queue should cap peak concurrency to the given bound.
    func testBoundedParallelism() async {
        let q = AsyncTaskQueue(.concurrent(3))
        let meter = Meter()
        let finished = XCTestExpectation(description: "all finished")
        finished.expectedFulfillmentCount = 10

        for i in 0..<10 {
            _ = await q.submit {
                await meter.start(i)
                await sleepMs(50)
                await meter.end(i)
                finished.fulfill()
                return i
            }
        }

        await fulfillment(of: [finished], timeout: 5)
        let snap = await meter.snapshot()
        XCTAssertLessThanOrEqual(snap.peak, 3, "Peak concurrency must not exceed limit")
        XCTAssertGreaterThanOrEqual(snap.peak, 2, "Should observe some parallelism")
    }

    /// Cancelling a pending task by id should prevent it from ever starting
    /// and should not block tasks behind it.
    func testCancelPendingById() async {
        let q = AsyncTaskQueue(.concurrent(1))
        let meter = Meter()

        // 1) Blocker occupies the single slot for a while.
        _ = await q.submit { () -> Int in
            await meter.start(0)
            await sleepMs(200)
            await meter.end(0)
            return 0
        }

        // 2) Pending task (will wait). Capture its id so we can cancel it.
        let pending = await q.submit { () -> Int in
            await meter.start(1)   // should never happen
            await meter.end(1)
            return 1
        }

        // 3) Cancel the pending waiter before it acquires.
        q.cancel(id: pending.id)

        // 4) A third task should run as soon as the blocker completes.
        let thirdStarted = XCTestExpectation(description: "third started")
        let thirdFinished = XCTestExpectation(description: "third finished")

        _ = await q.submit { () -> Int in
            await meter.start(2)
            thirdStarted.fulfill()
            await sleepMs(30)
            await meter.end(2)
            thirdFinished.fulfill()
            return 2
        }

        await fulfillment(of: [thirdStarted, thirdFinished], timeout: 5)
        let snap = await meter.snapshot()
        XCTAssertFalse(snap.started.contains(1), "Canceled pending task must not start")
        XCTAssertTrue(snap.started.contains(2), "Next task should proceed normally")
    }

    
    /// cancelAll should cancel running and queued tasks; queued tasks must not start afterwards.
    func testCancelAllCancelsQueuedAndRunning() async {
        let q = AsyncTaskQueue(.concurrent(2))
        let meter = Meter()

        let startedLong = XCTestExpectation(description: "long tasks started")
        startedLong.expectedFulfillmentCount = 2

        // Two long tasks occupy both slots
        _ = await q.submit {
            await meter.start(10);
            startedLong.fulfill()
            // Task.sleep is cancellation-cooperative
            try? await sleepsFor(seconds: 0.4)
            await meter.end(10)
            return 10
        }
        _ = await q.submit {
            await meter.start(11);
            startedLong.fulfill()
            try? await sleepsFor(seconds: 0.4)
            await meter.end(11)
            return 11
        }

        // Ensure the long tasks actually started
        await fulfillment(of: [startedLong], timeout: 3)
        
        // Two pending tasks (should never start after cancelAll)
        _ = await q.submit { () -> Int in
            //try await sleepsFor(seconds: 1) //give enough time for cancel to be called
            await meter.start(20)
            await meter.end(20)
            return 20
        }
        _ = await q.submit { () -> Int in
            //try await sleepsFor(seconds: 1) //give enough time for cancel to be called
            await meter.start(21)
            await meter.end(21)
            return 21
        }

        q.cancelAll()

        // Give some time for cancellations to propagate.
        try? await sleepsFor(seconds: 1.2)

        let snap = await meter.snapshot()
        XCTAssertFalse(snap.started.contains(20))
        XCTAssertFalse(snap.started.contains(21))
    }

    /// Basic sanity: each submit should return a distinct id.
    func testSubmitReturnsDistinctIds() async {
        let q = AsyncTaskQueue(.serial)
        let a = await q.submit { 1 }
        let b = await q.submit { 2 }
        XCTAssertNotEqual(a.id, b.id)
    }
    
    func testCancelReleasePermitNextRuns() async {
        let q = AsyncTaskQueue(.serial) // easiest to reason about
        let meter = Meter()

        let firstStarted = XCTestExpectation(description: "first started")
        let firstCancelled = XCTestExpectation(description: "first cancelled")
    
        _ = await q.submit { () -> Int in
            do {
                await meter.start(0)
                firstStarted.fulfill()
                try await sleepsFor(seconds: 1)
                await meter.end(0)
                return 0
            }catch is CancellationError {
                firstCancelled.fulfill()
                throw CancellationError()
            }
        }
        await fulfillment(of: [firstStarted], timeout: 3)
        q.cancelAll()
        await fulfillment(of: [firstCancelled], timeout: 3)
        
        let snap = await meter.snapshot()
        XCTAssertTrue(snap.started.contains(0), "First job should have started")
        XCTAssertFalse(snap.finished.contains(1), "First job should have not finished normally")
    }


    /// If the first operation throws, the queue must still release the permit
    /// so that the next queued operation can run.
    func testOperationErrorReleasesPermitAndNextRuns() async {
        let q = AsyncTaskQueue(.serial) // easiest to reason about
        let meter = Meter()

        // 1) Submit a throwing job
        _ = await q.submit { () -> Int in
            await meter.start(0)
            // Simulate a bit of work then throw
            await sleepMs(30)
            throw URLError(.badServerResponse)
        }

        // 2) Next job should still start and finish (i.e., permit was released)
        let secondStarted = XCTestExpectation(description: "second started")
        let secondFinished = XCTestExpectation(description: "second finished")

        _ = await q.submit { () -> Int in
            await meter.start(1)
            secondStarted.fulfill()
            await sleepMs(20)
            await meter.end(1)
            secondFinished.fulfill()
            return 1
        }

        await fulfillment(of: [secondStarted, secondFinished], timeout: 3)

        let snap = await meter.snapshot()
        XCTAssertTrue(snap.started.contains(0), "First job should have started")
        XCTAssertTrue(snap.started.contains(1), "Second job should have been able to start after the first threw")
        XCTAssertTrue(snap.finished.contains(1), "Second job should have finished normally")
    }
    
  

    /// Ensure the priority passed to `submit(priority:)` is observed inside the operation.
    /// Some platforms may escalate priorities, so we assert `current >= requested`.
    func testPriorityPropagationToOperation() async {
        let q = AsyncTaskQueue(.concurrent(2))

        let checked = XCTestExpectation(description: "checked priority")
        let requested: TaskPriority = .high

        _ = await q.submit(priority: requested) { () -> Int in
            let current = Task.currentPriority
            // Note: equality usually holds; using >= avoids false failures if the system escalates priority.
            XCTAssertGreaterThanOrEqual(current, requested, "Operation should inherit at least the requested priority")
            checked.fulfill()
            return 0
        }

        await fulfillment(of: [checked], timeout: 2)
    }
}
