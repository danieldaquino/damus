//
//  RelayToggle.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import SwiftUI

struct RelayToggle: View {
    let state: DamusState
    let timeline: Timeline
    let relay_id: RelayURL

    func toggle_binding(relay_id: RelayURL) -> Binding<Bool> {
        return Binding(get: {
            !state.relay_filters.is_filtered(timeline: timeline, relay_id: relay_id)
        }, set: { on in
            if !on {
                state.relay_filters.insert(timeline: timeline, relay_id: relay_id)
            } else {
                state.relay_filters.remove(timeline: timeline, relay_id: relay_id)
            }
        })
    }
    
    var body: some View {
        HStack {
            if let relay_connection {
                RelayStatusView(connection: relay_connection)
            }
            RelayType(is_paid: state.relay_model_cache.model(with_relay_id: relay_id)?.metadata.is_paid ?? false)
            Toggle(relay_id.absoluteString, isOn: toggle_binding(relay_id: relay_id))
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        }
    }
    
    private var relay_connection: RelayConnection? {
        state.nostrNetwork.pool.get_relay(relay_id)?.connection
    }
}

struct RelayToggle_Previews: PreviewProvider {
    static var previews: some View {
        RelayToggle(state: test_damus_state, timeline: .search, relay_id: RelayURL("wss://jb55.com")!)
            .padding()
    }
}
