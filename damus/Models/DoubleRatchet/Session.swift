//
//  Session.swift
//  damus
//
//  Created by Martti Malmi on 28.2.2025.
//

import Foundation
import secp256k1

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
        print("Initializing session - isInitiator:", isInitiator)

        var ourNextKeypair: FullKeypair
        var rootKey: Data
        var sendingChainKey: Data?
        var ourCurrentNostrKey: FullKeypair?
        
        if isInitiator {
            ourNextKeypair = generate_new_keypair()
            let conversationKey = try NIP44v2Encryption.conversationKey(
                privateKeyA: ourNextKeypair.privkey,
                publicKeyB: theirEphemeralNostrPublicKey
            )
            
            // Convert ContiguousBytes to Data for logging
            var conversationKeyData = Data()
            conversationKey.withUnsafeBytes { bytes in
                conversationKeyData.append(contentsOf: bytes)
            }
            print("Generated conversation key: \(conversationKeyData.hexString.prefix(16))")
            
            (rootKey, sendingChainKey) = try DoubleRatchet.kdf(sharedSecret, conversationKeyData, 2)
            print("Generated root key: \(rootKey.hexString.prefix(16)) and sending chain key: \(sendingChainKey?.hexString.prefix(16) ?? "nil")")

            ourCurrentNostrKey = FullKeypair(
                pubkey: try! privkey_to_pubkey(privkey: ourEphemeralNostrPrivateKey)!,
                privkey: ourEphemeralNostrPrivateKey
            )
            print("Set initiator current key:", ourCurrentNostrKey?.pubkey.hex().prefix(8) ?? "nil")
        } else {
            ourNextKeypair = FullKeypair(
                pubkey: try! privkey_to_pubkey(privkey: ourEphemeralNostrPrivateKey)!,
                privkey: ourEphemeralNostrPrivateKey
            )
            print("Set responder next key:", ourNextKeypair.pubkey.hex().prefix(8))

            rootKey = sharedSecret
            sendingChainKey = nil
            ourCurrentNostrKey = nil
        }
        
        let state = DoubleRatchet.SessionState(
            rootKey: rootKey,
            theirCurrentNostrPublicKey: nil,
            theirNextNostrPublicKey: theirEphemeralNostrPublicKey,
            ourCurrentNostrKey: ourCurrentNostrKey,
            ourNextNostrKey: ourNextKeypair,
            receivingChainKey: nil,
            sendingChainKey: sendingChainKey,
            sendingChainMessageNumber: 0,
            receivingChainMessageNumber: 0,
            previousSendingChainMessageCount: 0,
            skippedKeys: [:]
        )
        print("Created session state")
        
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
        print("\(name) registering event callback")
        let id = currentSubscriptionId
        currentSubscriptionId += 1
        subscriptions[id] = callback
        subscribeToNostrEvents()
        return { [weak self] in
            print("\(self?.name ?? "unknown") unsubscribing callback \(id)")
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

        print("\(name) ratchetEncrypt - starting with rootKey: \(state.rootKey.hexString.prefix(16))")
        print("\(name) ratchetEncrypt - current sendingChainKey: \(state.sendingChainKey?.hexString.prefix(16) ?? "nil")")
        print("\(name) ratchetEncrypt - current rootKey: \(state.rootKey.hexString.prefix(16))")

        let (newSendingChainKey, messageKey) = try DoubleRatchet.kdf(state.sendingChainKey!, DoubleRatchet.bytesToData([UInt8](repeating: 1, count: 1)), 2)
        state.sendingChainKey = newSendingChainKey

        print("\(name) ratchetEncrypt - new sendingChainKey: \(state.sendingChainKey!.hexString.prefix(16))")
        print("\(name) ratchetEncrypt - messageKey: \(messageKey.hexString.prefix(16))")
        
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
    
    private func ratchetStep() throws {
        print("\(name) ratchetStep - starting with theirNextNostrPublicKey: \(state.theirNextNostrPublicKey.hex().prefix(8))")
        print("\(name) ratchetStep - current rootKey: \(state.rootKey.hexString.prefix(16))")
        
        state.previousSendingChainMessageCount = state.sendingChainMessageNumber
        state.sendingChainMessageNumber = 0
        state.receivingChainMessageNumber = 0

        let conversationKey1 = try NIP44v2Encryption.conversationKey(
            privateKeyA: state.ourNextNostrKey.privkey,
            publicKeyB: state.theirNextNostrPublicKey
        )
        
        // Convert ContiguousBytes to Data
        var conversationKey1Data = Data()
        conversationKey1.withUnsafeBytes { bytes in
            conversationKey1Data.append(contentsOf: bytes)
        }
        print("\(name) ratchetStep - conversationKey1: \(conversationKey1Data.hexString.prefix(16))")
        
        let (theirRootKey, receivingChainKey) = try DoubleRatchet.kdf(state.rootKey, conversationKey1Data, 2)
        print("\(name) ratchetStep - theirRootKey: \(theirRootKey.hexString.prefix(16))")
        print("\(name) ratchetStep - receivingChainKey: \(receivingChainKey.hexString.prefix(16))")
        
        state.receivingChainKey = receivingChainKey
        
        state.ourCurrentNostrKey = state.ourNextNostrKey
        state.ourNextNostrKey = generate_new_keypair()
        print("\(name) ratchetStep - new ourNextNostrKey: \(state.ourNextNostrKey.pubkey.hex().prefix(8))")
        
        let conversationKey2 = try NIP44v2Encryption.conversationKey(
            privateKeyA: state.ourNextNostrKey.privkey,
            publicKeyB: state.theirNextNostrPublicKey
        )
        
        // Convert ContiguousBytes to Data
        var conversationKey2Data = Data()
        conversationKey2.withUnsafeBytes { bytes in
            conversationKey2Data.append(contentsOf: bytes)
        }
        print("\(name) ratchetStep - conversationKey2: \(conversationKey2Data.hexString.prefix(16))")
        
        let (rootKey, sendingChainKey) = try DoubleRatchet.kdf(theirRootKey, conversationKey2Data, 2)
        print("\(name) ratchetStep - new rootKey: \(rootKey.hexString.prefix(16))")
        print("\(name) ratchetStep - sendingChainKey: \(sendingChainKey.hexString.prefix(16))")
        
        state.rootKey = rootKey
        state.sendingChainKey = sendingChainKey
    }
    
    // MARK: - Private Methods - Message Key Management
    
    private func skipMessageKeys(until: Int, nostrSender: Pubkey) throws {
        if until <= state.receivingChainMessageNumber {
            return
        }

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
                // Convert ContiguousBytes to Data
                var currentSecretData = Data()
                currentSecret.withUnsafeBytes { bytes in
                    currentSecretData.append(contentsOf: bytes)
                }
                
                // Only append if not already present
                if !state.skippedKeys[nostrSender.hex()]!.headerKeys.contains(currentSecretData) {
                    state.skippedKeys[nostrSender.hex()]?.headerKeys.append(currentSecretData)
                }
            }
            
            let nextSecret = try NIP44v2Encryption.conversationKey(
                privateKeyA: state.ourNextNostrKey.privkey,
                publicKeyB: nostrSender
            )
            // Convert ContiguousBytes to Data
            var nextSecretData = Data()
            nextSecret.withUnsafeBytes { bytes in
                nextSecretData.append(contentsOf: bytes)
            }
            
            // Only append if not already present
            if !state.skippedKeys[nostrSender.hex()]!.headerKeys.contains(nextSecretData) {
                state.skippedKeys[nostrSender.hex()]?.headerKeys.append(nextSecretData)
            }
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
        print("\(name) handleNostrEvent:", event.id.hex().prefix(8))
        let (header, shouldRatchet, isSkipped) = try decryptHeader(event)
        print("\(name) decrypted header:", "shouldRatchet:", shouldRatchet, "isSkipped:", isSkipped)
        
        if !isSkipped {
            if state.theirNextNostrPublicKey != header.nextPublicKey {
                print("\(name) updating public keys")
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
                print("\(name) performing ratchet step")
                try skipMessageKeys(until: header.previousChainLength, nostrSender: event.pubkey)
                try ratchetStep()
            }
        } else {
            if state.skippedKeys[event.pubkey.hex()]?.messageKeys[header.number] == nil {
                print("\(name) skipped message already processed")
                return
            }
        }
        
        print("\(name) decrypting message")
        let text = try ratchetDecrypt(header: header, ciphertext: event.content, nostrSender: event.pubkey)
        print("\(name) decrypted text:", text)
        
        let innerEvent: DoubleRatchet.Rumor = try JSONDecoder().decode(DoubleRatchet.Rumor.self, from: Data(text.utf8))

        let calculatedId = calculate_event_id(
            pubkey: innerEvent.pubkey,
            created_at: innerEvent.created_at,
            kind: innerEvent.kind,
            tags: innerEvent.tags,
            content: innerEvent.content
        ).hex()
        
        if innerEvent.id != calculatedId {
            print("\(name) Error: Inner event id does not match", innerEvent)
            return
        }

        let rumor = DoubleRatchet.Rumor(
            id: innerEvent.id,
            content: innerEvent.content,
            kind: innerEvent.kind,
            created_at: innerEvent.created_at,
            tags: innerEvent.tags,
            pubkey: event.pubkey
        )
        
        let calculatedEventId = calculate_event_id(
            pubkey: innerEvent.pubkey,
            created_at: innerEvent.created_at,
            kind: innerEvent.kind,
            tags: innerEvent.tags,
            content: innerEvent.content
        ).hex()
        
        if innerEvent.id != calculatedEventId {
            print("\(name) Event hash does not match", innerEvent)
            return
        }
        
        print("\(name) calling \(subscriptions.count) callbacks")
        subscriptions.values.forEach { callback in
            callback(rumor, event)
        }
    }
    
    private func sendEvent(rumor: DoubleRatchet.Rumor) throws -> (event: NostrEvent, innerEvent: DoubleRatchet.Rumor) {
        print("\(name) sendEvent")
        if state.theirNextNostrPublicKey.id.isEmpty || state.ourCurrentNostrKey == nil {
            print("\(name) not initiator error")
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
        print("\(name) subscribing to Nostr events")
        guard nostrNextUnsubscribe == nil else {
            print("\(name) already subscribed")
            return
        }
        
        print("\(name) subscribing to next public key:", state.theirNextNostrPublicKey.hex().prefix(8))
        nostrNextUnsubscribe = nostrSubscribe(
            NostrFilter(
                kinds: [.double_ratchet_message],
                authors: [state.theirNextNostrPublicKey]
            ),
            { [weak self] event in
                print("\(self?.name ?? "unknown") received event for next key")
                try? self?.handleNostrEvent(event)
            }
        )
        
        if let currentKey = state.theirCurrentNostrPublicKey {
            print("\(name) subscribing to current public key:", currentKey.hex().prefix(8))
            nostrUnsubscribe = nostrSubscribe(
                NostrFilter(
                    kinds: [.double_ratchet_message],
                    authors: [currentKey]
                ),
                { [weak self] event in
                    print("\(self?.name ?? "unknown") received event for current key")
                    try? self?.handleNostrEvent(event)
                }
            )
        }
        
        let skippedAuthors = Array(state.skippedKeys.keys).compactMap { Pubkey(hex: $0) }
        if !skippedAuthors.isEmpty {
            print("\(name) subscribing to skipped authors:", skippedAuthors.map { $0.hex().prefix(8) })
            skippedSubscription = nostrSubscribe(
                NostrFilter(
                    kinds: [.double_ratchet_message],
                    authors: skippedAuthors
                ),
                { [weak self] event in
                    print("\(self?.name ?? "unknown") received event for skipped key")
                    try? self?.handleNostrEvent(event)
                }
            )
        }
    }
    
    // MARK: - Private Methods - Event Handling
    
    private func decryptHeader(_ event: NostrEvent) throws -> (DoubleRatchet.Header, Bool, Bool) {
        print("\(name) decrypting header for event:", event.id.hex().prefix(8))
        let encryptedHeader = event.tags[0][1].string()
        
        if let currentKey = state.ourCurrentNostrKey {
            print("\(name) trying current key:", currentKey.pubkey.hex().prefix(8))
            let currentSecret = try NIP44v2Encryption.conversationKey(
                privateKeyA: currentKey.privkey,
                publicKeyB: event.pubkey
            )
            do {
                let header = try JSONDecoder().decode(DoubleRatchet.Header.self, from: Data(try NIP44v2Encryption.decrypt(payload: encryptedHeader, conversationKey: currentSecret).utf8))
                print("\(name) decrypted with current key")
                return (header, false, false)
            } catch {
                print("\(name) failed to decrypt with current key:", error)
            }
        }
        
        print("\(name) trying next key:", state.ourNextNostrKey.pubkey.hex().prefix(8))
        let nextSecret = try NIP44v2Encryption.conversationKey(
            privateKeyA: state.ourNextNostrKey.privkey,
            publicKeyB: event.pubkey
        )
        do {
            let header = try JSONDecoder().decode(DoubleRatchet.Header.self, from: Data(try NIP44v2Encryption.decrypt(payload: encryptedHeader, conversationKey: nextSecret).utf8))
            print("\(name) decrypted with next key")
            return (header, true, false)
        } catch {
            print("\(name) failed to decrypt with next key:", error)
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
        print("\(name) failed to decrypt with skipped keys")
        
        throw DoubleRatchet.EncryptionError.headerDecryptionFailed
    }
    
    // MARK: - Error Types
    
    enum EncryptionError: Error {
        case tooManySkippedMessages
        case headerDecryptionFailed
        case notInitiator
    }
}

// Add this extension to help with debugging
extension Data {
    var hexString: String {
        return self.map { String(format: "%02hhx", $0) }.joined()
    }
}
