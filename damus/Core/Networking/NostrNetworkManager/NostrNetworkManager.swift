//
//  NostrNetworkManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-02-26.
//
import Foundation

/// Manages interactions with the Nostr Network.
///
/// This delineates a layer that is responsible for doing mid-level management of interactions with the Nostr network, controlling lower-level classes that perform more network/DB specific code, and providing an easier to use and more semantic interfaces for the rest of the app.
///
/// This is responsible for:
/// - Managing the user's relay list
/// - Establishing a `RelayPool` and maintaining it in sync with the user's relay list as it changes
/// - Abstracting away complexities of interacting with the nostr network, providing an easier-to-use interface to fetch and send content related to the Nostr network
///
/// This is **NOT** responsible for:
/// - Doing actual storage of relay list (delegated via the delegate
/// - Handling low-level relay logic (this will be delegated to lower level classes used in RelayPool/RelayConnection)
class NostrNetworkManager {
    /// The relay pool that we manage
    ///
    /// ## Implementation notes
    ///
    /// - This will be marked `private` in the future to prevent other code from accessing the relay pool directly. Code outside this layer should use a higher level interface
    private let pool: RelayPool // TODO: Make this private and make higher level interface for classes outside the NostrNetworkManager
    /// A delegate that allows us to interact with the rest of app without introducing hard or circular dependencies
    private var delegate: Delegate
    /// Manages the user's relay list, controls RelayPool's connected relays
    let userRelayList: UserRelayListManager
    /// Handles sending out notes to the network
    let postbox: PostBox
    /// Handles subscriptions and functions to read or consume data from the Nostr network
    let reader: SubscriptionManager
    
    init(delegate: Delegate) {
        self.delegate = delegate
        let pool = RelayPool(ndb: delegate.ndb, keypair: delegate.keypair)
        self.pool = pool
        let reader = SubscriptionManager(pool: pool, ndb: delegate.ndb)
        let userRelayList = UserRelayListManager(delegate: delegate, pool: pool, reader: reader)
        self.reader = reader
        self.userRelayList = userRelayList
        self.postbox = PostBox(pool: pool)
    }
    
    // MARK: - Control functions
    
    /// Connects the app to the Nostr network
    func connect() {
        self.userRelayList.connect()
    }
    
    func ping() {
        self.pool.ping()
    }

    func relaysForEvent(event: NostrEvent) -> [RelayURL] {
        // TODO(tyiu) Ideally this list would be sorted by the event author's outbox relay preferences
        // and reliability of relays to maximize chances of others finding this event.
        if let relays = pool.seen[event.id] {
            return Array(relays)
        }

        return []
    }
    
    // TODO: ORGANIZE THESE
    
    // MARK: - Communication with the Nostr Network
    /// ## Implementation notes
    ///
    /// - This class hides the relay pool on purpose to avoid other code from dealing with complex relay + nostrDB logic.
    /// - Instead, we provide an easy to use interface so that normal code can just get the info they want.
    /// - This is also to help us migrate to the relay model.
    // TODO: Define a better interface. This is a temporary scaffold to replace direct relay pool access. After that is done, we can refactor this interface to be cleaner and reduce non-sense.
    
    func sendToNostrDB(event: NostrEvent) {
        self.pool.send_raw_to_local_ndb(.typical(.event(event)))
    }
    
    func send(event: NostrEvent) {
        self.pool.send(.event(event))
    }
    
    /// Subscribes to data from Nostr
    func subscribe(filters: [NostrFilter], to: [RelayURL]? = nil) -> AsyncStream<RelayPool.StreamItem> {
        return self.pool.subscribe(filters: filters, to: to)
        /// TODO: To implement local relay model, replace the RelayPool stream with a NostrDB stream (that also gets RelayPool data).
        ///
        /// Something like this:
        ///
        /// ```pseudo-swift
        /// return AsyncStream<RelayPool.StreamItem> { continuation in
        ///     let ndbStreamTask = Task {
        ///         for await ndbEvent in ndb.query(filters) {
        ///             continuation.yield(.event(ndbEvent))
        ///         }
        ///         continuation.yield(.eose)
        ///         for await ndbEvent in ndb.stream(filters) {
        ///             continuation.yield(ndbEvent)
        ///         }
        ///     }
        ///     let networkStreamTask = Task {
        ///         for await item in pool.subscribe(filters) {
        ///             guard case .event(let event) = item else { continue }
        ///             ndb.ingest(event)
        ///         }
        ///     }
        ///     continuation.onTermination = {
        ///         ndbStreamTask.cancel()
        ///         networkStreamTask.cancel()
        ///     }
        /// }
        /// ```
    }
    
    func query(filters: [NostrFilter], to: [RelayURL]? = nil) async -> [NostrEvent] {
        var events: [NostrEvent] = []
        for await item in self.subscribe(filters: filters, to: to) {
            switch item {
            case .event(let event):
                events.append(event)
            case .eose:
                break
            }
        }
        return events
    }
    
    /// Finds a replaceable event based on an `naddr` address.
    ///
    /// - Parameters:
    ///   - naddr: the `naddr` address
    func lookup(naddr: NAddr) async -> NostrEvent? {
        var nostrKinds: [NostrKind]? = NostrKind(rawValue: naddr.kind).map { [$0] }

        let filter = NostrFilter(kinds: nostrKinds, authors: [naddr.author])
        
        for await item in self.subscribe(filters: [filter]) {
            switch item {
            case .event(let event):
                if event.referenced_params.first?.param.string() == naddr.identifier {
                    return event
                }
            case .eose:
                break
            }
        }
        return nil
    }
    
    // TODO: Improve this. This is mostly intact to keep compatibility with its predecessor, but we can do much better
    func findEvent(query: FindEvent) async -> FoundEvent? {
        var filter: NostrFilter? = nil
        let find_from = query.find_from
        let query = query.type
        
        switch query {
        case .profile(let pubkey):
            if let profile_txn = delegate.ndb.lookup_profile(pubkey),
               let record = profile_txn.unsafeUnownedValue,
               record.profile != nil
            {
                return .profile(pubkey)
            }
            filter = NostrFilter(kinds: [.metadata], limit: 1, authors: [pubkey])
        case .event(let evid):
            if let event = delegate.ndb.lookup_note(evid)?.unsafeUnownedValue?.to_owned() {
                return .event(event)
            }
            filter = NostrFilter(ids: [evid], limit: 1)
        }
        
        var attempts: Int = 0
        var has_event = false
        guard let filter else { return nil }
        
        for await item in self.subscribe(filters: [filter], to: find_from) {
            switch item {
            case .event(let event):
                switch query {
                case .profile:
                    if event.known_kind == .metadata {
                        return .profile(event.pubkey)
                    }
                case .event:
                    return .event(event)
                }
            case .eose:
                return nil
            }
        }
        return nil
    }
    
    func ping() {
        self.pool.ping()
    }
    
    func connect() {
        self.userRelayList.load()
        self.pool.connect()
    }
    
    func disconnect() {
        self.pool.disconnect()
    }
    
    func getRelay(_ id: RelayURL) -> RelayPool.Relay? {
        pool.get_relay(id)
    }
    
    var connectedRelays: [RelayPool.Relay] {
        self.pool.relays
    }
    
    var ourRelayDescriptors: [RelayPool.RelayDescriptor] {
        self.pool.our_descriptors
    }
    
    // TODO: Move this to NWCManager
    @discardableResult
    func nwcPay(url: WalletConnectURL, post: PostBox, invoice: String, delay: TimeInterval? = 5.0, on_flush: OnFlush? = nil) -> NostrEvent? {
        let req = make_wallet_pay_invoice_request(invoice: invoice)
        guard let ev = make_wallet_connect_request(req: req, to_pk: url.pubkey, keypair: url.keypair) else {
            return nil
        }

        try? pool.add_relay(.nwc(url: url.relay))
        subscribe_to_nwc(url: url, pool: pool)
        post.send(ev, to: [url.relay], skip_ephemeral: false, delay: delay, on_flush: on_flush)
        return ev
    }
    
    // MARK: - App lifecycle functions
    
    func close() {
        pool.close()
    }
}


// MARK: - Helper types

extension NostrNetworkManager {
    /// The delegate that provides information and structure for the `NostrNetworkManager` to function.
    ///
    /// ## Implementation notes
    ///
    /// This is needed to prevent a circular reference between `DamusState` and `NostrNetworkManager`, and reduce coupling.
    protocol Delegate: Sendable {
        /// NostrDB instance, used with `RelayPool` to send events for ingestion.
        var ndb: Ndb { get }
        
        /// The keypair to use for relay authentication and updating relay lists
        var keypair: Keypair { get }
        
        /// The latest relay list event id hex
        var latestRelayListEventIdHex: String? { get set }  // TODO: Update this once we have full NostrDB query support
        
        /// The latest contact list `NostrEvent`
        ///
        /// Note: Read-only access, because `NostrNetworkManager` does not manage contact lists.
        var latestContactListEvent: NostrEvent? { get }
        
        /// Default bootstrap relays to start with when a user relay list is not present
        var bootstrapRelays: [RelayURL] { get }
        
        /// Whether the app is in developer mode
        var developerMode: Bool { get }
        
        /// The cache of relay model information
        var relayModelCache: RelayModelCache { get }
        
        /// Relay filters
        var relayFilters: RelayFilters { get }
        
        /// The user's connected NWC wallet
        var nwcWallet: WalletConnectURL? { get }
    }
}
