//
//  SessionManager.swift
//  damus
//
//  Created by Martti Malmi on 28.2.2025.
//

import Foundation

class SessionManager {
    private var invites: [Invite] = []
    private var sessions: [Session] = []
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
                maxUses: 1
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
                            self.sessions.append(session)
                            print("New session established from invite: \(invite.label ?? "unnamed") with \(pubkey?.description ?? "unknown")")
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
    
    func getSessions() -> [Session] {
        return sessions
    }
    
    func getSession(with id: String) -> Session? {
        return sessions.first { $0.name == id }
    }
    
    func removeSession(_ session: Session) {
        session.close()
        sessions.removeAll { $0.name == session.name }
    }
    
    func acceptInvite(_ invite: Invite) async throws -> Session {
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
        
        sessions.append(session)
        postbox.send(event)
        return session
    }
    
    // MARK: - Error Types
    
    enum SessionManagerError: Error {
        case noPrivateKey
        case sessionNotFound
    }
}
