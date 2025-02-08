//
//  NostrEvent.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import CommonCrypto
import NostrSDK
import CryptoKit
import NaturalLanguage


enum ValidationResult: Decodable {
    case unknown
    case ok
    case bad_id
    case bad_sig
}

func sign_id(privkey: String, id: String) -> String {
    let keypair = NostrSDK.Keypair(hex: privkey)!

    let signature = try! keypair.privateKey.signatureForContent(id)

    return signature
}

func decode_nostr_event(txt: String) -> NostrResponse? {
    return NostrResponse.owned_from_json(json: txt)
}

func encode_json<T: Encodable>(_ val: T) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return (try? encode_json_data(val)).map { String(decoding: $0, as: UTF8.self) }
}

func encode_json_data<T: Encodable>(_ val: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return try encoder.encode(val)
}

func decode_nostr_event_json(json: String) -> NostrEvent? {
    return NostrEvent.owned_from_json(json: json)
}

func decode_json<T: Decodable>(_ val: String) -> T? {
    return try? JSONDecoder().decode(T.self, from: Data(val.utf8))
}

func decode_data<T: Decodable>(_ data: Data) -> T? {
    let decoder = JSONDecoder()
    do {
        return try decoder.decode(T.self, from: data)
    } catch {
        print("decode_data failed for \(T.self): \(error)")
    }

    return nil
}

func event_commitment(pubkey: Pubkey, created_at: UInt32, kind: UInt32, tags: [[String]], content: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    let str_data = try! encoder.encode(content)
    let content = String(decoding: str_data, as: UTF8.self)
    
    let tags_encoder = JSONEncoder()
    tags_encoder.outputFormatting = .withoutEscapingSlashes
    let tags_data = try! tags_encoder.encode(tags)
    let tags = String(decoding: tags_data, as: UTF8.self)

    return "[0,\"\(pubkey.hex())\",\(created_at),\(kind),\(tags),\(content)]"
}

func calculate_event_commitment(pubkey: Pubkey, created_at: UInt32, kind: UInt32, tags: [[String]], content: String) -> Data {
    let target = event_commitment(pubkey: pubkey, created_at: created_at, kind: kind, tags: tags, content: content)
    return target.data(using: .utf8)!
}

func calculate_event_id(pubkey: Pubkey, created_at: UInt32, kind: UInt32, tags: [[String]], content: String) -> NoteId {
    let commitment = calculate_event_commitment(pubkey: pubkey, created_at: created_at, kind: kind, tags: tags, content: content)
    return NoteId(sha256(commitment))
}


func sha256(_ data: Data) -> Data {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes {
        _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return Data(hash)
}

func hexchar(_ val: UInt8) -> UInt8 {
    if val < 10 {
        return 48 + val;
    }
    if val < 16 {
        return 97 + val - 10;
    }
    assertionFailure("impossiburu")
    return 0
}

func random_bytes(count: Int) -> Data {
    var bytes = [Int8](repeating: 0, count: count)
    guard
        SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess
    else {
        fatalError("can't copy secure random data")
    }
    return Data(bytes: bytes, count: count)
}

func make_boost_event(keypair: FullKeypair, boosted: NostrEvent) -> NostrEvent? {
    var tags = Array(boosted.referenced_pubkeys).map({ pk in pk.tag })

    tags.append(["e", boosted.id.hex(), "", "root"])
    tags.append(["p", boosted.pubkey.hex()])

    let content = event_to_json(ev: boosted)
    return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: 6, tags: tags)
}

func make_like_event(keypair: FullKeypair, liked: NostrEvent, content: String = "🤙") -> NostrEvent? {
    var tags = liked.tags.reduce(into: [[String]]()) { ts, tag in
        guard tag.count >= 2,
              (tag[0].matches_char("e") || tag[0].matches_char("p")) else {
            return
        }
        ts.append(tag.strings())
    }

    tags.append(["e", liked.id.hex()])
    tags.append(["p", liked.pubkey.hex()])

    return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: 7, tags: tags)
}

func generate_private_keypair(our_privkey: Privkey, id: NoteId, created_at: UInt32) -> FullKeypair? {
    let to_hash = our_privkey.hex() + id.hex() + String(created_at)
    guard let dat = to_hash.data(using: .utf8) else {
        return nil
    }
    let privkey_bytes = sha256(dat)
    let privkey = Privkey(privkey_bytes)
    guard let pubkey = privkey_to_pubkey(privkey: privkey) else { return nil }

    return FullKeypair(pubkey: pubkey, privkey: privkey)
}

func uniq<T: Hashable>(_ xs: [T]) -> [T] {
    var s = Set<T>()
    var ys: [T] = []
    
    for x in xs {
        if s.contains(x) {
            continue
        }
        s.insert(x)
        ys.append(x)
    }
    
    return ys
}

func gather_reply_ids(our_pubkey: Pubkey, from: NostrEvent) -> [RefId] {
    var ids: [RefId] = from.referenced_ids.first.map({ ref in [ .event(ref) ] }) ?? []

    let pks = from.referenced_pubkeys.reduce(into: [RefId]()) { rs, pk in
        if pk == our_pubkey {
            return
        }
        rs.append(.pubkey(pk))
    }

    ids.append(.event(from.id))
    ids.append(contentsOf: uniq(pks))

    if from.pubkey != our_pubkey {
        ids.append(.pubkey(from.pubkey))
    }

    return ids
}

func gather_quote_ids(our_pubkey: Pubkey, from: NostrEvent) -> [RefId] {
    var ids: [RefId] = [.quote(from.id.quote_id)]
    if from.pubkey != our_pubkey {
        ids.append(.pubkey(from.pubkey))
    }
    return ids
}

func event_from_json(dat: String) -> NostrEvent? {
    return NostrEvent.owned_from_json(json: dat)
}

func event_to_json(ev: NostrEvent) -> String {
    let encoder = JSONEncoder()
    guard let res = try? encoder.encode(ev) else {
        return "{}"
    }
    guard let str = String(data: res, encoding: .utf8) else {
        return "{}"
    }
    return str
}

func decrypt_dm(_ privkey: Privkey?, pubkey: Pubkey, content: String, encoding: EncEncoding) -> String? {
    guard let privkey = privkey else {
        return nil
    }
    guard let shared_sec = get_shared_secret(privkey: privkey, pubkey: pubkey) else {
        return nil
    }
    guard let dat = (encoding == .base64 ? decode_dm_base64(content) : decode_dm_bech32(content)) else {
        return nil
    }
    guard let dat = aes_decrypt(data: dat.content, iv: dat.iv, shared_sec: shared_sec) else {
        return nil
    }
    return String(data: dat, encoding: .utf8)
}

func decrypt_note(our_privkey: Privkey, their_pubkey: Pubkey, enc_note: String, encoding: EncEncoding) -> NostrEvent? {
    guard let dec = decrypt_dm(our_privkey, pubkey: their_pubkey, content: enc_note, encoding: encoding) else {
        return nil
    }
    
    return decode_nostr_event_json(json: dec)
}

func get_shared_secret(privkey: Privkey, pubkey: Pubkey) -> [UInt8]? {
    return try? LegacyEncryptedDirectMessageEvent.getSharedSecret(privateKey: privkey.toNSDKPrivateKey(), recipient: pubkey.toNSDKPublicKey())
}

enum EncEncoding {
    case base64
    case bech32
}

struct DirectMessageBase64 {
    let content: [UInt8]
    let iv: [UInt8]
}



func encode_dm_bech32(content: [UInt8], iv: [UInt8]) -> String {
    let content_bech32 = bech32_encode(hrp: "pzap", content)
    let iv_bech32 = bech32_encode(hrp: "iv", iv)
    return content_bech32 + "_" + iv_bech32
}

func decode_dm_bech32(_ all: String) -> DirectMessageBase64? {
    let parts = all.split(separator: "_")
    guard parts.count == 2 else {
        return nil
    }
    
    let content_bech32 = String(parts[0])
    let iv_bech32 = String(parts[1])
    
    guard let content_tup = try? bech32_decode(content_bech32) else {
        return nil
    }
    guard let iv_tup = try? bech32_decode(iv_bech32) else {
        return nil
    }
    guard content_tup.hrp == "pzap" else {
        return nil
    }
    guard iv_tup.hrp == "iv" else {
        return nil
    }
    
    return DirectMessageBase64(content: content_tup.data.bytes, iv: iv_tup.data.bytes)
}

func encode_dm_base64(content: [UInt8], iv: [UInt8]) -> String {
    let content_b64 = base64_encode(content)
    let iv_b64 = base64_encode(iv)
    return content_b64 + "?iv=" + iv_b64
}

func decode_dm_base64(_ all: String) -> DirectMessageBase64? {
    let splits = Array(all.split(separator: "?"))

    if splits.count != 2 {
        return nil
    }

    guard let content = base64_decode(String(splits[0])) else {
        return nil
    }

    var sec = String(splits[1])
    if !sec.hasPrefix("iv=") {
        return nil
    }

    sec = String(sec.dropFirst(3))
    guard let iv = base64_decode(sec) else {
        return nil
    }

    return DirectMessageBase64(content: content, iv: iv)
}

func base64_encode(_ content: [UInt8]) -> String {
    return Data(content).base64EncodedString()
}

func base64_decode(_ content: String) -> [UInt8]? {
    guard let dat = Data(base64Encoded: content) else {
        return nil
    }
    return dat.bytes
}

func aes_decrypt(data: [UInt8], iv: [UInt8], shared_sec: [UInt8]) -> Data? {
    return aes_operation(operation: CCOperation(kCCDecrypt), data: data, iv: iv, shared_sec: shared_sec)
}

func aes_encrypt(data: [UInt8], iv: [UInt8], shared_sec: [UInt8]) -> Data? {
    return aes_operation(operation: CCOperation(kCCEncrypt), data: data, iv: iv, shared_sec: shared_sec)
}

func aes_operation(operation: CCOperation, data: [UInt8], iv: [UInt8], shared_sec: [UInt8]) -> Data? {
    let data_len = data.count
    let bsize = kCCBlockSizeAES128
    let len = Int(data_len) + bsize
    var decrypted_data = [UInt8](repeating: 0, count: len)

    let key_length = size_t(kCCKeySizeAES256)
    if shared_sec.count != key_length {
        assert(false, "unexpected shared_sec len: \(shared_sec.count) != 32")
        return nil
    }

    let algorithm: CCAlgorithm = UInt32(kCCAlgorithmAES128)
    let options:   CCOptions   = UInt32(kCCOptionPKCS7Padding)

    var num_bytes_decrypted :size_t = 0

    let status = CCCrypt(operation,  /*op:*/
                         algorithm,  /*alg:*/
                         options,    /*options:*/
                         shared_sec, /*key:*/
                         key_length, /*keyLength:*/
                         iv,         /*iv:*/
                         data,       /*dataIn:*/
                         data_len, /*dataInLength:*/
                         &decrypted_data,/*dataOut:*/
                         len,/*dataOutAvailable:*/
                         &num_bytes_decrypted/*dataOutMoved:*/
    )

    if UInt32(status) != UInt32(kCCSuccess) {
        return nil
    }

    return Data(bytes: decrypted_data, count: num_bytes_decrypted)

}



func validate_event(ev: NostrEvent) -> ValidationResult {
    let nsdkEvent = ev.toNSDKEvent()
    do {
        try nsdkEvent.verifyEvent()
        return .ok
    }
    catch {
        if let error = error as? NostrSDK.EventVerifyingError {
            switch error {
            case .invalidId:
                return .bad_id
            case .unsignedEvent:
                return .unknown
            }
        }
        else if let error = error as? NostrSDK.SignatureVerifyingError {
            switch error {
            case .unexpectedSignatureLength:
                return .bad_sig
            case .unexpectedPublicKeyLength:
                return .unknown
            case .invalidMessage:
                return .bad_id
            case .invalidSignature:
                return .bad_sig
            }
        }
    }
    return .unknown
}

func first_eref_mention(ev: NostrEvent, keypair: Keypair) -> Mention<NoteId>? {
    let blocks = ev.blocks(keypair).blocks.filter { block in
        guard case .mention(let mention) = block else {
                return false
            }

        switch mention.ref {
        case .note, .nevent:
            return true
        default:
            return false
        }
    }
    
    /// MARK: - Preview
    if let firstBlock = blocks.first,
       case .mention(let mention) = firstBlock {
        switch mention.ref {
        case .note(let note_id):
            return .note(note_id)
        case .nevent(let nevent):
            return .note(nevent.noteid)
        default:
            return nil
        }
    }
    return nil
}

func separate_invoices(ev: NostrEvent, keypair: Keypair) -> [Invoice]? {
    let invoiceBlocks: [Invoice] = ev.blocks(keypair).blocks.reduce(into: []) { invoices, block in
        guard case .invoice(let invoice) = block else {
            return
        }
        invoices.append(invoice)
    }
    return invoiceBlocks.isEmpty ? nil : invoiceBlocks
}

/**
 Transforms a `NostrEvent` of known kind `NostrKind.like`to a human-readable emoji.
 If the known kind is not a `NostrKind.like`, it will return `nil`.
 If the event content is an empty string or `+`, it will map that to a heart ❤️ emoji.
 If the event content is a "-", it will map that to a dislike 👎 emoji.
 Otherwise, it will return the event content at face value without transforming it.
 */
func to_reaction_emoji(ev: NostrEvent) -> String? {
    guard ev.known_kind == NostrKind.like else {
        return nil
    }

    switch ev.content {
    case "", "+":
        return "❤️"
    case "-":
        return "👎"
    default:
        return ev.content
    }
}

extension NostrEvent {
    /// The mutelist for a given event
    ///
    /// If the event is not a mutelist it will return `nil`.
    var mute_list: Set<MuteItem>? {
        if (self.kind == NostrKind.list_deprecated.rawValue && self.referenced_params.contains(where: { p in p.param.matches_str("mute") })) || self.kind == NostrKind.mute_list.rawValue {
            return Set(self.referenced_mute_items)
        } else {
            return nil
        }
    }
}
