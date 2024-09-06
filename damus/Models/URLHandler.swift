//
//  URLHandler.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-09-06.
//

import Foundation

protocol DamusURLHandler {
    func compute_action(url: URL) -> ContentView.OpenAction
}

struct URLHandler: DamusURLHandler {
    let damus_state: DamusState
    
    func compute_action(url: URL) -> ContentView.OpenAction {
        on_open_url(state: damus_state!, url: url) { res in
            guard let res else {
                return
            }
            
            switch res {
                case .filter(let filt): self.open_search(filt: filt)
                case .profile(let pk):  self.open_profile(pubkey: pk)
                case .event(let ev):    self.open_event(ev: ev)
                case .wallet_connect(let nwc): self.open_wallet(nwc: nwc)
                case .script(let data): self.open_script(data)
                case .purple(let purple_url):
                    if case let .welcome(checkout_id) = purple_url.variant {
                        // If this is a welcome link, do the following before showing the onboarding screen:
                        // 1. Check if this is legitimate and good to go.
                        // 2. Mark as complete if this is good to go.
                        Task {
                            let is_good_to_go = try? await damus_state.purple.check_and_mark_ln_checkout_is_good_to_go(checkout_id: checkout_id)
                            if is_good_to_go == true {
                                self.active_sheet = .purple(purple_url)
                            }
                        }
                    }
                    else {
                        self.active_sheet = .purple(purple_url)
                    }
            }
        }
    }
}

enum OpenResult {
    case profile(Pubkey)
    case filter(NostrFilter)
    case event(NostrEvent)
    case wallet_connect(WalletConnectURL)
    case script([UInt8])
    case purple(DamusPurpleURL)
}

func find_open(state: DamusState, url: URL) -> OpenResult? {
    if let purple_url = DamusPurpleURL(url: url) {
        return .purple(purple_url)
    }
    
    if let nwc = WalletConnectURL(str: url.absoluteString) {
        return .wallet_connect(nwc)
    }
    
    guard let link = decode_nostr_uri(url.absoluteString) else {
        result(nil)
        return
    }
    
    switch link {
    case .ref(let ref):
        switch ref {
        case .pubkey(let pk):
            result(.profile(pk))
        case .event(let noteid):
            find_event(state: state, query: .event(evid: noteid)) { res in
                guard let res, case .event(let ev) = res else { return }
                result(.event(ev))
            }
        case .hashtag(let ht):
            result(.filter(.filter_hashtag([ht.hashtag])))
        case .param, .quote, .reference:
            // doesn't really make sense here
            break
        case .naddr(let naddr):
            naddrLookup(damus_state: state, naddr: naddr) { res in
                guard let res = res else { return }
                result(.event(res))
            }
        }
    case .filter(let filt):
        result(.filter(filt))
        break
        // TODO: handle filter searches?
    case .script(let script):
        result(.script(script))
        break
    }
}
