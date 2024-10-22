//
//  DamusFullScreenCover.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-10-25.
//

import SwiftUI

fileprivate struct DamusFullScreenCover<FullScreenContent: View>: ViewModifier {
    let damus_state: DamusState
    @Binding var is_presented: Bool
    let full_screen_content: () -> FullScreenContent
    
    func body(content: Content) -> some View {
        content
            .onChange(of: is_presented) { newValue in
                damus_state.video.set_full_screen_mode(newValue)
            }
            .fullScreenCover(isPresented: $is_presented, content: {
                full_screen_content()
                    .environment(\.video_focus_context, .full_screen)
                    // Another observer for full screen presentation is needed here because in some cases the underlying view (`body::content`) may have been deinitialized and no longer listen to changes
                    // One such example is when the underlying navigation stack navigates away from a source view at the same time it opens the full screen view
                    // Therefore, when the full screen view is dismissed, this content will disappear, and we should notify the video coordinator.
                    .onDisappear {
                        damus_state.video.set_full_screen_mode(is_presented)
                    }
            })
    }
}

extension View {
    func damus_full_screen_cover<Content: View>(_ is_presented: Binding<Bool>, damus_state: DamusState, @ViewBuilder content: @escaping () -> Content) -> some View {
        return self.modifier(DamusFullScreenCover(damus_state: damus_state, is_presented: is_presented, full_screen_content: content))
    }
}
