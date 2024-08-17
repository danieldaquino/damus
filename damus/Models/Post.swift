//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-05-07.
//

import Foundation

struct NostrPost {
    let kind: NostrKind
    let content: String
    let tags: [[String]]

    init(content: String, kind: NostrKind = .text, tags: [[String]] = []) {
        self.content = content
        self.kind = kind
        self.tags = tags
    }
    
    func to_event(keypair: FullKeypair) -> NostrEvent? {
        let post_blocks = self.parse_blocks()
        let post_tags = make_post_tags(post_blocks: post_blocks, tags: self.tags)
        let content = post_tags.blocks
            .map(\.asString)
            .joined(separator: "")
        
        if self.kind == .highlight {
            var new_tags = post_tags.tags.filter({ $0[safe: 0] != "comment" })
            new_tags.append(["comment", content])
            return NostrEvent(content: self.content, keypair: keypair.to_keypair(), kind: self.kind.rawValue, tags: new_tags)
        }
        
        return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: self.kind.rawValue, tags: post_tags.tags)
    }
    
    func parse_blocks() -> [Block] {
        guard let content_for_parsing = self.default_content_for_block_parsing() else { return [] }
        return parse_post_blocks(content: content_for_parsing)
    }
    
    private func default_content_for_block_parsing() -> String? {
        switch kind {
            case .highlight:
                return tags.filter({ $0[safe: 0] == "comment" }).first?[safe: 1]
            default:
                return self.content
        }
    }
}

func parse_post_blocks(content: String) -> [Block] {
    return parse_note_content(content: .content(content, nil)).blocks
}

