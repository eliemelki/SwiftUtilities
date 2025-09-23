//
//  TaskBagTests.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 18/09/2025.
//


// TaskBagTests.swift
import XCTest
@testable import LBSwiftUtilities

final class TaskBagTests: XCTestCase {
    
    
    func testAddThenCancelCancelsExactlyOnce() async {
        let bag = TaskBag()

        
        let t = await bag.add(id: UUID(), task: Task {})
        await bag.cancel(id: t.id)
        var count = await bag.count()
        XCTAssertEqual(count, 0)
        // Second cancel should be a no-op (task was removed on cancel)
        await bag.cancel(id: t.id)
        count = await bag.count()
        XCTAssertEqual(count, 0)
    }
    
    func testRemovePreventsFutureCancel() async {
        let bag = TaskBag()
        let t = await bag.add(id: UUID(), task: Task {})
        await bag.remove(id: t.id)
        var count = await bag.count()
        XCTAssertEqual(count, 0, "already removed")
        await bag.cancel(id: t.id)
        count = await bag.count()
        XCTAssertEqual(count, 0, "Removed task should not be canceled")
    }
    
    func testCancelFromTask() async {
        let bag = TaskBag()
        let a = await bag.add(id: UUID(), task: Task {})
        let b = await bag.add(id: UUID(), task: Task {})
        let c = await bag.add(id: UUID(), task: Task {})
        
    
        var count = await bag.count()
        XCTAssertEqual(count, 3)
        
        await a.cancel()
        count = await bag.count()
        let aExist = await bag.contains(task: a)
        let bExist = await bag.contains(task: b)
        var cExist = await bag.contains(task: c)
        XCTAssertEqual(count, 2)
        XCTAssertFalse(aExist)
        XCTAssertTrue(bExist)
        XCTAssertTrue(cExist)
        
        await c.cancel()
        cExist = await bag.contains(task: c)
        count = await bag.count()
        XCTAssertEqual(count, 1)
        XCTAssertFalse(cExist)
        
    }
    
    func testCancelAllCancelsRemainingAndEmptiesBag() async {
        let bag = TaskBag()
        _ = await bag.add(id: UUID(), task: Task {})
        _ = await bag.add(id: UUID(), task: Task {})
        var count = await bag.count()
        XCTAssertEqual(count, 2)
        _ = await bag.add(id: UUID(), task: Task {})
        
        await bag.cancelAll()
        count = await bag.count()
        XCTAssertEqual(count, 0)
        
        // Bag should now be empty; a second cancelAll should not call cancel again.
        await bag.cancelAll()
        count = await bag.count()
        XCTAssertEqual(count, 0)
    }
    
    func testCancelUnknownIdDoesNothing() async {
        let bag = TaskBag()
        _ = await bag.add(id: UUID(), task: Task {})
        await bag.cancel(id: UUID()) // unknown
        
        let count = await bag.count()
        XCTAssertEqual(count, 1)
    }
    
    func testAddingDuplicateIdOverridesPrevious() async {
        let bag = TaskBag()
        let sharedID = UUID()
        _ = await bag.add(id: sharedID, task: Task {})
        _ = await bag.add(id: sharedID, task: Task {})
        
          
        await bag.cancel(id: sharedID)
        let count = await bag.count()
        XCTAssertEqual(count, 0)
    }
    
}
