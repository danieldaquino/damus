//
//  NostrNetworkManagerTests.swift
//  damus
//
//  Created by Daniel D'Aquino on 2025-08-22.
//

import XCTest
@testable import damus


class NostrNetworkManagerTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testBasicEventReading() {
        let expectation1 = XCTestExpectation(description: "Event should not be on ndb before process event")
        let expectation2 = XCTestExpectation(description: "Found event id on ndb")
        let expectation3 = XCTestExpectation(description: "Received expected event id on stream")
        
        let expectedEventId = "f4a5635d78d4c1ec2bf7d15d33bd8d5e0afdb8a5a24047f095842281c744e6a3"
        let testNoteText = """
        {"id":"\(expectedEventId)","created_at":1753898578,"content":"Test 1102","kind":1,"pubkey":"056b5b5966f500defb3b790a14633e5ec4a0e8883ca29bc23d0030553edb084a","sig":"d03f0beee7355a8b6ce437b43e01f2d3be8c0f3f17b41a8dec8a9b9804d44ab639b7906c545e4b51820f00b09d00cfa5058916e93126e8a11a65e2623f95f152","tags":[]}
        """
        let damusState = generate_test_damus_state(
            mock_profile_info: nil
        )
        Task {
            if await damusState.nostrNetwork.findEvent(query: .event(evid: NoteId(hex: expectedEventId)!)) == nil {
                expectation1.fulfill()
            }
        }
        let mainTask = Task {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let _ = damusState.ndb.process_event(testNoteText)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            if let result = await damusState.nostrNetwork.findEvent(query: .event(evid: NoteId(hex: expectedEventId)!)) {
                expectation2.fulfill()
            }
            
            let filter = NostrFilter(pubkeys: [Pubkey(hex: "056b5b5966f500defb3b790a14633e5ec4a0e8883ca29bc23d0030553edb084a")!])
            for await item in damusState.nostrNetwork.reader.subscribe(filters: [filter]) {
                switch item {
                case .event(borrow: let borrow):
                    var found = false
                    try? borrow { event in
                        if event.id == NoteId(hex: expectedEventId) {
                            found = true
                            expectation3.fulfill()
                        }
                    }
                    if found { break }
                case .eose:
                    // End of stream, break out of the loop
                    break
                }
            }
        }
        wait(for: [expectation1, expectation2, expectation3], timeout: 7.0)
        mainTask.cancel()
    }
}
