import XCTest
@testable import damus

final class InviteTests: XCTestCase {
    // Helper function to create a mock subscribe function
    private func createMockSubscribe() -> DoubleRatchet.NostrSubscribe {
        return { _, _ in { } }
    }
    
    func testCreateNewInvite() throws {
        let aliceKeypair = generate_new_keypair()
        let invite = try Invite.createNew(inviter: aliceKeypair.pubkey, label: "Test Invite", maxUses: 5)
        
        XCTAssertEqual(invite.inviterEphemeralPublicKey.hex().count, 64)
        XCTAssertEqual(invite.sharedSecret.count, 64)
        XCTAssertEqual(invite.inviter, aliceKeypair.pubkey)
        XCTAssertEqual(invite.label, "Test Invite")
        XCTAssertEqual(invite.maxUses, 5)
    }
    
    func testUrlGenerationAndParsing() throws {
        let aliceKeypair = generate_new_keypair()
        let invite = try Invite.createNew(inviter: aliceKeypair.pubkey, label: "Test Invite")
        
        let url = invite.getUrl()
        let parsedInvite = try Invite.fromUrl(URL(string: url)!)
        
        XCTAssertEqual(parsedInvite.inviterEphemeralPublicKey.hex(), invite.inviterEphemeralPublicKey.hex())
        XCTAssertEqual(parsedInvite.sharedSecret, invite.sharedSecret)
        XCTAssertEqual(parsedInvite.inviter.hex(), invite.inviter.hex())
    }
    
    func testAcceptInviteAndCreateSession() async throws {
        let aliceKeypair = generate_new_keypair()
        let invite = try Invite.createNew(inviter: aliceKeypair.pubkey)
        let bobKeypair = generate_new_keypair()
        
        let mockSubscribe = createMockSubscribe()
        
        let (session, event) = try await invite.accept(
            nostrSubscribe: mockSubscribe,
            inviteePublicKey: bobKeypair.pubkey,
            encryptor: bobKeypair.privkey
        )
        
        XCTAssertNotNil(session)
        XCTAssertNotNil(event)
        XCTAssertNotEqual(event.pubkey, bobKeypair.pubkey)
        XCTAssertEqual(event.kind, DoubleRatchet.Constants.INVITE_RESPONSE_KIND)
        XCTAssertEqual(event.tags[0][0].string(), "p")
        XCTAssertEqual(event.tags[0][1].string(), invite.inviterEphemeralPublicKey.hex())
    }
    
    func testListenForInviteAcceptances() async throws {
        let aliceKeypair = generate_new_keypair()
        let invite = try Invite.createNew(inviter: aliceKeypair.pubkey)
        let bobKeypair = generate_new_keypair()
        
        var messageQueue: [NostrEvent] = []
        
        let mockSubscribe: DoubleRatchet.NostrSubscribe = { filter, onEvent in
            print("Mock subscribe called for filter:", filter)
            
            // Create a task to continuously monitor the queue
            Task {
                while true {
                    if let index = messageQueue.firstIndex(where: { _ in true }) {
                        let event = messageQueue.remove(at: index)
                        onEvent(event)
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                }
            }
            
            return {}
        }
        
        let (_, acceptEvent) = try await invite.accept(
            nostrSubscribe: mockSubscribe,
            inviteePublicKey: bobKeypair.pubkey,
            encryptor: bobKeypair.privkey
        )
        
        let sessionExpectation = expectation(description: "Session created")
        var receivedSession: Session?
        var receivedIdentity: Pubkey?
        
        let unsubscribe = try invite.listen(
            decryptor: aliceKeypair.privkey,
            nostrSubscribe: mockSubscribe
        ) { session, identity in
            receivedSession = session
            receivedIdentity = identity
            sessionExpectation.fulfill()
        }
        
        messageQueue.append(acceptEvent)
        
        await waitForExpectations(timeout: 5)
        
        XCTAssertNotNil(receivedSession)
        XCTAssertEqual(receivedIdentity, bobKeypair.pubkey)
        
        unsubscribe()
    }
    
    func testEventConversion() throws {
        let aliceKeypair = generate_new_keypair()
        let invite = try Invite.createNew(inviter: aliceKeypair.pubkey, label: "Test Invite", maxUses: 5)
        
        let event = invite.getEvent(keypair: aliceKeypair)
        
        XCTAssertEqual(event.kind, DoubleRatchet.Constants.INVITE_EVENT_KIND)
        XCTAssertEqual(event.pubkey.hex(), aliceKeypair.pubkey.hex())
        
        // Find the ephemeral key tag
        let ephemeralKeyTag = event.tags.first { tag in
            tag.count > 0 && tag[0].string() == "ephemeralKey"
        }
        XCTAssertNotNil(ephemeralKeyTag)
        XCTAssertEqual(ephemeralKeyTag?[1].string(), invite.inviterEphemeralPublicKey.hex())
        
        // Find the shared secret tag
        let sharedSecretTag = event.tags.first { tag in
            tag.count > 0 && tag[0].string() == "sharedSecret"
        }
        XCTAssertNotNil(sharedSecretTag)
        XCTAssertEqual(sharedSecretTag?[1].string(), invite.sharedSecret)
        
        let parsedInvite = try Invite.fromEvent(event)
        
        // Add debug output
        print("Original ephemeral key: \(invite.inviterEphemeralPublicKey.hex())")
        print("Parsed ephemeral key: \(parsedInvite.inviterEphemeralPublicKey.hex())")
        
        XCTAssertEqual(parsedInvite.inviterEphemeralPublicKey.hex(), invite.inviterEphemeralPublicKey.hex())
        XCTAssertEqual(parsedInvite.sharedSecret, invite.sharedSecret)
        XCTAssertEqual(parsedInvite.inviter.hex(), invite.inviter.hex())
    }
} 