//
//  WalletModel.swift
//  damus
//
//  Created by William Casarin on 2023-05-09.
//

import Foundation

enum WalletConnectState {
    case new(WalletConnectURL)
    case existing(WalletConnectURL)
    case none
}

/// Models the user's NWC wallet based on the app's settings
class WalletModel: ObservableObject {
    var settings: UserSettingsStore
    private(set) var previous_state: WalletConnectState
    var initial_percent: Int
    @Published private(set) var balance: Int64 = 0
    @Published private(set) var transactions: [NWCTransaction] = []
    
    @Published private(set) var connect_state: WalletConnectState
    
    init(state: WalletConnectState, settings: UserSettingsStore) {
        self.connect_state = state
        self.previous_state = .none
        self.settings = settings
        self.initial_percent = settings.donation_percent
    }
    
    init(settings: UserSettingsStore) {
        self.settings = settings
        if let str = settings.nostr_wallet_connect,
           let nwc = WalletConnectURL(str: str) {
            self.previous_state = .existing(nwc)
            self.connect_state = .existing(nwc)
        } else {
            self.previous_state = .none
            self.connect_state = .none
        }
        self.initial_percent = settings.donation_percent
    }
    
    func cancel() {
        self.connect_state = previous_state
        self.objectWillChange.send()
    }
    
    func disconnect() {
        self.settings.nostr_wallet_connect = nil
        self.connect_state = .none
        self.previous_state = .none
    }
    
    func new(_ nwc: WalletConnectURL) {
        self.connect_state = .new(nwc)
    }
    
    func connect(_ nwc: WalletConnectURL) {
        self.settings.nostr_wallet_connect = nwc.to_url().absoluteString
        notify(.attached_wallet(nwc))
        self.connect_state = .existing(nwc)
        self.previous_state = .existing(nwc)
    }

    /// Handles an NWC response event and updates the model.
    ///
    /// This takes a response received from the NWC relay and updates the internal state of this model.
    ///
    /// - Parameter resp: The NWC response received from the network
    func nwc_info_success(resp: FullWalletResponse) {
        switch resp.response.result {
        case .get_balance(let balanceResp):
            self.balance = balanceResp.balance / 1000
        case .none:
            return
        case .some(.pay_invoice(_)):
            return
        case .list_transactions(let transactionsResp):
            self.transactions = transactionsResp.transactions
        }
    }
}
