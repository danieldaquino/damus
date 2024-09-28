//
//  PostingTimelineView.swift
//  damus
//
//  Created by eric on 7/15/24.
//

import SwiftUI

struct PostingTimelineView: View {
    
    let damus_state: DamusState
    var home: HomeModel
    @ObservedObject var selected_user_list: UserListModel
    @State var search: String = ""
    @State var results: [NostrEvent] = []
    @State var initialOffset: CGFloat?
    @State var offset: CGFloat?
    @State var showSearch: Bool = true
    @Binding var active_sheet: Sheets?
    @FocusState private var isSearchFocused: Bool
    @State private var contentOffset: CGFloat = 0
    @State private var indicatorWidth: CGFloat = 0
    @State private var indicatorPosition: CGFloat = 0
    @SceneStorage("PostingTimelineView.filter_state") var filter_state : FilterState = .posts_and_replies
    
    var mystery: some View {
        Text("Are you lost?", comment: "Text asking the user if they are lost in the app.")
        .id("what")
    }

    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: damus_state)
        filters.append(fstate.filter)
        
        return ContentFilters(filters: filters).filter
    }
    
    func contentTimelineView(filter: (@escaping (NostrEvent) -> Bool)) -> some View {
        let events = selected_user_list.events ?? home.events
        return TimelineView(events: events, loading: .constant(false), damus: damus_state, show_friend_icon: false, filter: filter) {
            PullDownSearchView(state: damus_state, on_cancel: {})
        }
    }

    var body: some View {
        VStack {
            ZStack {
                TabView(selection: $filter_state) {
                    // This is needed or else there is a bug when switching from the 3rd or 2nd tab to first. no idea why.
                    mystery
                    
                    contentTimelineView(filter: content_filter(.posts))
                        .tag(FilterState.posts)
                        .id(FilterState.posts)
                    contentTimelineView(filter: content_filter(.posts_and_replies))
                        .tag(FilterState.posts_and_replies)
                        .id(FilterState.posts_and_replies)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                if damus_state.keypair.privkey != nil {
                    PostButtonContainer(is_left_handed: damus_state.settings.left_handed) {
                        self.active_sheet = .post(.posting(.none))
                    }
                }
            }
        }
        .onAppear {
            if let selected_user_list {
                selected_user_list.subscribe()
            }
        }
        .onDisappear {
            if let selected_user_list {
                selected_user_list.unsubscribe()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CustomPicker(tabs: [
                    (NSLocalizedString("Notes", comment: "Label for filter for seeing only notes (instead of notes and replies)."), FilterState.posts),
                    (NSLocalizedString("Notes & Replies", comment: "Label for filter for seeing notes and replies (instead of only notes)."), FilterState.posts_and_replies)
                  ],
                selection: $filter_state)

                Divider()
                    .frame(height: 1)
            }
            .background(DamusColors.adaptableWhite)
        }
    }
}

enum UserListSelection: CaseIterable {
    case following
    case favorites
    
    func heading() -> String {
        switch self {
            case .following:
                return NSLocalizedString("Following", comment: "Heading for selected user list")
            case .favorites:
                return NSLocalizedString("My favorites", comment: "Heading for selected user list")
        }
    }
    
    func pubkeys() -> [Pubkey]? {
        switch self {
            case .following:
                return nil
            case .favorites:
                // TODO: Make this not hard-coded
                return [
                    Pubkey(hex: "8b2be0a0ad34805d76679272c28a77dbede9adcbfdca48c681ec8b624a1208a6")!,
                    Pubkey(hex: "ee6ea13ab9fe5c4a68eaf9b1a34fe014a66b40117c50ee2a614f4cda959b6e74")!,
                ]
        }
    }
    
    func model(pool: RelayPool) -> UserListModel? {
        guard let pubkeys = self.pubkeys() else { return nil }
        return UserListModel(pubkeys: pubkeys, pool: pool)
    }
}

class UserListModel: ObservableObject {
    @Published var events: EventHolder
    var pubkeys: [Pubkey]
    let pool: RelayPool
    let subscription_id = UUID().description
    
    init(pubkeys: [Pubkey], pool: RelayPool) {
        self.events = EventHolder()
        self.pubkeys = pubkeys
        self.pool = pool
    }
    
    func subscribe() {
        let filter = NostrFilter(
            kinds: [.text, .longform, .boost, .highlight],
            since: nil,  // TODO: Check this
            limit: 500,
            authors: self.pubkeys
        )
        pool.subscribe(sub_id: subscription_id, filters: [filter], handler: self.handle_event)
    }
    
    func unsubscribe() {
        self.pool.unsubscribe(sub_id: subscription_id)
    }
    
    func handle_event(relay_id: RelayURL, ev: NostrConnectionEvent) {
        let (sub_id, done) = handle_subid_event(pool: pool, relay_id: relay_id, ev: ev) { sid, ev in
            guard subscription_id == sid else {
                return
            }
            
            _ = self.events.insert(ev)
        }
    }
}
