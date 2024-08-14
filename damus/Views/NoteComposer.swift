//
//  NoteComposer.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-08-14.
//

import SwiftUI

struct NoteComposer: View {
    let damus_state: DamusState
    let placeholder_messages: [String]
    let initial_text_suffix: String?
    var post_changed: ((_ post: NSMutableAttributedString, _ media: [UploadedMedia]) -> Void)?
    
    @Binding var post: NSMutableAttributedString
    @FocusState var focus: Bool
    @Binding var uploadedMedias: [UploadedMedia]
    @Binding var focusWordAttributes: (String?, NSRange?)
    @Binding var newCursorIndex: Int?
    @ObservedObject var tagModel: TagModel
    @Binding var current_placeholder_index: Int
    
    @State var textHeight: CGFloat? = nil
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextViewWrapper(
                attributedText: $post,
                textHeight: $textHeight,
                initialTextSuffix: initial_text_suffix,
                cursorIndex: newCursorIndex,
                getFocusWordForMention: { word, range in
                    focusWordAttributes = (word, range)
                    self.newCursorIndex = nil
                },
                updateCursorPosition: { newCursorIndex in
                    self.newCursorIndex = newCursorIndex
                }
            )
                .environmentObject(tagModel)
                .focused($focus)
                .textInputAutocapitalization(.sentences)
                .onChange(of: post) { p in
                    self.post_changed?(p, uploadedMedias)
                }
                // Set a height based on the text content height, if it is available and valid
                .frame(height: get_valid_text_height())
            
            if post.string.isEmpty {
                Text(self.placeholder_messages[self.current_placeholder_index])
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .foregroundColor(Color(uiColor: .placeholderText))
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            // Schedule a timer to switch messages every 3 seconds
            Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { timer in
                withAnimation {
                    self.current_placeholder_index = (self.current_placeholder_index + 1) % self.placeholder_messages.count
                }
            }
        }
    }
    
    // Returns a valid height for the text box, even when textHeight is not a number
    func get_valid_text_height() -> CGFloat {
        if let textHeight, textHeight.isFinite, textHeight > 0 {
            return textHeight
        }
        else {
            return 10
        }
    }
}

#Preview {
    NoteComposer(
        damus_state: test_damus_state,
        placeholder_messages: ["Test placeholder", "Test placeholder 2"],
        initial_text_suffix: "",
        post_changed: { post, media in
            print("post_changed")
        },
        post: .constant(.init(string: "")),
        focus: .init(),
        uploadedMedias: .constant([]),
        focusWordAttributes: .constant((nil, nil)),
        newCursorIndex: .constant(nil),
        tagModel: .init(),
        current_placeholder_index: .constant(1)
    )
}
