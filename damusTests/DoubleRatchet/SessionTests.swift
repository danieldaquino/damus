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
            sharedSecret: Data("testSharedSecret".utf8),
            nostrSubscribe: mockSubscribe,
            name: "alice"
        )
        
        XCTAssertEqual(alice.state.theirNextNostrPublicKey, bobKeypair.pubkey)
        XCTAssertEqual(alice.state.ourCurrentNostrKey?.pubkey, aliceKeypair.pubkey)
        XCTAssertEqual(alice.state.ourCurrentNostrKey?.pubkey.hex().count, 64)

        let bob = try Session.initialize(
            theirEphemeralNostrPublicKey: aliceKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(bobKeypair.privkey.id),
            isInitiator: false,
            sharedSecret: Data("testSharedSecret".utf8),
            nostrSubscribe: mockSubscribe,
            name: "bob"
        )

        XCTAssertEqual(bob.state.theirNextNostrPublicKey, aliceKeypair.pubkey)
        XCTAssertEqual(bob.state.ourCurrentNostrKey, nil)
        XCTAssertEqual(bob.state.ourNextNostrKey.pubkey, bobKeypair.pubkey)
    }
    
    func testCreateEventWithCorrectProperties() throws {
        let aliceKeypair = generate_new_keypair()
        let bobKeypair = generate_new_keypair()
        
        let mockSubscribe = createMockSubscribe()
        
        let aliceSession = try Session.initialize(
            theirEphemeralNostrPublicKey: bobKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(aliceKeypair.privkey.id),
            isInitiator: true,
            sharedSecret: Data("testSharedSecret".utf8),
            nostrSubscribe: mockSubscribe,
            name: "alice"
        )

        let testData = "Hello, world!"
        let (event, _) = try aliceSession.sendText(testData)
        
        XCTAssertNotNil(event)
        XCTAssertEqual(event.kind, DoubleRatchet.Constants.MESSAGE_EVENT_KIND)
        XCTAssertEqual(event.tags[0][0].string(), "header")
        XCTAssertNotNil(event.tags[0][1])
        XCTAssertNotNil(event.content)
        XCTAssertGreaterThan(event.created_at, 0)
        XCTAssertEqual(event.pubkey.hex().count, 64)
        XCTAssertNotEqual(event.pubkey.hex(), aliceKeypair.pubkey.hex())
        XCTAssertEqual(event.id.hex().count, 64)
        XCTAssertEqual(event.sig.data.count, 64)
    }
    
    func testHandleIncomingEventsAndUpdateKeys() async throws {
        var messageQueue: [NostrEvent] = []
        
        let mockSubscribe: DoubleRatchet.NostrSubscribe = { filter, onEvent in
            print("Mock subscribe called for filter:", filter)
            
            // Create a task to continuously monitor the queue
            Task {
                while true {
                    if let index = messageQueue.firstIndex(where: { _ in true }) {
                        let event = messageQueue.remove(at: index)
                        print("Processing event from queue:", event.id.hex().prefix(8))
                        onEvent(event)
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                }
            }
            
            return {}
        }
        
        let aliceKeypair = generate_new_keypair()
        let bobKeypair = generate_new_keypair()
        
        let alice = try Session.initialize(
            theirEphemeralNostrPublicKey: bobKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(aliceKeypair.privkey.id),
            isInitiator: true,
            sharedSecret: Data("testSharedSecret".utf8),
            nostrSubscribe: mockSubscribe,
            name: "alice"
        )
        
        let bob = try Session.initialize(
            theirEphemeralNostrPublicKey: aliceKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(bobKeypair.privkey.id),
            isInitiator: false,
            sharedSecret: Data("testSharedSecret".utf8),
            nostrSubscribe: mockSubscribe,
            name: "bob"
        )
        
        let initialReceivingChainKey = bob.state.receivingChainKey
        
        var bobMessages = DoubleRatchet.createEventStream(bob).makeAsyncIterator()
        
        let (event, _) = try alice.sendText("Hello, Bob!")
        print("Adding Alice's event to queue:", event.id.hex().prefix(8))
        messageQueue.append(event)
        
        // Wait for Bob to receive
        print("Waiting for Bob to receive message...")
        let bobReceived = await bobMessages.next()
        XCTAssertEqual(bobReceived?.content, "Hello, Bob!")
        XCTAssertNotEqual(bob.state.receivingChainKey, initialReceivingChainKey)
    }
    
    func testMultipleBackAndForthMessages() async throws {
        var messageQueue: [NostrEvent] = []
        
        let mockSubscribe: DoubleRatchet.NostrSubscribe = { filter, onEvent in
            print("Mock subscribe called for filter:", filter)
            
            // Create a task to continuously monitor the queue
            Task {
                while true {
                    if let index = messageQueue.firstIndex(where: { _ in true }) {
                        let event = messageQueue.remove(at: index)
                        print("Processing event from queue:", event.id.hex().prefix(8))
                        onEvent(event)
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                }
            }
            
            return {}
        }
        
        let aliceKeypair = generate_new_keypair()
        let bobKeypair = generate_new_keypair()
        
        let alice = try Session.initialize(
            theirEphemeralNostrPublicKey: bobKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(aliceKeypair.privkey.id),
            isInitiator: true,
            sharedSecret: Data("testSharedSecret".utf8),
            nostrSubscribe: mockSubscribe,
            name: "alice"
        )
        
        let bob = try Session.initialize(
            theirEphemeralNostrPublicKey: aliceKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(bobKeypair.privkey.id),
            isInitiator: false,
            sharedSecret: Data("testSharedSecret".utf8),
            nostrSubscribe: mockSubscribe,
            name: "bob"
        )
        
        var bobMessages = DoubleRatchet.createEventStream(bob).makeAsyncIterator()
        var aliceMessages = DoubleRatchet.createEventStream(alice).makeAsyncIterator()
        
        // Alice sends to Bob
        let (aliceEvent, _) = try alice.sendText("Hello Bob!")
        print("Adding Alice's event to queue:", aliceEvent.id.hex().prefix(8))
        messageQueue.append(aliceEvent)
        
        // Wait for Bob to receive
        print("Waiting for Bob to receive message...")
        let bobReceived = await bobMessages.next()
        XCTAssertEqual(bobReceived?.content, "Hello Bob!")
        
        // Now Bob can reply
        let (bobEvent, _) = try bob.sendText("Hi Alice!")
        print("Adding Bob's event to queue:", bobEvent.id.hex().prefix(8))
        messageQueue.append(bobEvent)
        
        // Wait for Alice to receive
        print("Waiting for Alice to receive message...")
        let aliceReceived = await aliceMessages.next()
        XCTAssertEqual(aliceReceived?.content, "Hi Alice!")
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
            sharedSecret: Data("testSharedSecret".utf8),
            nostrSubscribe: mockSubscribe,
            name: "alice"
        )
        
        let bob = try Session.initialize(
            theirEphemeralNostrPublicKey: aliceKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(bobKeypair.privkey.id),
            isInitiator: false,
            sharedSecret: Data("testSharedSecret".utf8),
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
            sharedSecret: Data("testSharedSecret".utf8),
            nostrSubscribe: mockSubscribe,
            name: "alice"
        )
        
        var bob = try Session.initialize(
            theirEphemeralNostrPublicKey: aliceKeypair.pubkey,
            ourEphemeralNostrPrivateKey: Privkey(bobKeypair.privkey.id),
            isInitiator: false,
            sharedSecret: Data("testSharedSecret".utf8),
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
