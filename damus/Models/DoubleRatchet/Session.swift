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
    var name: String
    
    // MARK: - Types
    
    typealias EventCallback = (DoubleRatchet.Rumor, NostrEvent) -> Void
    typealias Unsubscribe = () -> Void
    
    // MARK: - Double Ratchet Initialization
    
    init(state: DoubleRatchet.SessionState, name: String) {
        self.state = state
        self.name = name
    }
    
    static func initialize(
        theirEphemeralNostrPublicKey: Pubkey,
        ourEphemeralNostrPrivateKey: Privkey,
        isInitiator: Bool,
        sharedSecret: Data,
        name: String? = nil
    ) throws -> Session {
        let ourNextPrivateKey = generatePrivateKey()
        let ourNextPubkey = try! privkey_to_pubkey(privkey: Privkey(ourNextPrivateKey))!
        
        let conversationKey = try NIP44v2Encryption.conversationKey(
            privateKeyA: Privkey(ourNextPrivateKey),
            publicKeyB: theirEphemeralNostrPublicKey
        )
        
        let (rootKey, sendingChainKey) = try kdf(sharedSecret, conversationKey, 2)
        
        var ourCurrentNostrKey: FullKeypair?
        let ourNextNostrKey: FullKeypair
        
        if isInitiator {
            ourCurrentNostrKey = FullKeypair(
                pubkey: try! privkey_to_pubkey(privkey: ourEphemeralNostrPrivateKey)!,
                privkey: ourEphemeralNostrPrivateKey
            )
            ourNextNostrKey = FullKeypair(pubkey: ourNextPubkey, privkey: Privkey(ourNextPrivateKey))
        } else {
            ourNextNostrKey = FullKeypair(pubkey: ourNextPubkey, privkey: Privkey(ourNextPrivateKey))
        }
        
        let state = DoubleRatchet.SessionState(
            rootKey: isInitiator ? rootKey : sharedSecret,
            theirCurrentNostrPublicKey: nil,
            theirNextNostrPublicKey: theirEphemeralNostrPublicKey,
            ourCurrentNostrKey: ourCurrentNostrKey,
            ourNextNostrKey: ourNextNostrKey,
            receivingChainKey: nil,
            sendingChainKey: isInitiator ? sendingChainKey : nil,
            sendingChainMessageNumber: 0,
            receivingChainMessageNumber: 0,
            previousSendingChainMessageCount: 0,
            skippedKeys: [:]
        )
        
        return Session(state: state, name: name ?? String(Int.random(in: 0...9999), radix: 36))
    }
    
    // MARK: - Public Methods
    
    func send(_ text: String) throws -> (event: NostrEvent, innerEvent: DoubleRatchet.Rumor) {
        return try sendEvent(content: text, kind: DoubleRatchet.Constants.CHAT_MESSAGE_KIND)
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
        subscriptions.removeAll()
    }
    
    // MARK: - Private Methods - Ratchet Operations
    
    private func ratchetEncrypt(_ plaintext: String) throws -> (DoubleRatchet.Header, String) {
        let (newSendingChainKey, messageKey) = try kdf(state.sendingChainKey!, bytesToData([UInt8](repeating: 1, count: 1)), 2)
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
        
        let (newReceivingChainKey, messageKey) = try kdf(state.receivingChainKey!, bytesToData([UInt8](repeating: 1, count: 1)), 2)
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
        
        let (theirRootKey, receivingChainKey) = try kdf(state.rootKey, conversationKey1, 2)
        state.receivingChainKey = receivingChainKey
        
        state.ourCurrentNostrKey = state.ourNextNostrKey
        let ourNextSecretKey = generatePrivateKey()
        state.ourNextNostrKey = FullKeypair(
            pubkey: try! privkey_to_pubkey(privkey: Privkey(ourNextSecretKey))!,
            privkey: Privkey(ourNextSecretKey)
        )
        
        let conversationKey2 = try NIP44v2Encryption.conversationKey(
            privateKeyA: state.ourNextNostrKey.privkey,
            publicKeyB: theirNextNostrPublicKey
        )
        
        let (rootKey, sendingChainKey) = try kdf(theirRootKey, conversationKey2, 2)
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
                state.skippedKeys[nostrSender.hex()]?.headerKeys.append(currentSecret)
            }
            
            let nextSecret = try NIP44v2Encryption.conversationKey(
                privateKeyA: state.ourNextNostrKey.privkey,
                publicKeyB: nostrSender
            )
            state.skippedKeys[nostrSender.hex()]?.headerKeys.append(nextSecret)
        }
        
        while state.receivingChainMessageNumber < until {
            let (newReceivingChainKey, messageKey) = try kdf(state.receivingChainKey!, bytesToData([UInt8](repeating: 1, count: 1)), 2)
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
        guard let innerEvent = try? JSONDecoder().decode(DoubleRatchet.Rumor.self, from: Data(text.utf8)) else {
            print("Invalid event received", text)
            return
        }
        
        guard innerEvent.id == getEventHash(innerEvent) else {
            print("Event hash does not match", innerEvent)
            return
        }
        
        subscriptions.values.forEach { callback in
            callback(innerEvent, event)
        }
    }
    
    private func sendEvent(content: String, kind: Int) throws -> (event: NostrEvent, innerEvent: DoubleRatchet.Rumor) {
        if state.theirNextNostrPublicKey.id.isEmpty || state.ourCurrentNostrKey == nil {
            throw DoubleRatchet.EncryptionError.notInitiator
        }
        
        let now = Date().timeIntervalSince1970
        
        var rumor = DoubleRatchet.Rumor(
            id: "",
            content: content,
            kind: kind,
            created_at: Int(now),
            tags: [],
            pubkey: DoubleRatchet.Constants.DUMMY_PUBKEY
        )
        
        // Add millisecond timestamp if not present
        if !rumor.tags.contains(where: { $0.first == "ms" }) {
            rumor.tags.append(["ms", String(Int(now * 1000))])
        }
        
        rumor.id = getEventHash(rumor)
        
        let (header, encryptedData) = try ratchetEncrypt(try DoubleRatchet.toString(try JSONEncoder().encode(rumor)))
        
        let sharedSecret = try NIP44v2Encryption.conversationKey(
            privateKeyA: state.ourCurrentNostrKey!.privkey,
            publicKeyB: state.theirNextNostrPublicKey
        )
        
        let encryptedHeader = try NIP44v2Encryption.encrypt(
            plaintext: try DoubleRatchet.toString(try JSONEncoder().encode(header)),
            conversationKey: sharedSecret
        )
        
        let nostrEvent = try NostrEvent.create(
            content: encryptedData,
            kind: DoubleRatchet.Constants.MESSAGE_EVENT_KIND,
            tags: [["header", encryptedHeader]],
            created_at: Int(now),
            privkey: state.ourCurrentNostrKey!.privkey
        )
        
        return (event: nostrEvent, innerEvent: rumor)
    }
    
    // MARK: - Private Methods - Nostr Subscription
    
    private func subscribeToNostrEvents() {
        // Implementation would depend on your Nostr client architecture
        // This would typically involve subscribing to events with:
        // - authors matching theirNextNostrPublicKey
        // - kind matching MESSAGE_EVENT_KIND
        // And calling handleNostrEvent for each received event
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

// These functions would need to be implemented based on your crypto implementation
func generatePrivateKey() -> Data {
    // Implementation needed
    fatalError("Not implemented")
}

func getPublicKey(privateKey: Data) -> Pubkey {
    // Implementation needed
    fatalError("Not implemented")
}

func getEventHash(_ event: DoubleRatchet.Rumor) -> String {
    // Implementation needed
    fatalError("Not implemented")
}

// MARK: - Helper Functions

private func bytesToData(_ bytes: [UInt8]) -> Data {
    return Data(bytes)
}

private func bytesToData(_ bytes: ContiguousBytes) -> Data {
    var data = Data()
    bytes.withUnsafeBytes { buffer in
        data.append(contentsOf: buffer)
    }
    return data
}

func kdf(_ input1: Data, _ input2: ContiguousBytes, _ numOutputs: Int) throws -> (Data, Data) {
    var saltData = Data()
    input2.withUnsafeBytes { buffer in
        saltData.append(contentsOf: buffer)
    }
    
    let prk = CryptoKit.HKDF<CryptoKit.SHA256>.extract(
        inputKeyMaterial: SymmetricKey(data: input1),
        salt: saltData
    )
    
    var outputs: [Data] = []
    for i in 1...numOutputs {
        let info = Data([UInt8(i)])
        let output = CryptoKit.HKDF<CryptoKit.SHA256>.expand(pseudoRandomKey: prk, info: info, outputByteCount: 32)
        outputs.append(Data(output.withUnsafeBytes { Data($0) }))
    }
    
    return (outputs[0], outputs[1])
}

// MARK: - NostrEvent Creation Helper

extension NostrEvent {
    static func create(content: String, kind: Int, tags: [[String]], created_at: Int, privkey: Data) throws -> NostrEvent {
        // Implementation needed based on your NostrEvent creation logic
        fatalError("Not implemented")
    }
}
