//
//  ContactListRecoveryWizard.swift
//  damus
//
//  Created by Daniel D‘Aquino on 2024-09-13.
//

import SwiftUI

struct ContactListRecoveryWizardView: View {
    let damus_state: DamusState
    @State private var search_relays: [String] = ["wss://relay.damus.io", "wss://nos.lol"]
    @State private var current_page: Int = 1
    
    var body: some View {
        TabView(selection: $current_page) {
            WizardRelayPage(damus_state: damus_state, relays: $search_relays, next_page: { current_page += 1 })
                .tabItem { Text("Select relays") }
                .tag(1)
            ContactListSearchPage(damus_state: damus_state, relay_inputs: search_relays)
                .tabItem { Text("Search and select contact lists") }
                .tag(2)
            Text("Done")
                .tabItem { Text("Apply settings") }
                .tag(3)
        }
        .tabViewStyle(.page)
        .onAppear(perform: {
            let current_relays = damus_state.pool.relays.map({ $0.descriptor.url.absoluteString })
            let bootstrap_relays = damus_state.bootstrap_relays.map({ $0.absoluteString })
            var all_relays = current_relays + bootstrap_relays
            if all_relays.count == 0 { all_relays = [""] }
            self.search_relays = all_relays
        })
    }
}

fileprivate struct WizardRelayPage: View {
    let damus_state: DamusState
    @Binding var relays: [String]
    let next_page: () -> Void

    var body: some View {
        Form {
            Text("Select relays to search", comment: "Title for contact list recovery wizard, where the user selects relays to search their contact list on.")
                .font(.title)
            
            Section {
                ForEach(relays.indices, id: \.self) { index in
                    TextField("Relay URL", text: $relays[index])
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .onDelete(perform: deleteItem)
                
                Button(action: {
                    relays.append("")
                }, label: {
                    Text("Add relay", comment: "Button to add relay to the list of relays to search contact list on")
                })
                
                EditButton()
            }
            
            if relays.count > 0 {
                Button(action: {
                    self.next_page()
                }, label: {
                    Text("Next", comment: "Button to go to the next step in wizard")
                })
            }
        }
    }

    func deleteItem(at offsets: IndexSet) {
        relays.remove(atOffsets: offsets)
    }
}

fileprivate struct ContactListSearchPage: View {
    let damus_state: DamusState
    let relay_inputs: [String]
    @State var search_state: SearchState
    @State var all_found_lists: [NdbNote] = []
    
    init(damus_state: DamusState, relay_inputs: [String]) {
        self.damus_state = damus_state
        self.relay_inputs = relay_inputs
        self.search_state = SearchState(from: relay_inputs)
    }

    var body: some View {
        ScrollView {
            VStack {
                self.search_state_view
                
                Button(action: {
                    all_found_lists = search_state.all_found_lists()
                }, label: {
                    Text("Show lists that were found")
                })
                
                List(all_found_lists) {
                    Text("List with \($0.tags.count) tags from \(Date(timeIntervalSince1970: TimeInterval($0.created_at)).formatted())")
                }
                
                ForEach(all_found_lists) {
                    Text("List with \($0.tags.count) tags from \(Date(timeIntervalSince1970: TimeInterval($0.created_at)).formatted())")
                }
                
            }
        }
        .onAppear(perform: {
            self.find_contact_lists()
        })
    }
    
    var search_state_view: some View {
        ForEach(search_state.relay_items, id: \.self) { relay_item in
            RelayStatusItemView(item: relay_item)
        }
    }
    
    func find_contact_lists() {
        let relay_pool = RelayPool(ndb: damus_state.ndb, keypair: damus_state.keypair)
        for (item_index, relay_item) in search_state.relay_items.enumerated() {
            try? self.search_state.update(index: item_index, state: .connecting)
            guard let relay_url = RelayURL(relay_item.relay) else {
                try? self.search_state.update(index: item_index, state: .failed(error_message: NSLocalizedString("Invalid URL", comment: "Error message indicating an invalid URL was input")))
                continue
            }
            do {
                try relay_pool.add_relay(RelayDescriptor(url: relay_url, info: RelayInfo.rw))
            }
            catch {
                try? self.search_state.update(index: item_index, state: .failed(error_message: error.localizedDescription))
            }
        }
        let our_contact_list_filter = NostrFilter(
            kinds: [NostrKind.contacts],
            authors: [damus_state.pubkey]
        )
        relay_pool.subscribe(
            sub_id: UUID().uuidString,
            filters: [our_contact_list_filter],
            handler: { relay_url, connection_event in
                switch connection_event {
                    case .ws_event(let ws_event):
                        switch ws_event {
                            case .connected:
                                try? self.search_state.update(relay_url: relay_url, state: .loading(lists_found: []))
                            case .message:
                                return
                            case .disconnected(_, _):
                                let lists_found = self.search_state.state_for(relay_url: relay_url)?.lists_found() ?? []
                                if lists_found.count > 0 {
                                    try? self.search_state.update(relay_url: relay_url, state: .done(lists_found: lists_found))
                                }
                            case .error(let error):
                                try? self.search_state.update(relay_url: relay_url, state: .failed(error_message: error.localizedDescription))
                        }
                    case .nostr_event(let response):
                        switch response {
                            case .event(_, let nostr_event):
                                self.search_state.add_list(nostr_event, to: relay_url)
                            case .eose(_):
                                let lists_found = self.search_state.state_for(relay_url: relay_url)?.lists_found() ?? []
                                try? self.search_state.update(relay_url: relay_url, state: .done(lists_found: lists_found))
                            case .ok, .notice:
                                return
                            case .auth(_):
                                try? self.search_state.update(relay_url: relay_url, state: .failed(error_message: NSLocalizedString("Auth required, but not supported by this wizard", comment: "error message")))
                        }
                }
            }
        )
    }
}

// MARK: - Helper structures

extension ContactListSearchPage {
    fileprivate struct RelayStatusItemView: View {
        let item: SearchState.RelayStatusItem
        
        var body: some View {
            HStack {
                Text(item.relay)
                switch item.state {
                    case .not_started:
                        Text("Not started")
                    case .connecting:
                        Text("Connecting")
                    case .failed(let error_message):
                        Text("Failed: \(error_message)")
                    case .loading(let lists_found):
                        Text("Loading… Found: \(lists_found.count) items")
                    case .done(let lists_found):
                        Text("Done. Found: \(lists_found.count) items")
                }
            }
        }
    }
}

extension ContactListSearchPage {
    fileprivate struct SearchState {
        var relay_items: [RelayStatusItem]
        
        init(from relays: [String]) {
            self.relay_items = relays.map({ RelayStatusItem(relay: $0) })
        }
        
        // MARK: Getting information
        
        func state_for(relay_url: RelayURL) -> RelayStatusItem.State? {
            return self.relay_item_for(relay_url: relay_url)?.state
        }
        
        func relay_item_for(relay_url: RelayURL) -> RelayStatusItem? {
            for relay_item in relay_items {
                if relay_url.absoluteString == relay_item.relay {
                    return relay_item
                }
            }
            return nil
        }
        
        func all_found_lists() -> [NdbNote] {
            var found_lists: [NdbNote] = []
            for relay_item in relay_items {
                found_lists.append(contentsOf: relay_item.state.lists_found())
            }
            return found_lists
        }
        
        // MARK: Updating states
        
        mutating func update(index: Int, state: RelayStatusItem.State) throws {
            guard self.relay_items[safe: index] != nil else {
                throw SearchStateError.no_such_item
            }
            self.relay_items[index].state = state
        }
        
        mutating func update(relay_url: RelayURL, state: RelayStatusItem.State) throws {
            for (item_index, relay_item) in relay_items.enumerated() {
                if relay_url.absoluteString == relay_item.relay {
                    try self.update(index: item_index, state: state)
                }
            }
        }
        
        mutating func add_list(_ list: NostrEvent, to relay_url: RelayURL) {
            var lists = self.state_for(relay_url: relay_url)?.lists_found() ?? []
            lists.append(list)
            try? self.update(relay_url: relay_url, state: .loading(lists_found: lists))
        }
        
        // MARK: Helpers
        
        enum SearchStateError: Error {
            case no_such_item
        }
        
        struct RelayStatusItem: Hashable {
            let relay: String
            var state: State = .not_started
            
            enum State: Hashable {
                case not_started
                case connecting
                case failed(error_message: String)
                case loading(lists_found: [NdbNote])
                case done(lists_found: [NdbNote])
                
                func lists_found() -> [NdbNote] {
                    switch self {
                        case .not_started, .connecting, .failed:
                            return []
                        case .loading(lists_found: let lists_found):
                            return lists_found
                        case .done(lists_found: let lists_found):
                            return lists_found
                    }
                }
            }
        }
    }
}

#Preview {
    ContactListRecoveryWizardView(damus_state: test_damus_state)
}
