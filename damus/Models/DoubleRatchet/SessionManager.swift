//
//  SessionManager.swift
//  damus
//
//  Created by Martti Malmi on 28.2.2025.
//

import Foundation
import Combine

class MessageRecord: ObservableObject {
    let rumor: DoubleRatchet.Rumor
    let isFromMe: Bool
    @Published var reactions: [Pubkey: String] = [:]
    
    init(event: DoubleRatchet.Rumor, isFromMe: Bool) {
        self.rumor = event
        self.isFromMe = isFromMe
    }
}

class SessionRecord: ObservableObject {
    let pubkey: Pubkey
    let session: Session
    @Published var messages: [String: MessageRecord]
    @Published var latest: DoubleRatchet.Rumor?
    
    init(pubkey: Pubkey, session: Session) {
        self.pubkey = pubkey
        self.session = session
        self.messages = [:]
    }
    
    func addEvent(_ rumor: DoubleRatchet.Rumor, isFromMe: Bool) {
        if rumor.kind == 6 {
            let eventTags = rumor.tags.filter { tag in
                tag.count > 1 && tag[0].string() == "e"
            }
            
            if !eventTags.isEmpty && rumor.content.count > 0 {
                let reactedEventId = eventTags[0][1].string()
                print("Received reaction \(rumor.content) for message \(reactedEventId) from \(rumor.pubkey.hex())")
                
                if let messageRecord = messages[reactedEventId] {
                    print("Found message, adding reaction")
                    messageRecord.reactions[rumor.pubkey] = rumor.content
                } else {
                    print("Message not found for reaction")
                }
            }
            return
        }
        
        let messageRecord = MessageRecord(event: rumor, isFromMe: isFromMe)
        messages[rumor.id] = messageRecord
        latest = rumor
    }
}

class SessionManager {
    private var invites: [Invite] = []
    private var sessions: [String: SessionRecord] = [:]
    private let pool: RelayPool
    private let keypair: Keypair
    private let postbox: PostBox
    
    init(keypair: Keypair, pool: RelayPool, postbox: PostBox) {
        self.keypair = keypair
        self.pool = pool
        self.postbox = postbox
        
        // Create default public and private invites
        createDefaultInvites()
    }
    
    // MARK: - Default Invites
    
    private func createDefaultInvites() {
        guard let _ = keypair.privkey else {
            print("Cannot create default invites: no private key available")
            return
        }
        
        // Check if we already have invites before creating defaults
        if !invites.isEmpty {
            return
        }
        
        do {
            // Create a public invite
            let publicInvite = try Invite.createNew(
                inviter: keypair.pubkey,
                label: "public",
                maxUses: nil
            )
            invites.append(publicInvite)
            
            // Create a private invite
            let privateInvite = try Invite.createNew(
                inviter: keypair.pubkey,
                label: "private",
                maxUses: nil
            )
            invites.append(privateInvite)
            
            // Set up listeners for the newly created invites
            for invite in invites {
                do {
                    let nostrSubscribe: DoubleRatchet.NostrSubscribe = { filter, callback in
                        let sub_id = UUID().uuidString
                        self.pool.subscribe(sub_id: sub_id, filters: [filter], handler: { _, event in
                            if case .nostr_event(let nostr_response) = event,
                               case .event(_, let ev) = nostr_response {
                                callback(ev)
                            }
                        })
                        return { self.pool.unsubscribe(sub_id: sub_id) }
                    }
                    
                    guard let privkey = keypair.privkey else {
                        throw SessionManagerError.noPrivateKey
                    }
                    
                    _ = try invite.listen(
                        decryptor: privkey,
                        nostrSubscribe: nostrSubscribe,
                        onSession: { [weak self] session, pubkey in
                            guard let self = self else { return }
                            if let pubkey = pubkey {
                                let sessionRecord = SessionRecord(pubkey: pubkey, session: session)
                                self.sessions[session.name] = sessionRecord
                                listenToMessages(sessionRecord)
                                print("New session established from invite: \(invite.label ?? "unnamed") with \(pubkey.description)")
                            }
                                                        
                            NotificationCenter.default.post(name: NSNotification.Name("NewSessionEstablished"), object: session)
                        }
                    )
                } catch {
                    print("Error listening for responses to invite \(invite.label ?? "unnamed"): \(error)")
                }
            }
        } catch {
            print("Error creating default invites: \(error)")
        }
    }
    
    // MARK: - Invite Management
    
    func createInvite(label: String? = nil, maxUses: Int? = nil) throws -> Invite {
        guard let privkey = keypair.privkey else {
            throw SessionManagerError.noPrivateKey
        }
        
        let invite = try Invite.createNew(
            inviter: keypair.pubkey,
            label: label,
            maxUses: maxUses
        )
        
        invites.append(invite)
        return invite
    }
    
    func getInvites() -> [Invite] {
        return invites
    }
    
    func removeInvite(_ invite: Invite) {
        invites.removeAll { $0.sharedSecret == invite.sharedSecret }
    }
    
    func importInviteFromUrl(_ url: URL) throws -> Invite {
        let invite = try Invite.fromUrl(url)
        invites.append(invite)
        return invite
    }
    
    func importInviteFromEvent(_ event: NostrEvent) throws -> Invite {
        let invite = try Invite.fromEvent(event)
        invites.append(invite)
        return invite
    }
    
    // MARK: - Session Management
    
    func getSessionRecords() -> [String: SessionRecord] {
        return sessions
    }
    
    func getSessionRecord(with id: String) -> SessionRecord? {
        return sessions[id]
    }
    
    func removeSession(_ session: Session) {
        session.close()
        sessions.removeValue(forKey: session.name)
    }

    func listenToMessages(_ sessionRecord: SessionRecord) {
        let eventHandler = sessionRecord.session.onEvent { rumor, eventReceived in
            print("Received event: \(rumor)")
            var myRumor = rumor
            myRumor.pubkey = sessionRecord.pubkey
            sessionRecord.addEvent(myRumor, isFromMe: false)
        }
    }
    
    func acceptInvite(_ invite: Invite) async throws -> SessionRecord {
        guard let privkey = keypair.privkey else {
            throw SessionManagerError.noPrivateKey
        }
        
        let nostrSubscribe: DoubleRatchet.NostrSubscribe = { filter, callback in
            let sub_id = UUID().uuidString
            self.pool.subscribe(sub_id: sub_id, filters: [filter], handler: { _, event in
                if case .nostr_event(let nostr_response) = event,
                   case .event(_, let ev) = nostr_response {
                    callback(ev)
                }
            })
            return { self.pool.unsubscribe(sub_id: sub_id) }
        }
        
        let (session, event) = try await invite.accept(
            nostrSubscribe: nostrSubscribe,
            inviteePublicKey: keypair.pubkey,
            encryptor: privkey
        )
        
        let sessionRecord = SessionRecord(pubkey: invite.inviter, session: session)
        sessions[session.name] = sessionRecord
        listenToMessages(sessionRecord)
        postbox.send(event)
        return sessionRecord
    }
    
    // MARK: - Error Types
    
    enum SessionManagerError: Error {
        case noPrivateKey
        case sessionNotFound
    }
}
