//
//  NIP37Draft.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-01-20.
//
import NostrSDK
import Foundation

/// This models a NIP-37 draft.
///
/// It is an immutable data structure that automatically makes both sides of a NIP-37 draft available: Its unwrapped form and wrapped form.
///
/// This is useful for keeping it or passing it around to other functions when both sides will be used, or it is not known which side of it will be used.
///
/// Just initialize it, and read its properties.
struct NIP37Draft {
    // MARK: Properties
    // Implementation note: Must be immutable to maintain integrity of the structure.
    
    /// The wrapped version of the draft. That is, a NIP-37 note with draft contents encrypted.
    let wrapped_note: NdbNote
    /// The unwrapped version of the draft. That is, the actual note that was being drafted.
    let unwrapped_note: NdbNote
    /// The unique ID of the draft, as per NIP-37
    var id: String? {
        return self.wrapped_note.referenced_params.first?.param.string()
    }
    
    
    // MARK: Initialization
    
    /// Basic initializer
    ///
    /// ## Implementation notes
    ///
    /// - Using this externally defeats the whole purpose of using this struct, so this is kept private.
    private init(wrapped_note: NdbNote, unwrapped_note: NdbNote) {
        self.wrapped_note = wrapped_note
        self.unwrapped_note = unwrapped_note
    }
    
    /// Initializes object with a wrapped NIP-37 note, if the keys can decrypt it.
    /// - Parameters:
    ///   - wrapped_note: NIP-37 note
    ///   - keypair: The keys to decrypt
    init?(wrapped_note: NdbNote, keypair: FullKeypair) throws {
        self.wrapped_note = wrapped_note
        guard let unwrapped_note = try Self.unwrap(note: wrapped_note, keypair: keypair) else { return nil }
        self.unwrapped_note = unwrapped_note
    }
    
    /// Initializes object with an event to be wrapped into a NIP-37 draft
    /// - Parameters:
    ///   - unwrapped_note: a note to be wrapped
    ///   - draft_id: the unique ID of this draft, as per NIP-37
    ///   - keypair: the keys to use for encrypting
    init?(unwrapped_note: NdbNote, draft_id: String, keypair: FullKeypair) throws {
        self.unwrapped_note = unwrapped_note
        guard let wrapped_note = try Self.wrap(note: unwrapped_note, draft_id: draft_id, keypair: keypair) else { return nil }
        self.wrapped_note = wrapped_note
    }
    
    
    // MARK: Static functions
    // Use these when you just need to wrap/unwrap once
    
    
    /// A function that wraps a note into NIP-37 draft event
    /// - Parameters:
    ///   - note: the note that needs to be wrapped
    ///   - draft_id: the unique ID of the draft, as per NIP-37
    ///   - keypair: the keys to use for encrypting
    /// - Returns: A NIP-37 draft, if it succeeds.
    static func wrap(note: NdbNote, draft_id: String, keypair: FullKeypair) throws -> NdbNote? {
        let jsonData = try JSONEncoder().encode(note)
        guard let noteJSONString = String(data: jsonData, encoding: .utf8) else {
            throw NIP37DraftEventError.encoding_error
        }
        //--
        let draftPrivateWrapEvent = try DraftPrivateWrapEvent.Builder()
            .identifier(draft_id)
            .draftEventKind(EventKind(rawValue: Int(note.kind)))
            .appendAnchorEvents(anchorEventTag1, anchorEventTag2)
            .appendAnchorEventAddresses(anchorEventAddress1, anchorEventAddress2)
            .draftContent(note.toNSDKEvent(), encryptedWith: keypair.toNSDKKeypair())
            .build(signedBy: .test)
        //--

        builder.appendTags(["d": draft_id, "k": String(note.kind)])
        if let repliedToNote = note.direct_replies() {
            builder.appendAnchorEvents(["e": repliedToNote.hex()])
        }

        guard let draftEvent = try? builder.build() else { return nil }
        return NdbNote.from(draftEvent) // Assuming implementation of from() method
    }
    
    /// A function that unwraps and decrypts a NIP-37 draft
    /// - Parameters:
    ///   - note: NIP-37 note to be unwrapped
    ///   - keypair: The keys to use for decrypting
    /// - Returns: The unwrapped note, if it can be decrypted/unwrapped.
    static func unwrap(note: NdbNote, keypair: FullKeypair) throws -> NdbNote? {
        guard note.known_kind == .draft else { return nil }
        let draftEvent = DraftPrivateWrapEvent.from(note: note) // Assuming cast or init
        guard let unwrappedEvent = try? draftEvent.draftEvent(decryptedWith: keypair) else {
            throw NIP37DraftEventError.decryptionFailed
        }
        return NdbNote.from(unwrappedEvent) // Assuming implementation of from() method
    }
    
    enum NIP37DraftEventError: Error {
        case invalid_keypair
        case encoding_error
    }
}

// MARK: - Convenience extensions


