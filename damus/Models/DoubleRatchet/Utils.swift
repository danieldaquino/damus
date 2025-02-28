import Foundation
import CryptoKit

extension DoubleRatchet {
    static func serializeSessionState(_ state: SessionState) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(SerializedState(
            version: 1,
            rootKey: state.rootKey.hex(),
            theirCurrentNostrPublicKey: state.theirCurrentNostrPublicKey,
            theirNextNostrPublicKey: state.theirNextNostrPublicKey,
            ourCurrentNostrKey: state.ourCurrentNostrKey.map { key in
                SerializedKeypair(
                    publicKey: key.pubkey,
                    privateKey: key.privkey.hex()
                )
            },
            ourNextNostrKey: SerializedKeypair(
                publicKey: state.ourNextNostrKey.pubkey,
                privateKey: state.ourNextNostrKey.privkey.hex()
            ),
            receivingChainKey: state.receivingChainKey?.hex(),
            sendingChainKey: state.sendingChainKey?.hex(),
            sendingChainMessageNumber: state.sendingChainMessageNumber,
            receivingChainMessageNumber: state.receivingChainMessageNumber,
            previousSendingChainMessageCount: state.previousSendingChainMessageCount,
            skippedKeys: state.skippedKeys.mapValues { value in
                SerializedSkippedKeys(
                    headerKeys: value.headerKeys.map { $0.hex() },
                    messageKeys: Dictionary(uniqueKeysWithValues: value.messageKeys.map { 
                        (String($0.key), $0.value.hex()) 
                    })
                )
            }
        ))
        return String(data: data, encoding: .utf8)!
    }
    
    static func deserializeSessionState(_ data: String) throws -> SessionState {
        let decoder = JSONDecoder()
        let serialized = try decoder.decode(SerializedState.self, from: Data(data.utf8))
        
        return SessionState(
            rootKey: Data(hex: serialized.rootKey),
            theirCurrentNostrPublicKey: serialized.theirCurrentNostrPublicKey,
            theirNextNostrPublicKey: serialized.theirNextNostrPublicKey,
            ourCurrentNostrKey: serialized.ourCurrentNostrKey.map { key in
                FullKeypair(
                    pubkey: key.publicKey,
                    privkey: Privkey(Data(hex: key.privateKey))
                )
            },
            ourNextNostrKey: FullKeypair(
                pubkey: serialized.ourNextNostrKey.publicKey,
                privkey: Privkey(Data(hex: serialized.ourNextNostrKey.privateKey))
            ),
            receivingChainKey: serialized.receivingChainKey.map { Data(hex: $0) },
            sendingChainKey: serialized.sendingChainKey.map { Data(hex: $0) },
            sendingChainMessageNumber: serialized.sendingChainMessageNumber,
            receivingChainMessageNumber: serialized.receivingChainMessageNumber,
            previousSendingChainMessageCount: serialized.previousSendingChainMessageCount,
            skippedKeys: serialized.skippedKeys.mapValues { value in
                SkippedKeys(
                    headerKeys: value.headerKeys.map { Data(hex: $0) },
                    messageKeys: Dictionary(uniqueKeysWithValues: value.messageKeys.map {
                        (Int($0.key)!, Data(hex: $0.value))
                    })
                )
            }
        )
    }
    
    static func createEventStream(_ session: Session) -> AsyncStream<Rumor> {
        var continuation: AsyncStream<Rumor>.Continuation?
        
        let stream = AsyncStream<Rumor> { cont in
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
    
    // MARK: - Private Types
    
    private struct SerializedState: Codable {
        let version: Int
        let rootKey: String
        let theirCurrentNostrPublicKey: Pubkey?
        let theirNextNostrPublicKey: Pubkey
        let ourCurrentNostrKey: SerializedKeypair?
        let ourNextNostrKey: SerializedKeypair
        let receivingChainKey: String?
        let sendingChainKey: String?
        let sendingChainMessageNumber: Int
        let receivingChainMessageNumber: Int
        let previousSendingChainMessageCount: Int
        let skippedKeys: [String: SerializedSkippedKeys]
    }
    
    private struct SerializedKeypair: Codable {
        let publicKey: Pubkey
        let privateKey: String
    }
    
    private struct SerializedSkippedKeys: Codable {
        let headerKeys: [String]
        let messageKeys: [String: String]
    }
    
    // MARK: - Helper Functions
    
    static func bytesToData(_ bytes: [UInt8]) -> Data {
        return Data(bytes)
    }
    
    static func bytesToData(_ bytes: ContiguousBytes) -> Data {
        var data = Data()
        bytes.withUnsafeBytes { buffer in
            data.append(contentsOf: buffer)
        }
        return data
    }
    
    static func kdf(_ input1: Data, _ input2: ContiguousBytes, _ numOutputs: Int) throws -> (Data, Data) {
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
}

// MARK: - Data Hex Extensions

extension Data {
    func hex() -> String {
        return self.map { String(format: "%02hhx", $0) }.joined()
    }
    
    init(hex: String) {
        self.init()
        var hex = hex
        while hex.count > 0 {
            let c = String(hex.prefix(2))
            hex = String(hex.dropFirst(2))
            let ch = UInt8(c, radix: 16) ?? 0
            self.append(ch)
        }
    }
} 