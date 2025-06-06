//
//  Id.swift
//  damus
//
//  Created by William Casarin on 2023-07-26.
//

import Foundation

struct TagRef<T>: Hashable, Equatable, Encodable {
    let elem: TagElem

    init(_ elem: TagElem) {
        self.elem = elem
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(elem.string())
    }
}

protocol TagKey {
    var keychar: AsciiCharacter { get }
}

protocol TagKeys {
    associatedtype TagKeys: TagKey
    var key: TagKeys { get }
}

protocol TagConvertible {
    var tag: [String] { get }
    static func from_tag(tag: TagSequence) -> Self?
}

/// Protocol for types that can be converted from/to a tag sequence with the possibilty of an error
protocol ThrowingTagConvertible {
    associatedtype E: Error
    var tag: [String] { get }
    static func fromTag(tag: TagSequence) throws(E) -> Self?
}

/// Protocol for types that can be converted from/to a tag item
protocol TagItemConvertible {
    var tagItem: String? { get }
    static func fromTagItem(_ item: String?) -> Self?
}

struct QuoteId: IdType, TagKey, TagConvertible {
    let id: Data
    
    init(_ data: Data) {
        self.id = data
    }
    
    /// The note id being quoted
    var note_id: NoteId {
        NoteId(self.id)
    }

    var keychar: AsciiCharacter { "q" }
    
    var tag: [String] {
        ["q", self.hex()]
    }
    
    static func from_tag(tag: TagSequence) -> QuoteId? {
        var i = tag.makeIterator()

        guard tag.count >= 2,
              let t0 = i.next(),
              let key = t0.single_char,
              key == "q",
              let t1 = i.next(),
              let quote_id = t1.id().map(QuoteId.init)
        else { return nil }

        return quote_id
    }
}


struct Privkey: IdType {
    let id: Data

    var nsec: String {
        bech32_privkey(self)
    }

    init?(hex: String) {
        guard let id = hex_decode_id(hex) else {
            return nil
        }
        self.init(id)
    }

    init(_ data: Data) {
        self.id = data
    }
}


struct Hashtag: TagConvertible, Hashable {
    let hashtag: String

    static func from_tag(tag: TagSequence) -> Hashtag? {
        var i = tag.makeIterator()

        guard tag.count >= 2,
              let t0 = i.next(),
              let chr = t0.single_char,
              chr == "t",
              let t1 = i.next() else {
            return nil
        }

        return Hashtag(hashtag: t1.string())
    }

    var tag: [String] { ["t", self.hashtag] }
    var keychar: AsciiCharacter { "t" }
}

struct ReplaceableParam: TagConvertible {
    let param: TagElem

    static func from_tag(tag: TagSequence) -> ReplaceableParam? {
        var i = tag.makeIterator()

        guard tag.count >= 2,
              let t0 = i.next(),
              let chr = t0.single_char,
              chr == "d",
              let t1 = i.next() else {
            return nil
        }

        return ReplaceableParam(param: t1)
    }

    var tag: [String] { [self.keychar.description, self.param.string()] }
    var keychar: AsciiCharacter { "d" }
}

struct Signature: Codable, Hashable, Equatable {
    let data: Data
    
    init(from decoder: Decoder) throws {
        self.init(try hex_decoder(decoder, expected_len: 64))
    }

    func encode(to encoder: Encoder) throws {
        try hex_encoder(to: encoder, data: self.data)
    }

    init(_ p: Data) {
        self.data = p
    }
}
