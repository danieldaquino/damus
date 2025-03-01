//
//  Invite.swift
//  damus
//
//  Created by Martti Malmi on 28.2.2025.
//

import Foundation

class Invite {
    let inviterEphemeralPublicKey: Pubkey
    let sharedSecret: String
    let inviter: Pubkey
    let inviterEphemeralPrivateKey: Privkey?
    let label: String?
    let maxUses: Int?
    var usedBy: [Pubkey]
    
    private static let TWO_DAYS: TimeInterval = 2 * 24 * 60 * 60
    
    init(
        inviterEphemeralPublicKey: Pubkey,
        sharedSecret: String,
        inviter: Pubkey,
        inviterEphemeralPrivateKey: Privkey? = nil,
        label: String? = nil,
        maxUses: Int? = nil,
        usedBy: [Pubkey] = []
    ) {
        self.inviterEphemeralPublicKey = inviterEphemeralPublicKey
        self.sharedSecret = sharedSecret
        self.inviter = inviter
        self.inviterEphemeralPrivateKey = inviterEphemeralPrivateKey
        self.label = label
        self.maxUses = maxUses
        self.usedBy = usedBy
    }
    
    static func createNew(inviter: Pubkey, label: String? = nil, maxUses: Int? = nil) throws -> Invite {
        let inviterEphemeralKeypair = generate_new_keypair()
        let inviterEphemeralPublicKey = try privkey_to_pubkey(privkey: inviterEphemeralKeypair.privkey)!
        let sharedSecret = hex_encode(generate_new_keypair().privkey.id)
        
        return Invite(
            inviterEphemeralPublicKey: inviterEphemeralPublicKey,
            sharedSecret: sharedSecret,
            inviter: inviter,
            inviterEphemeralPrivateKey: inviterEphemeralKeypair.privkey,
            label: label,
            maxUses: maxUses
        )
    }
    
    static func fromUrl(_ url: URL) throws -> Invite {
        guard let fragment = url.fragment,
              let decodedHash = fragment.removingPercentEncoding,
              let data = decodedHash.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("Invalid URL format: \(url)")  // Debug output
            throw InviteError.invalidUrl
        }
        
        guard let inviter = json["inviter"] as? String,
              let ephemeralKey = json["ephemeralKey"] as? String,
              let sharedSecret = json["sharedSecret"] as? String,
              let inviterPubkey = Pubkey(hex: inviter),
              let ephemeralPubkey = Pubkey(hex: ephemeralKey) else {
            print("Missing fields in URL: \(json)")  // Debug output
            throw InviteError.missingFields
        }
        
        return Invite(
            inviterEphemeralPublicKey: ephemeralPubkey,
            sharedSecret: sharedSecret,
            inviter: inviterPubkey
        )
    }
    
    static func fromEvent(_ event: NostrEvent) throws -> Invite {
        let validationResult = validate_event(ev: event)
        guard validationResult == .ok else {
            print("Invalid event signature: \(event.id.hex()), validation result: \(validationResult)")
            throw InviteError.invalidSignature
        }
        
        // Print the event tags for debugging
        print("Event tags: \(event.tags)")
        
        // Find tags by their first element using direct tag access
        var ephemeralKeyValue: String? = nil
        var sharedSecretValue: String? = nil
        
        for tag in event.tags {
            if tag.count > 1 {
                if tag[0].string() == "ephemeralKey" {
                    ephemeralKeyValue = tag[1].string()
                } else if tag[0].string() == "sharedSecret" {
                    sharedSecretValue = tag[1].string()
                }
            }
        }
        
        guard let ephemeralKey = ephemeralKeyValue,
              let sharedSecret = sharedSecretValue,
              let ephemeralPubkey = Pubkey(hex: ephemeralKey) else {
            print("Missing or invalid tags in event: \(event.tags)")
            throw InviteError.missingTags
        }
        
        return Invite(
            inviterEphemeralPublicKey: ephemeralPubkey,
            sharedSecret: sharedSecret,
            inviter: event.pubkey
        )
    }
    
    func getUrl(root: String = "https://iris.to") -> String {
        let data: [String: String] = [
            "inviter": inviter.hex(),
            "ephemeralKey": inviterEphemeralPublicKey.hex(),
            "sharedSecret": sharedSecret
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return root
        }
        
        var components = URLComponents(string: root) ?? URLComponents()
        components.fragment = jsonString
        return components.url?.absoluteString ?? root
    }
    
    func getEvent(keypair: FullKeypair) -> NostrEvent {
        if keypair.pubkey != inviter {
            fatalError("Invalid keypair for invite: \(keypair.pubkey.hex()) vs \(inviter.hex())")
        }

        guard let event = NostrEvent(
            content: "",
            keypair: keypair.to_keypair(),
            kind: DoubleRatchet.Constants.INVITE_EVENT_KIND,
            tags: [
                ["ephemeralKey", inviterEphemeralPublicKey.hex()],
                ["sharedSecret", sharedSecret],
                ["d", "double-ratchet/invites/public"],
                ["l", "double-ratchet/invites"]
            ]
        ) else {
            fatalError("Failed to create NostrEvent")
        }
        
        return event
    }
    
    func accept(
        nostrSubscribe: @escaping DoubleRatchet.NostrSubscribe,
        inviteePublicKey: Pubkey,
        encryptor: Privkey
    ) async throws -> (session: Session, event: NostrEvent) {
        let inviteeSessionKey = generate_new_keypair().privkey
        let inviteeSessionPublicKey = try privkey_to_pubkey(privkey: inviteeSessionKey)!
        let inviterPublicKey = inviter
        
        let sharedSecretData = Data(hex: sharedSecret)
        let session = try Session.initialize(
            theirEphemeralNostrPublicKey: inviterEphemeralPublicKey,
            ourEphemeralNostrPrivateKey: inviteeSessionKey,
            isInitiator: true,
            sharedSecret: sharedSecretData,
            nostrSubscribe: nostrSubscribe
        )
        
        // Encrypt invitee session public key with DH(invitee, inviter)
        let dhEncrypted = try await NIP44v2Encryption.encrypt(
            plaintext: inviteeSessionPublicKey.hex(),
            privateKeyA: encryptor,
            publicKeyB: inviterPublicKey
        )
        
        // Create inner event
        let innerEvent = NostrEvent(
            content: try await NIP44v2Encryption.encrypt(
                plaintext: dhEncrypted,
                conversationKey: sharedSecretData
            ),
            keypair: Keypair(pubkey: inviteePublicKey, privkey: nil),
            kind: 0,
            tags: [],
            createdAt: UInt32(Date().timeIntervalSince1970)
        )!
        
        let innerJson = encode_json(innerEvent)!
        
        // Create a random keypair for the envelope sender
        let randomSenderKeypair = generate_new_keypair()
        let randomSenderPublicKey = try privkey_to_pubkey(privkey: randomSenderKeypair.privkey)!
        
        // Create and encrypt the envelope
        let envelope = NostrEvent(
            content: try await NIP44v2Encryption.encrypt(
                plaintext: innerJson,
                privateKeyA: randomSenderKeypair.privkey,
                publicKeyB: inviterEphemeralPublicKey
            ),
            keypair: Keypair(pubkey: randomSenderPublicKey, privkey: randomSenderKeypair.privkey),
            kind: DoubleRatchet.Constants.INVITE_RESPONSE_KIND,
            tags: [["p", inviterEphemeralPublicKey.hex()]],
            createdAt: UInt32(Date().timeIntervalSince1970 - Double.random(in: 0...Self.TWO_DAYS))
        )!
        
        return (session: session, event: envelope)
    }
    
    func listen(
        decryptor: Privkey,
        nostrSubscribe: @escaping DoubleRatchet.NostrSubscribe,
        onSession: @escaping (Session, Pubkey?) -> Void
    ) throws -> DoubleRatchet.Unsubscribe {
        guard let inviterEphemeralPrivateKey = self.inviterEphemeralPrivateKey else {
            throw InviteError.inviterKeyNotAvailable
        }
        
        let filter = NostrFilter(
            kinds: [.gift_wrap],
            pubkeys: [inviterEphemeralPublicKey]
        )
        
        return nostrSubscribe(filter) { [weak self] event in
            guard let self = self else { return }
            
            do {
                if let maxUses = self.maxUses, self.usedBy.count >= maxUses {
                    print("Invite has reached maximum number of uses")
                    return
                }
                
                // Decrypt the outer envelope first
                let decrypted = try NIP44v2Encryption.decrypt(
                    payload: event.content,
                    privateKeyA: inviterEphemeralPrivateKey,
                    publicKeyB: event.pubkey
                )
                
                guard let innerEvent = NostrEvent.owned_from_json(json: decrypted) else {
                    print("Invalid inner event format")
                    return
                }
                
                let sharedSecretData = Data(hex: self.sharedSecret)
                let inviteeIdentity = innerEvent.pubkey
                self.usedBy.append(inviteeIdentity)
                
                // Decrypt the inner content using shared secret first
                let dhEncrypted = try NIP44v2Encryption.decrypt(
                    payload: innerEvent.content,
                    conversationKey: sharedSecretData
                )
                
                // Then decrypt using DH key
                let decryptedSessionKey = try NIP44v2Encryption.decrypt(
                    payload: dhEncrypted,
                    privateKeyA: decryptor,
                    publicKeyB: inviteeIdentity
                )
                
                guard let inviteeSessionPubkey = Pubkey(hex: decryptedSessionKey) else {
                    print("Invalid invitee session public key")
                    return
                }
                
                let session = try Session.initialize(
                    theirEphemeralNostrPublicKey: inviteeSessionPubkey,
                    ourEphemeralNostrPrivateKey: inviterEphemeralPrivateKey,
                    isInitiator: false,
                    sharedSecret: sharedSecretData,
                    nostrSubscribe: nostrSubscribe,
                    name: event.id.hex()
                )
                
                onSession(session, inviteeIdentity)
            } catch {
                print("Error processing invite message:", error, "event:", event)
            }
        }
    }
    
    enum InviteError: Error {
        case invalidUrl
        case missingFields
        case invalidSignature
        case missingTags
        case inviterKeyNotAvailable
    }
}
