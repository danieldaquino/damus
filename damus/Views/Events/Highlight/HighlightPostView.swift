//
//  HighlightPostView.swift
//  damus
//
//  Created by eric on 5/26/24.
//

import SwiftUI

struct HighlightPostView: View {
    let damus_state: DamusState
    let source: HighlightSource
    @Binding var selectedText: String
    
    let on_post: ((NostrEvent) -> Void)?
    let on_cancel: (() -> Void)?

    @Environment(\.dismiss) var dismiss
    
    init(damus_state: DamusState, source: HighlightSource, selected_text: Binding<String>, on_post: ((NostrEvent) -> Void)? = nil, on_cancel: (() -> Void)? = nil) {
        self.damus_state = damus_state
        self.source = source
        self._selectedText = selected_text
        self.on_post = on_post
        self.on_cancel = on_cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack {
                HStack(spacing: 5.0) {
                    Button(action: {
                        self.on_cancel?()
                        dismiss()
                    }, label: {
                        Text("Cancel", comment: "Button to cancel out of highlighting a note.")
                            .padding(10)
                    })
                    .buttonStyle(NeutralButtonStyle())

                    Spacer()

                    Button(NSLocalizedString("Post", comment: "Button to post a highlight.")) {
                        let tags = self.source.tags()

                        let kind = NostrKind.highlight.rawValue
                        guard let ev = NostrEvent(content: selectedText, keypair: damus_state.keypair, kind: kind, tags: tags) else {
                            return
                        }
                        damus_state.postbox.send(ev)
                        self.on_post?(ev)
                        dismiss()
                    }
                    .bold()
                    .buttonStyle(GradientButtonStyle(padding: 10))
                }

                Divider()
                    .foregroundColor(DamusColors.neutral3)
                    .padding(.top, 5)
            }
            .frame(height: 30)
            .padding()
            .padding(.top, 15)

            HStack {
                var attributedString: AttributedString {
                    var attributedString = AttributedString(selectedText)

                    if let range = attributedString.range(of: selectedText) {
                        attributedString[range].backgroundColor = DamusColors.highlight
                    }

                    return attributedString
                }

                Text(attributedString)
                    .lineSpacing(5)
                    .padding(10)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 25).fill(DamusColors.highlight).frame(width: 4),
                alignment: .leading
            )
            .padding()
            
            if case .external_url(let url) = source {
                LinkViewRepresentable(meta: .url(url))
                    .frame(height: 50)
                    .padding()
            }

            Spacer()
        }
    }
    
    enum HighlightSource {
        case event(NostrEvent)
        case external_url(URL)
        
        func tags() -> [[String]] {
            switch self {
                case .event(let event):
                    return [ ["e", "\(event.id)"] ]
                case .external_url(let url):
                    return [ ["r", "\(url)"] ]
            }
        }
    }
}
