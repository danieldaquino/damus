import Foundation

enum DoubleRatchet {
    // MARK: - Core Types
    
    struct Header: Codable {
        let number: Int
        let previousChainLength: Int
        let nextPublicKey: Pubkey
    }
    
    struct SkippedKeys {
        var headerKeys: [Data]
        var messageKeys: [Int: Data]
    }
    
    struct SessionState {
        /// Root key used to derive new sending / receiving chain keys
        var rootKey: Data
        
        /// The other party's current Nostr public key
        var theirCurrentNostrPublicKey: Pubkey?
        
        /// The other party's next Nostr public key
        var theirNextNostrPublicKey: Pubkey
        
        /// Our current Nostr keypair used for this session
        var ourCurrentNostrKey: FullKeypair?
        
        /// Our next Nostr keypair, used when ratcheting forward
        var ourNextNostrKey: FullKeypair
        
        /// Key for decrypting incoming messages in current chain
        var receivingChainKey: Data?
        
        /// Key for encrypting outgoing messages in current chain
        var sendingChainKey: Data?
        
        /// Number of messages sent in current sending chain
        var sendingChainMessageNumber: Int
        
        /// Number of messages received in current receiving chain
        var receivingChainMessageNumber: Int
        
        /// Number of messages sent in previous sending chain
        var previousSendingChainMessageCount: Int
        
        /// Cache of message & header keys for handling out-of-order messages
        var skippedKeys: [String: SkippedKeys]
    }
    
    struct Rumor: Codable {
        var id: String
        let content: String
        let kind: Int
        let created_at: Int
        var tags: [[String]]
        let pubkey: Pubkey
    }
    
    // MARK: - Type Aliases
    
    typealias EventCallback = (Rumor, NostrEvent) -> Void
    typealias Unsubscribe = () -> Void
    
    // MARK: - Constants
    
    enum Constants {
        static let MESSAGE_EVENT_KIND = 1060
        static let INVITE_EVENT_KIND = 30078
        static let INVITE_RESPONSE_KIND = 1059
        static let CHAT_MESSAGE_KIND = 14
        static let MAX_SKIP = 1000
        static let DUMMY_PUBKEY = Pubkey(hex: "0000000000000000000000000000000000000000000000000000000000000000")!
    }
    
    // MARK: - Errors
    
    enum EncryptionError: Error {
        case tooManySkippedMessages
        case headerDecryptionFailed
        case notInitiator
    }
    
    // MARK: - Helper Extensions
    
    static func toString(_ data: Data) throws -> String {
        guard let str = String(data: data, encoding: .utf8) else {
            throw EncryptionError.headerDecryptionFailed
        }
        return str
    }
    
    static func toBytes(_ data: Data) -> [UInt8] {
        return [UInt8](data)
    }
    
    static func toData(_ bytes: [UInt8]) -> Data {
        return Data(bytes)
    }
}
