//
//  Session.swift
//  damus
//
//  Created by Martti Malmi on 28.2.2025.
//

import Foundation
import secp256k1
import CryptoKit

/// Double ratchet secure communication session over Nostr
/// Very similar to Signal's "Double Ratchet with header encryption"
/// https://signal.org/docs/specifications/doubleratchet/
class Session {
    internal var state: DoubleRatchet.SessionState
    private var subscriptions: [Int: DoubleRatchet.EventCallback] = [:]
    private var currentSubscriptionId = 0
    private var nostrUnsubscribe: DoubleRatchet.Unsubscribe?
    private var nostrNextUnsubscribe: DoubleRatchet.Unsubscribe?
    private var skippedSubscription: DoubleRatchet.Unsubscribe?
    private let nostrSubscribe: DoubleRatchet.NostrSubscribe
    var name: String
    
    // MARK: - Types
    
    typealias EventCallback = (DoubleRatchet.Rumor, NostrEvent) -> Void
    typealias Unsubscribe = () -> Void
    
    // MARK: - Double Ratchet Initialization
    
    init(state: DoubleRatchet.SessionState, nostrSubscribe: @escaping DoubleRatchet.NostrSubscribe, name: String) {
        self.state = state
        self.nostrSubscribe = nostrSubscribe
        self.name = name
    }
    
    static func initialize(
        theirEphemeralNostrPublicKey: Pubkey,
        ourEphemeralNostrPrivateKey: Privkey,
        isInitiator: Bool,
        sharedSecret: Data,
        nostrSubscribe: @escaping DoubleRatchet.NostrSubscribe,
        name: String? = nil
    ) throws -> Session {
        let ourNextKeypair = generate_new_keypair()
        
        let conversationKey = try NIP44v2Encryption.conversationKey(
            privateKeyA: ourEphemeralNostrPrivateKey,
            publicKeyB: theirEphemeralNostrPublicKey
        )
        
        let (rootKey, sendingChainKey) = try DoubleRatchet.kdf(sharedSecret, conversationKey, 2)
        
        var ourCurrentNostrKey: FullKeypair?
        
        if isInitiator {
            ourCurrentNostrKey = FullKeypair(
                pubkey: try! privkey_to_pubkey(privkey: ourEphemeralNostrPrivateKey)!,
                privkey: ourEphemeralNostrPrivateKey
            )
        }
        
        let state = DoubleRatchet.SessionState(
            rootKey: isInitiator ? rootKey : sharedSecret,
            theirCurrentNostrPublicKey: nil,
            theirNextNostrPublicKey: theirEphemeralNostrPublicKey,
            ourCurrentNostrKey: ourCurrentNostrKey,
            ourNextNostrKey: ourNextKeypair,
            receivingChainKey: nil,
            sendingChainKey: isInitiator ? sendingChainKey : nil,
            sendingChainMessageNumber: 0,
            receivingChainMessageNumber: 0,
            previousSendingChainMessageCount: 0,
            skippedKeys: [:]
        )
        
        return Session(
            state: state,
            nostrSubscribe: nostrSubscribe,
            name: name ?? String(Int.random(in: 0...9999), radix: 36)
        )
    }
    
    // MARK: - Public Methods
    
    func sendText(_ text: String) throws -> (event: NostrEvent, innerEvent: DoubleRatchet.Rumor) {
        let partialRumor = DoubleRatchet.Rumor(
            id: "",  // Will be calculated later
            content: text,
            kind: DoubleRatchet.Constants.CHAT_MESSAGE_KIND,
            created_at: UInt32(Date().timeIntervalSince1970),
            tags: [],
            pubkey: DoubleRatchet.Constants.DUMMY_PUBKEY
        )
        return try sendEvent(rumor: partialRumor)
    }
    
    func onEvent(_ callback: @escaping DoubleRatchet.EventCallback) -> Unsubscribe {
        let id = currentSubscriptionId
        currentSubscriptionId += 1
        subscriptions[id] = callback
        subscribeToNostrEvents()
        return { [weak self] in
            self?.subscriptions.removeValue(forKey: id)
        }
    }
    
    func close() {
        nostrUnsubscribe?()
        nostrNextUnsubscribe?()
        skippedSubscription?()
        subscriptions.removeAll()
    }
    
    // MARK: - Private Methods - Ratchet Operations
    
    private func ratchetEncrypt(_ plaintext: String) throws -> (DoubleRatchet.Header, String) {
        let (newSendingChainKey, messageKey) = try DoubleRatchet.kdf(state.sendingChainKey!, DoubleRatchet.bytesToData([UInt8](repeating: 1, count: 1)), 2)
        state.sendingChainKey = newSendingChainKey
        
        let header = DoubleRatchet.Header(
            number: state.sendingChainMessageNumber,
            previousChainLength: state.previousSendingChainMessageCount,
            nextPublicKey: state.ourNextNostrKey.pubkey
        )
        state.sendingChainMessageNumber += 1
        
        return (header, try NIP44v2Encryption.encrypt(plaintext: plaintext, conversationKey: messageKey))
    }
    
    private func ratchetDecrypt(header: DoubleRatchet.Header, ciphertext: String, nostrSender: Pubkey) throws -> String {
        if let plaintext = try trySkippedMessageKeys(header: header, ciphertext: ciphertext, nostrSender: nostrSender) {
            return plaintext
        }
        
        try skipMessageKeys(until: header.number, nostrSender: nostrSender)
        
        let (newReceivingChainKey, messageKey) = try DoubleRatchet.kdf(state.receivingChainKey!, DoubleRatchet.bytesToData([UInt8](repeating: 1, count: 1)), 2)
        state.receivingChainKey = newReceivingChainKey
        state.receivingChainMessageNumber += 1
        
        do {
            return try NIP44v2Encryption.decrypt(payload: ciphertext, conversationKey: messageKey)
        } catch {
            print("\(name) Decryption failed:", error)
            throw error
        }
    }
    
    private func ratchetStep(theirNextNostrPublicKey: Pubkey) throws {
        state.previousSendingChainMessageCount = state.sendingChainMessageNumber
        state.sendingChainMessageNumber = 0
        state.receivingChainMessageNumber = 0
        state.theirNextNostrPublicKey = theirNextNostrPublicKey
        
        let conversationKey1 = try NIP44v2Encryption.conversationKey(
            privateKeyA: state.ourNextNostrKey.privkey,
            publicKeyB: theirNextNostrPublicKey
        )
        
        let (theirRootKey, receivingChainKey) = try DoubleRatchet.kdf(state.rootKey, conversationKey1, 2)
        state.receivingChainKey = receivingChainKey
        
        state.ourCurrentNostrKey = state.ourNextNostrKey
        state.ourNextNostrKey = generate_new_keypair()
        
        let conversationKey2 = try NIP44v2Encryption.conversationKey(
            privateKeyA: state.ourNextNostrKey.privkey,
            publicKeyB: theirNextNostrPublicKey
        )
        
        let (rootKey, sendingChainKey) = try DoubleRatchet.kdf(theirRootKey, conversationKey2, 2)
        state.rootKey = rootKey
        state.sendingChainKey = sendingChainKey
    }
    
    // MARK: - Private Methods - Message Key Management
    
    private func skipMessageKeys(until: Int, nostrSender: Pubkey) throws {
        if state.receivingChainMessageNumber + DoubleRatchet.Constants.MAX_SKIP < until {
            throw DoubleRatchet.EncryptionError.tooManySkippedMessages
        }
        
        if state.skippedKeys[nostrSender.hex()] == nil {
            state.skippedKeys[nostrSender.hex()] = DoubleRatchet.SkippedKeys(headerKeys: [], messageKeys: [:])
            
            if let currentKey = state.ourCurrentNostrKey {
                let currentSecret = try NIP44v2Encryption.conversationKey(
                    privateKeyA: currentKey.privkey,
                    publicKeyB: nostrSender
                )
                state.skippedKeys[nostrSender.hex()]?.headerKeys.append(currentSecret as! Data)
            }
            
            let nextSecret = try NIP44v2Encryption.conversationKey(
                privateKeyA: state.ourNextNostrKey.privkey,
                publicKeyB: nostrSender
            )
            state.skippedKeys[nostrSender.hex()]?.headerKeys.append(nextSecret as! Data)
        }
        
        while state.receivingChainMessageNumber < until {
            let (newReceivingChainKey, messageKey) = try DoubleRatchet.kdf(state.receivingChainKey!, DoubleRatchet.bytesToData([UInt8](repeating: 1, count: 1)), 2)
            state.receivingChainKey = newReceivingChainKey
            state.skippedKeys[nostrSender.hex()]?.messageKeys[state.receivingChainMessageNumber] = messageKey
            state.receivingChainMessageNumber += 1
        }
    }
    
    private func trySkippedMessageKeys(header: DoubleRatchet.Header, ciphertext: String, nostrSender: Pubkey) throws -> String? {
        guard let skippedKeys = state.skippedKeys[nostrSender.hex()] else { return nil }
        guard let messageKey = skippedKeys.messageKeys[header.number] else { return nil }
        
        state.skippedKeys[nostrSender.hex()]?.messageKeys.removeValue(forKey: header.number)
        
        if state.skippedKeys[nostrSender.hex()]?.messageKeys.isEmpty ?? true {
            state.skippedKeys.removeValue(forKey: nostrSender.hex())
        }
        
        return try NIP44v2Encryption.decrypt(payload: ciphertext, conversationKey: messageKey)
    }
    
    // MARK: - Private Methods - Event Handling
    
    private func handleNostrEvent(_ event: NostrEvent) throws {
        let (header, shouldRatchet, isSkipped) = try decryptHeader(event)
        
        if !isSkipped {
            if state.theirNextNostrPublicKey != header.nextPublicKey {
                state.theirCurrentNostrPublicKey = state.theirNextNostrPublicKey
                state.theirNextNostrPublicKey = header.nextPublicKey
                nostrUnsubscribe?()
                nostrUnsubscribe = nostrNextUnsubscribe
                nostrNextUnsubscribe = nostrSubscribe(
                    NostrFilter(
                        kinds: [.double_ratchet_message],
                        authors: [state.theirNextNostrPublicKey]
                    ),
                    { [weak self] event in
                        try? self?.handleNostrEvent(event)
                    }
                )
            }
            
            if shouldRatchet {
                try skipMessageKeys(until: header.previousChainLength, nostrSender: event.pubkey)
                try ratchetStep(theirNextNostrPublicKey: header.nextPublicKey)
            }
        } else {
            if state.skippedKeys[event.pubkey.hex()]?.messageKeys[header.number] == nil {
                // Maybe we already processed this message — no error
                return
            }
        }
        
        let text = try ratchetDecrypt(header: header, ciphertext: event.content, nostrSender: event.pubkey)
        guard let innerEvent = NostrEvent.owned_from_json(json: text) else {
            print("Invalid event received", text)
            return
        }

        if !innerEvent.sig.data.isEmpty {
            print("Error: Inner event has sig", innerEvent)
            return
        }

        let rumor = DoubleRatchet.Rumor(
            id: innerEvent.id.hex(),
            content: innerEvent.content,
            kind: innerEvent.kind,
            created_at: innerEvent.created_at,
            tags: innerEvent.tags.strings(),
            pubkey: event.pubkey
        )
        
        guard validate_event(ev: innerEvent) == .ok else {
            print("Event validation failed", innerEvent)
            return
        }
        
        if innerEvent.id != calculate_event_id(
            pubkey: innerEvent.pubkey,
            created_at: innerEvent.created_at,
            kind: innerEvent.kind,
            tags: innerEvent.tags.strings(),
            content: innerEvent.content
        ) {
            print("Event hash does not match", innerEvent)
            return
        }
        
        subscriptions.values.forEach { callback in
            callback(rumor, event)
        }
    }
    
    private func sendEvent(rumor: DoubleRatchet.Rumor) throws -> (event: NostrEvent, innerEvent: DoubleRatchet.Rumor) {
        if state.theirNextNostrPublicKey.id.isEmpty || state.ourCurrentNostrKey == nil {
            throw DoubleRatchet.EncryptionError.notInitiator
        }
        
        let now = Date().timeIntervalSince1970
        
        var rumor = rumor  // Create mutable copy
        
        // Add millisecond timestamp if not present
        if !rumor.tags.contains(where: { $0.first == "ms" }) {
            rumor.tags.append(["ms", String(Int(now * 1000))])
        }
        
        rumor.id = calculate_event_id(
            pubkey: rumor.pubkey,
            created_at: rumor.created_at,
            kind: rumor.kind,
            tags: rumor.tags,
            content: rumor.content
        ).hex()
        
        let (header, encryptedData) = try ratchetEncrypt(try DoubleRatchet.toString(try JSONEncoder().encode(rumor)))
        
        let sharedSecret = try NIP44v2Encryption.conversationKey(
            privateKeyA: state.ourCurrentNostrKey!.privkey,
            publicKeyB: state.theirNextNostrPublicKey
        )
        
        let encryptedHeader = try NIP44v2Encryption.encrypt(
            plaintext: try DoubleRatchet.toString(try JSONEncoder().encode(header)),
            conversationKey: sharedSecret
        )
        
        let nostrEvent = NostrEvent(
            content: encryptedData,
            keypair: Keypair(pubkey: privkey_to_pubkey(privkey: state.ourCurrentNostrKey!.privkey)!, privkey: state.ourCurrentNostrKey!.privkey),
            kind: UInt32(DoubleRatchet.Constants.MESSAGE_EVENT_KIND),
            tags: [["header", encryptedHeader]],
            createdAt: UInt32(now)
        )!
        
        return (event: nostrEvent, innerEvent: rumor)
    }
    
    // MARK: - Private Methods - Nostr Subscription
    
    private func subscribeToNostrEvents() {
        guard nostrNextUnsubscribe == nil else { return }
        
        nostrNextUnsubscribe = nostrSubscribe(
            NostrFilter(
                kinds: [.double_ratchet_message],
                authors: [state.theirNextNostrPublicKey]
            ),
            { [weak self] event in
                try? self?.handleNostrEvent(event)
            }
        )
        
        if let currentKey = state.theirCurrentNostrPublicKey {
            nostrUnsubscribe = nostrSubscribe(
                NostrFilter(
                    kinds: [.double_ratchet_message],
                    authors: [currentKey]
                ),
                { [weak self] event in
                    try? self?.handleNostrEvent(event)
                }
            )
        }
        
        let skippedAuthors = Array(state.skippedKeys.keys).compactMap { Pubkey(hex: $0) }
        if !skippedAuthors.isEmpty {
            skippedSubscription = nostrSubscribe(
                NostrFilter(
                    kinds: [.double_ratchet_message],
                    authors: skippedAuthors
                ),
                { [weak self] event in
                    try? self?.handleNostrEvent(event)
                }
            )
        }
    }
    
    // MARK: - Private Methods - Event Handling
    
    private func decryptHeader(_ event: NostrEvent) throws -> (DoubleRatchet.Header, Bool, Bool) {
        let encryptedHeader = String(describing: event.tags[0][1])
        
        if let currentKey = state.ourCurrentNostrKey {
            let currentSecret = try NIP44v2Encryption.conversationKey(
                privateKeyA: currentKey.privkey,
                publicKeyB: event.pubkey
            )
            do {
                let header = try JSONDecoder().decode(DoubleRatchet.Header.self, from: Data(try NIP44v2Encryption.decrypt(payload: encryptedHeader, conversationKey: currentSecret).utf8))
                return (header, false, false)
            } catch {
                // Decryption with currentSecret failed, try nextSecret
            }
        }
        
        let nextSecret = try NIP44v2Encryption.conversationKey(
            privateKeyA: state.ourNextNostrKey.privkey,
            publicKeyB: event.pubkey
        )
        do {
            let header = try JSONDecoder().decode(DoubleRatchet.Header.self, from: Data(try NIP44v2Encryption.decrypt(payload: encryptedHeader, conversationKey: nextSecret).utf8))
            return (header, true, false)
        } catch {
            // Decryption with nextSecret failed, try skipped keys
        }
        
        if let skippedKeys = state.skippedKeys[event.pubkey.hex()]?.headerKeys {
            for key in skippedKeys {
                do {
                    let header = try JSONDecoder().decode(DoubleRatchet.Header.self, from: Data(try NIP44v2Encryption.decrypt(payload: encryptedHeader, conversationKey: key).utf8))
                    return (header, false, true)
                } catch {
                    // Try next key
                }
            }
        }
        
        throw DoubleRatchet.EncryptionError.headerDecryptionFailed
    }
    
    // MARK: - Error Types
    
    enum EncryptionError: Error {
        case tooManySkippedMessages
        case headerDecryptionFailed
        case notInitiator
    }
}
