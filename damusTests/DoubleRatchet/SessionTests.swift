import XCTest
import secp256k1
@testable import damus

final class SessionTests: XCTestCase {
    
    // Helper function to create a mock subscribe function
    private func createMockSubscribe() -> DoubleRatchet.NostrSubscribe {
        return { _, _ in { } }
    }
    
    func testInitializeWithCorrectProperties() throws {
        let aliceKeypair = generate_new_keypair()
        let bobKeypair = generate_new_keypair()
        
        let mockSubscribe = createMockSubscribe()
        
        let alice = try Session.initialize(
            theirEphemeralNostrPublicKey: bobKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(aliceKeypair.privkey.id),
            isInitiator: true,
            sharedSecret: Data(),
            nostrSubscribe: mockSubscribe,
            name: "alice"
        )
        
        XCTAssertEqual(alice.state.theirNextNostrPublicKey, bobKeypair.pubkey)
        XCTAssertEqual(alice.state.ourCurrentNostrKey?.pubkey, aliceKeypair.pubkey)
        XCTAssertEqual(alice.state.ourCurrentNostrKey?.pubkey.hex().count, 64)
    }
    
    func testCreateEventWithCorrectProperties() throws {
        let aliceKeypair = generate_new_keypair()
        let bobKeypair = generate_new_keypair()
        
        let mockSubscribe = createMockSubscribe()
        
        let session = try Session.initialize(
            theirEphemeralNostrPublicKey: bobKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(aliceKeypair.privkey.id),
            isInitiator: true,
            sharedSecret: Data(),
            nostrSubscribe: mockSubscribe,
            name: "alice"
        )
        
        let testData = "Hello, world!"
        let (event, _) = try session.sendText(testData)
        
        XCTAssertNotNil(event)
        XCTAssertEqual(event.kind, DoubleRatchet.Constants.MESSAGE_EVENT_KIND)
        XCTAssertEqual(event.tags[0][0].string(), "header")
        XCTAssertNotNil(event.tags[0][1])
        XCTAssertNotNil(event.content)
        XCTAssertGreaterThan(event.created_at, 0)
        XCTAssertEqual(event.pubkey.hex().count, 64)
        XCTAssertEqual(event.id.hex().count, 64)
        XCTAssertEqual(event.sig.data.count, 64)
    }
    
    func testHandleIncomingEventsAndUpdateKeys() async throws {
        var messageQueue: [NostrEvent] = []
        
        let mockSubscribe: DoubleRatchet.NostrSubscribe = { filter, onEvent in
            if let index = messageQueue.firstIndex(where: { _ in true }) {
                let event = messageQueue.remove(at: index)
                onEvent(event)
            }
            return {}
        }
        
        let aliceKeypair = generate_new_keypair()
        let bobKeypair = generate_new_keypair()
        
        let alice = try Session.initialize(
            theirEphemeralNostrPublicKey: bobKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(aliceKeypair.privkey.id),
            isInitiator: true,
            sharedSecret: Data(),
            nostrSubscribe: mockSubscribe,
            name: "alice"
        )
        
        let bob = try Session.initialize(
            theirEphemeralNostrPublicKey: aliceKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(bobKeypair.privkey.id),
            isInitiator: false,
            sharedSecret: Data(),
            nostrSubscribe: mockSubscribe,
            name: "bob"
        )
        
        let initialReceivingChainKey = bob.state.receivingChainKey
        
        let expectation = XCTestExpectation(description: "Message received")
        var receivedMessage: String?
        
        _ = bob.onEvent { rumor, _ in
            receivedMessage = rumor.content
            expectation.fulfill()
        }
        
        let (event, _) = try alice.sendText("Hello, Bob!")
        messageQueue.append(event)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(receivedMessage, "Hello, Bob!")
        XCTAssertNotEqual(bob.state.receivingChainKey, initialReceivingChainKey)
    }
    
    func testMultipleBackAndForthMessages() async throws {
        var messageQueue: [NostrEvent] = []
        
        let mockSubscribe: DoubleRatchet.NostrSubscribe = { filter, onEvent in
            if let index = messageQueue.firstIndex(where: { _ in true }) {
                let event = messageQueue.remove(at: index)
                onEvent(event)
            }
            return {}
        }
        
        let aliceKeypair = generate_new_keypair()
        let bobKeypair = generate_new_keypair()
        
        let alice = try Session.initialize(
            theirEphemeralNostrPublicKey: bobKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(aliceKeypair.privkey.id),
            isInitiator: true,
            sharedSecret: Data(),
            nostrSubscribe: mockSubscribe,
            name: "alice"
        )
        
        let bob = try Session.initialize(
            theirEphemeralNostrPublicKey: aliceKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(bobKeypair.privkey.id),
            isInitiator: false,
            sharedSecret: Data(),
            nostrSubscribe: mockSubscribe,
            name: "bob"
        )
        
        let aliceExpectation = XCTestExpectation(description: "Alice received message")
        let bobExpectation = XCTestExpectation(description: "Bob received message")
        
        var aliceReceivedMessage: String?
        var bobReceivedMessage: String?
        
        _ = alice.onEvent { rumor, _ in
            aliceReceivedMessage = rumor.content
            aliceExpectation.fulfill()
        }
        
        _ = bob.onEvent { rumor, _ in
            bobReceivedMessage = rumor.content
            bobExpectation.fulfill()
        }
        
        // Alice sends to Bob
        let (aliceEvent, _) = try alice.sendText("Hello Bob!")
        messageQueue.append(aliceEvent)
        
        await fulfillment(of: [bobExpectation], timeout: 1.0)
        XCTAssertEqual(bobReceivedMessage, "Hello Bob!")
        
        // Bob replies to Alice
        let (bobEvent, _) = try bob.sendText("Hi Alice!")
        messageQueue.append(bobEvent)
        
        await fulfillment(of: [aliceExpectation], timeout: 1.0)
        XCTAssertEqual(aliceReceivedMessage, "Hi Alice!")
    }
    
    func testOutOfOrderMessageDelivery() async throws {
        var messageQueue: [NostrEvent] = []
        
        let mockSubscribe: DoubleRatchet.NostrSubscribe = { filter, onEvent in
            if let index = messageQueue.firstIndex(where: { _ in true }) {
                let event = messageQueue.remove(at: index)
                onEvent(event)
            }
            return {}
        }
        
        let aliceKeypair = generate_new_keypair()
        let bobKeypair = generate_new_keypair()
        
        let alice = try Session.initialize(
            theirEphemeralNostrPublicKey: bobKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(aliceKeypair.privkey.id),
            isInitiator: true,
            sharedSecret: Data(),
            nostrSubscribe: mockSubscribe,
            name: "alice"
        )
        
        let bob = try Session.initialize(
            theirEphemeralNostrPublicKey: aliceKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(bobKeypair.privkey.id),
            isInitiator: false,
            sharedSecret: Data(),
            nostrSubscribe: mockSubscribe,
            name: "bob"
        )
        
        var bobMessages = DoubleRatchet.createEventStream(bob).makeAsyncIterator()
        
        // Create messages
        let (message1, _) = try alice.sendText("Message 1")
        let (message2, _) = try alice.sendText("Message 2")
        let (message3, _) = try alice.sendText("Message 3")
        
        // Deliver out of order
        messageQueue.append(message3)
        let receivedMessage3 = await bobMessages.next()
        XCTAssertEqual(receivedMessage3?.content, "Message 3")
        
        // Deliver skipped messages
        messageQueue.append(message1)
        messageQueue.append(message2)
        
        let receivedMessage1 = await bobMessages.next()
        XCTAssertEqual(receivedMessage1?.content, "Message 1")
        
        let receivedMessage2 = await bobMessages.next()
        XCTAssertEqual(receivedMessage2?.content, "Message 2")
    }
    
    func testSessionSerialization() async throws {
        var messageQueue: [NostrEvent] = []
        
        let mockSubscribe: DoubleRatchet.NostrSubscribe = { filter, onEvent in
            if let index = messageQueue.firstIndex(where: { _ in true }) {
                let event = messageQueue.remove(at: index)
                onEvent(event)
            }
            return {}
        }
        
        let aliceKeypair = generate_new_keypair()
        let bobKeypair = generate_new_keypair()
        
        let alice = try Session.initialize(
            theirEphemeralNostrPublicKey: bobKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(aliceKeypair.privkey.id),
            isInitiator: true,
            sharedSecret: Data(),
            nostrSubscribe: mockSubscribe,
            name: "alice"
        )
        
        var bob = try Session.initialize(
            theirEphemeralNostrPublicKey: aliceKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(bobKeypair.privkey.id),
            isInitiator: false,
            sharedSecret: Data(),
            nostrSubscribe: mockSubscribe,
            name: "bob"
        )
        
        var bobMessages = DoubleRatchet.createEventStream(bob).makeAsyncIterator()
        
        // Initial message exchange
        let (message1, _) = try alice.sendText("Message 1")
        messageQueue.append(message1)
        let receivedMessage1 = await bobMessages.next()
        XCTAssertEqual(receivedMessage1?.content, "Message 1")
        
        // Serialize bob's state
        let serializedBob = try DoubleRatchet.serializeSessionState(bob.state)
        bob.close()
        
        // Create new session with serialized state
        bob = Session(
            state: try DoubleRatchet.deserializeSessionState(serializedBob),
            nostrSubscribe: mockSubscribe,
            name: "bobRestored"
        )
        bobMessages = DoubleRatchet.createEventStream(bob).makeAsyncIterator()
        
        // Continue conversation
        let (message2, _) = try alice.sendText("Message 2")
        messageQueue.append(message2)
        let receivedMessage2 = await bobMessages.next()
        XCTAssertEqual(receivedMessage2?.content, "Message 2")
    }
}

// MARK: - Helper Functions

func createEventStream(_ session: Session) -> AsyncStream<DoubleRatchet.Rumor> {
    var continuation: AsyncStream<DoubleRatchet.Rumor>.Continuation?
    
    let stream = AsyncStream<DoubleRatchet.Rumor> { cont in
        continuation = cont
        
        let unsubscribe = session.onEvent { rumor, _ in
            continuation?.yield(rumor)
        }
        
        cont.onTermination = { _ in
            unsubscribe()
        }
    }
    
    return stream
}
