//
//  WalletView.swift
//  damus
//
//  Created by William Casarin on 2023-05-05.
//

import SwiftUI

struct WalletView: View {
    let damus_state: DamusState
    @State var show_settings: Bool = false
    @ObservedObject var model: WalletModel
    @ObservedObject var settings: UserSettingsStore
    
    init(damus_state: DamusState, model: WalletModel? = nil) {
        self.damus_state = damus_state
        self._model = ObservedObject(wrappedValue: model ?? damus_state.wallet)
        self._settings = ObservedObject(wrappedValue: damus_state.settings)
    }
    
    func MainWalletView(nwc: WalletConnectURL) -> some View {
        ScrollView {
            VStack(spacing: 35) {
                VStack(spacing: 5) {
                    
                    BalanceView(balance: model.balance)
                    
                    TransactionsView(damus_state: damus_state, transactions: model.transactions)
                }
            }
            .navigationTitle(NSLocalizedString("Wallet", comment: "Navigation title for Wallet view"))
            .navigationBarTitleDisplayMode(.inline)
            .padding()
            .padding(.bottom, 50)
        }
    }

    var body: some View {
        switch model.connect_state {
        case .new:
            ConnectWalletView(model: model, nav: damus_state.nav)
        case .none:
            ConnectWalletView(model: model, nav: damus_state.nav)
        case .existing(let nwc):
            MainWalletView(nwc: nwc)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(
                            action: { show_settings = true },
                            label: {
                                Image("settings")
                                    .foregroundColor(.gray)
                            }
                        )
                    }
                }
                .onAppear() {
                    guard let url = damus_state.settings.nostr_wallet_connect,
                          let nwc = WalletConnectURL(str: url) else {
                        return
                    }
                    
                    Task { @MainActor in

                        let flusher: OnFlush? = nil
                        
                        let delay = damus_state.settings.nozaps ? nil : 5.0

                        let _ = nwc_balance(url: nwc, pool: damus_state.pool, post: damus_state.postbox, delay: delay, on_flush: flusher)
                        return
                    }
                }
                .onAppear() {
                    guard let url = damus_state.settings.nostr_wallet_connect,
                          let nwc = WalletConnectURL(str: url) else {
                        return
                    }
                    
                    Task { @MainActor in

                        let flusher: OnFlush? = nil
                        
                        let delay = damus_state.settings.nozaps ? nil : 5.0

                        let _ = nwc_transactions(url: nwc, pool: damus_state.pool, post: damus_state.postbox, delay: delay, on_flush: flusher)
                        return
                    }
                }
                .sheet(isPresented: $show_settings, onDismiss: { self.show_settings = false }) {
                    NWCSettings(damus_state: damus_state, nwc: nwc, model: model, settings: settings)
                        .presentationDragIndicator(.visible)
                        .presentationDetents([.large])
                }
        }
    }
}

let test_wallet_connect_url = WalletConnectURL(pubkey: test_pubkey, relay: .init("wss://relay.damus.io")!, keypair: test_damus_state.keypair.to_full()!, lud16: "jb55@sendsats.com")

struct WalletView_Previews: PreviewProvider {
    static let tds = test_damus_state
    static var previews: some View {
        WalletView(damus_state: tds, model: WalletModel(state: .existing(test_wallet_connect_url), settings: tds.settings))
    }
}
