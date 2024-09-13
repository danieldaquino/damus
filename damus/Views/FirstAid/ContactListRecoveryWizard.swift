//
//  ContactListRecoveryWizard.swift
//  damus
//
//  Created by Daniel D‘Aquino on 2024-09-13.
//

import SwiftUI

struct ContactListRecoveryWizard: View {
    var body: some View {
        TabView {
            Text("Hello, World 1!")
            Text("Hello, World 2!")
            Text("Hello, World 3!")
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        
    }
    
//    func find_contact_lists() {
//        let relay_pool = RelayPool(ndb: damus_state.ndb, keypair: damus_state.keypair)
//        let bootstrap_relays = get_default_bootstrap_relays().map({ RelayDescriptor.init(url: $0, info: RelayInfo.r) })
//        for bootstrap_relay in
//        relay_pool.add_relay(RelayDescriptor(url: <#T##RelayURL#>, info: <#T##RelayInfo#>))
//    }
}

#Preview {
    ContactListRecoveryWizard()
}
