//
//  UniqueInsertSortTests.swift
//  damusTests
//
//  Created by Daniel D'Aquino on 2024-12-13.
//

import Foundation
@testable import damus
import XCTest

struct TestObject: Identifiable {
    typealias ID = Int
    var id: ID
    var value: Int
}

class TestObjectTests: XCTestCase {

    func testInsertIntoEmptyArray() {
        var testObjects: [TestObject] = []
        let newObject = TestObject(id: 1, value: 100)
        XCTAssertTrue(insert_unique_sorted_for_presorted_items(items: &testObjects, new_item: newObject) {$0.value < $1.value})
        XCTAssertEqual(testObjects.count, 1)
        XCTAssertEqual(testObjects.first?.id, newObject.id)
        XCTAssertEqual(testObjects.first?.value, newObject.value)
    }
    
    func testInsertAtBeginning() {
        var testObjects = [
            TestObject(id: 2, value: 200),
            TestObject(id: 3, value: 300)
        ]
        let newObject = TestObject(id: 1, value: 100)
        XCTAssertTrue(insert_unique_sorted_for_presorted_items(items: &testObjects, new_item: newObject) {$0.value < $1.value})
        XCTAssertEqual(testObjects.count, 3)
        XCTAssertEqual(testObjects.first?.id, 1)
        XCTAssertEqual(testObjects.first?.value, 100)
    }
    
    func testInsertAtEnd() {
        var testObjects = [
            TestObject(id: 1, value: 100),
            TestObject(id: 2, value: 200)
        ]
        let newObject = TestObject(id: 3, value: 300)
        XCTAssertTrue(insert_unique_sorted_for_presorted_items(items: &testObjects, new_item: newObject) {$0.value < $1.value})
        XCTAssertEqual(testObjects.count, 3)
        XCTAssertEqual(testObjects.last?.id, 3)
        XCTAssertEqual(testObjects.last?.value, 300)
    }
    
    func testInsertInMiddle() {
        var testObjects = [
            TestObject(id: 1, value: 100),
            TestObject(id: 3, value: 300)
        ]
        let newObject = TestObject(id: 2, value: 200)
        XCTAssertTrue(insert_unique_sorted_for_presorted_items(items: &testObjects, new_item: newObject) {$0.value < $1.value})
        XCTAssertEqual(testObjects.count, 3)
        XCTAssertEqual(testObjects[1].id, 2)
        XCTAssertEqual(testObjects[1].value, 200)
    }
    
    func testPreventDuplicateInsertions() {
        var testObjects = [
            TestObject(id: 1, value: 100),
            TestObject(id: 2, value: 200)
        ]
        let duplicateObject = TestObject(id: 2, value: 250) // Different value, but same id should not be inserted
        XCTAssertFalse(insert_unique_sorted_for_presorted_items(items: &testObjects, new_item: duplicateObject) {$0.value < $1.value})
        XCTAssertEqual(testObjects.count, 2) // No new insertion should happen
        XCTAssertEqual(testObjects[1].value, 200) // The second object's value should remain unchanged as duplicate was not inserted
    }
    
    func testInsertIntoLargerArray() {
        // Create an array of objects with ids from 1 to 12, excluding an id of 7 to test insertion there
        var testObjects: [TestObject] = (1...12).filter { $0 != 7 }.map { TestObject(id: $0, value: $0 * 100) }
        
        // TestObject to be inserted
        let newObject = TestObject(id: 7, value: 700)
        
        // Execute insertion
        XCTAssertTrue(insert_unique_sorted_for_presorted_items(items: &testObjects, new_item: newObject) { $0.value < $1.value })
        
        // Verification that the array has now a new element
        XCTAssertEqual(testObjects.count, 12)
        
        // Verify order is maintained and new object is correctly placed
        for i in 0..<testObjects.count {
            XCTAssertEqual(testObjects[i].id, i + 1)
            XCTAssertEqual(testObjects[i].value, (i + 1) * 100)
        }
        
        // Ensure the inserted object is exactly where expected
        XCTAssertEqual(testObjects[6].id, 7)
        XCTAssertEqual(testObjects[6].value, 700)
    }
    
    func testInsertIntoLargerOddNumberedArray() {
        // Create an array of objects with ids from 1 to 11, excluding an id of 7 to test insertion there
        var testObjects: [TestObject] = (1...11).filter { $0 != 7 }.map { TestObject(id: $0, value: $0 * 100) }
        
        // TestObject to be inserted
        let newObject = TestObject(id: 7, value: 700)
        
        // Execute insertion
        XCTAssertTrue(insert_unique_sorted_for_presorted_items(items: &testObjects, new_item: newObject) { $0.value < $1.value })
        
        // Verification that the array has now a new element
        XCTAssertEqual(testObjects.count, 11)
        
        // Verify order is maintained and new object is correctly placed
        for i in 0..<testObjects.count {
            XCTAssertEqual(testObjects[i].id, i + 1)
            XCTAssertEqual(testObjects[i].value, (i + 1) * 100)
        }
        
        // Ensure the inserted object is exactly where expected
        XCTAssertEqual(testObjects[6].id, 7)
        XCTAssertEqual(testObjects[6].value, 700)
    }
}
