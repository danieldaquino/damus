//
//  NostrSDKAdapters.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-02-07.
//

import Foundation
import NostrSDK

extension NostrKind {
    func toNSDKEventKind() -> NostrSDK.EventKind {
        // Directly mapping the NostrKind to its raw integer value
        return EventKind(rawValue: Int(self.rawValue))
    }
}

extension NdbNote {
    func toNSDKEvent() -> NostrSDK.NostrEvent {
        return NostrSDK.NostrEvent(
            id: self.id.hex(),
            pubkey: self.pubkey.hex(),
            createdAt: Int64(self.created_at),
            kind: EventKind(rawValue: Int(self.kind)),
            tags: self.tags.toNSDKTags(),
            content: self.content,
            signature: self.sig.data.toHexString()
        )
    }
}

extension TagsSequence {
    func toNSDKTags() -> [NostrSDK.Tag] {
        return self.compactMap({ $0.toNSDKTag() })
    }
}

extension TagSequence {
    func toNSDKTag() -> NostrSDK.Tag? {
        return NostrSDK.Tag(strings: self.strings())
    }
}

extension FullKeypair {
    func toNSDKKeypair() -> NostrSDK.Keypair {
        return NostrSDK.Keypair(hex: self.privkey.hex())!   // We can guarantee at compile time that `hex()` yields a valid string, ok to force-unwrap
    }
}

extension Privkey {
    func toNSDKPrivateKey() -> NostrSDK.PrivateKey {
        return NostrSDK.PrivateKey(dataRepresentation: self.id)!    // Easy to guarantee this won't fail on runtime, ok to force-unwrap
    }
}

extension Pubkey {
    func toNSDKPublicKey() -> NostrSDK.PublicKey {
        return NostrSDK.PublicKey(dataRepresentation: self.id)!     // Easy to guarantee this won't fail on runtime, ok to force-unwrap
    }
}
