//
//  SecureChatView.swift
//  damus
//
//  Created for Double Ratchet secure chats
//

import SwiftUI
import Combine

struct SecureChatView: View, KeyboardReadable {
    let damus_state: DamusState
    @FocusState private var isTextFieldFocused: Bool
    @ObservedObject var sessionRecord: SessionRecord
    @State private var draft: String = ""
    
    var Messages: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading) {
                    MessagesContent(scroller: scroller)
                    EndBlock(height: 1)
                }
                .padding(.horizontal)
            }
            .dismissKeyboardOnTap()
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scroll_to_end(scroller)
                }
            }
            .onChange(of: sessionRecord.messages.count) { newCount in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scroll_to_end(scroller, animated: true)
                }
            }
            
            Footer
                .onReceive(keyboardPublisher) { visible in
                    guard visible else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scroll_to_end(scroller, animated: true)
                    }
                }
        }
        .padding(.bottom, isTextFieldFocused ? 0 : tabHeight)
    }
    
    @ViewBuilder
    func MessagesContent(scroller: ScrollViewProxy) -> some View {
        ForEach(Array(sessionRecord.messages.values.sorted(by: { $0.rumor.created_at < $1.rumor.created_at })), id: \.rumor.id) { messageRecord in
            SecureChatMessageView(
                messageRecord: messageRecord,
                damus_state: damus_state,
                sessionRecord: sessionRecord
            )
            /*
            .contextMenu {
                MenuItems(
                    damus_state: damus_state,
                    event: event,
                    target_pubkey: pubkey,
                    profileModel: ProfileModel(pubkey: pubkey, damus: damus_state)
                )
            }
            */
        }
    }
    
    func scroll_to_end(_ scroller: ScrollViewProxy, animated: Bool = false) {
        if animated {
            withAnimation {
                scroller.scrollTo("endblock")
            }
        } else {
            scroller.scrollTo("endblock")
        }
    }

    var Header: some View {
        return NavigationLink(value: Route.ProfileByKey(pubkey: sessionRecord.pubkey)) {
            HStack(spacing: 8) {
                ProfilePicView(pubkey: sessionRecord.pubkey, size: 24, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)

                VStack(alignment: .leading) {
                    ProfileName(pubkey: sessionRecord.pubkey, damus: damus_state)
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Secure Chat")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }

    var InputField: some View {
        TextEditor(text: $draft)
            .textEditorBackground {
                InputBackground()
            }
            .focused($isTextFieldFocused)
            .cornerRadius(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: .init(lineWidth: 2))
                    .foregroundColor(.secondary.opacity(0.2))
            )
            .padding(16)
            .foregroundColor(Color.primary)
            .frame(minHeight: 70, maxHeight: 150, alignment: .bottom)
            .fixedSize(horizontal: false, vertical: true)
    }

    @Environment(\.colorScheme) var colorScheme

    func InputBackground() -> Color {
        if colorScheme == .light {
            return Color.init(.sRGB, red: 0.9, green: 0.9, blue: 0.9, opacity: 1.0)
        } else {
            return Color.init(.sRGB, red: 0.1, green: 0.1, blue: 0.1, opacity: 1.0)
        }
    }

    var Footer: some View {
        HStack(spacing: 0) {
            InputField

            if !draft.isEmpty {
                Button(
                    role: .none,
                    action: {
                        send_message()
                    }
                ) {
                    Label("", image: "send")
                        .font(.title)
                }
            }
        }
    }

    func send_message() {
        guard !draft.isEmpty else { return }
        
        do {
            let (event, rumor) = try sessionRecord.session.sendText(draft)
            damus_state.postbox.send(event)
            sessionRecord.addEvent(rumor, isFromMe: true)
            
            // Clear draft
            draft = ""
            end_editing()
        } catch {
            print("Error sending secure message: \(error)")
        }
    }

    var body: some View {
        ZStack {
            Messages

            Text("Send a message to start the secure conversation...", comment: "Text prompt for user to send a message to the other user.")
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity((sessionRecord.messages.isEmpty ? 1.0 : 0.0))
                .foregroundColor(.gray)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Header
            }
        }
    }
}

struct SecureChatMessageView: View {
    @ObservedObject var messageRecord: MessageRecord
    let damus_state: DamusState
    let sessionRecord: SessionRecord
    
    var body: some View {
        HStack {
            if messageRecord.isFromMe {
                Spacer()
            }
            
            VStack(alignment: messageRecord.isFromMe ? .trailing : .leading) {
                Text(messageRecord.rumor.content)
                    .padding(10)
                    .background(messageRecord.isFromMe ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                    .cornerRadius(10)
                
                // Display reactions
                if !messageRecord.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(messageRecord.reactions), id: \.key) { pubkey, reaction in
                            HStack(spacing: 2) {
                                Text(reaction)
                                ProfilePicView(pubkey: pubkey, size: 16, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                
                Text(Date(timeIntervalSince1970: TimeInterval(messageRecord.rumor.created_at)).formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !messageRecord.isFromMe {
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(action: {
                addReaction("❤️")
            }) {
                Label("❤️", systemImage: "heart")
            }
            
            Button(action: {
                addReaction("👍")
            }) {
                Label("👍", systemImage: "hand.thumbsup")
            }
        }
    }
    
    func addReaction(_ reaction: String) {
        do {
            let (event, _) = try sessionRecord.session.sendEvent(rumor: DoubleRatchet.Rumor(
                id: UUID().uuidString,
                content: reaction,
                kind: 6,
                created_at: UInt32(Date().timeIntervalSince1970),
                tags: [["e", messageRecord.rumor.id]],
                pubkey: damus_state.pubkey
            ))
            damus_state.postbox.send(event)
            messageRecord.reactions[damus_state.pubkey] = reaction
        } catch {
            print("Error sending reaction: \(error)")
        }
    }
} 