//
//  ReactionsView.swift
//  damus
//
//  Created by William Casarin on 2023-01-11.
//

import SwiftUI

struct ReactionsView: View {
    let damus_state: DamusState
    @StateObject var model: EventsModel

    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(model.events.events.filter { $0.last_refid() == model.target }, id: \.id) { ev in
                    ReactionView(damus_state: damus_state, reaction: ev)
                }
            }
            .padding()
        }
        .padding(.bottom, tabHeight)
        .navigationBarTitle(NSLocalizedString("Reactions", comment: "Navigation bar title for Reactions view."))
        .onAppear {
            Task { await model.subscribe() }
        }
        .onDisappear {
            Task { await model.unsubscribe() }
        }
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }
}

struct ReactionsView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        ReactionsView(damus_state: state, model: .likes(state: state, target: test_note.id))
    }
}
