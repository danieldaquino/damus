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
                    .environment(\.view_layer_context, .full_screen_layer)
                    // Another observer for full screen presentation is needed here because in some cases the underlying view (`body::content`) may have been deinitialized and no longer listen to changes
                    // One such example is when the underlying navigation stack navigates away from a source view at the same time it opens the full screen view
                    // Therefore, when the full screen view is dismissed, this content will disappear, and we should notify the video coordinator.
                    .onDisappear {
                        damus_state.video.set_full_screen_mode(is_presented)
                    }
            })
    }
}

fileprivate struct DamusFullScreenCover2<FullScreenContent: View, T: Identifiable & Equatable>: ViewModifier {
    let damus_state: DamusState
    @Binding var item: T?
    let full_screen_content: (T) -> FullScreenContent
    
    func body(content: Content) -> some View {
        content
            .onChange(of: item) { newValue in
                damus_state.video.set_full_screen_mode(newValue != nil)
            }
            .fullScreenCover(item: $item, content: { item in
                full_screen_content(item)
                    .environment(\.view_layer_context, .full_screen_layer)
                    // Another observer for full screen presentation is needed here because in some cases the underlying view (`body::content`) may have been deinitialized and no longer listen to changes
                    // One such example is when the underlying navigation stack navigates away from a source view at the same time it opens the full screen view
                    // Therefore, when the full screen view is dismissed, this content will disappear, and we should notify the video coordinator.
                    .onDisappear {
                        damus_state.video.set_full_screen_mode(false)
                    }
            })
    }
}

extension View {
    func damus_full_screen_cover<Content: View>(_ is_presented: Binding<Bool>, damus_state: DamusState, @ViewBuilder content: @escaping () -> Content) -> some View {
        return self.modifier(DamusFullScreenCover(damus_state: damus_state, is_presented: is_presented, full_screen_content: content))
    }
    
    func damus_full_screen_cover<Content: View, T: Identifiable & Equatable>(_ item: Binding<T?>, damus_state: DamusState, @ViewBuilder content: @escaping (T) -> Content) -> some View {
        return self.modifier(DamusFullScreenCover2(damus_state: damus_state, item: item, full_screen_content: content))
    }
}
