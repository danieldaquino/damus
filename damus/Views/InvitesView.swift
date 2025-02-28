import SwiftUI

struct InvitesView: View {
    let damus_state: DamusState
    @State private var inviteLink: String = ""
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Add top padding
                Spacer()
                    .frame(height: 20)
                
                // Paste Invite Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Have someone's invite link?")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    HStack {
                        TextField("Paste invite link", text: $inviteLink)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button(action: {
                            // TODO: Implement QR scan
                        }) {
                            Image(systemName: "qrcode.viewfinder")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
                
                // Share Invite Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Share your invite link")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Button(action: {
                        // TODO: Implement invite creation logic
                    }) {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("Create New Invite")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    // Public Invite Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Public Invite")
                            .font(.headline)
                        
                        HStack {
                            Spacer()
                            Button(action: {
                                // TODO: Show QR code
                            }) {
                                Image(systemName: "qrcode")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                // TODO: Copy URL logic
                            }) {
                                Text("Copy")
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                // TODO: Delete invite
                            }) {
                                Text("Delete")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    
                    // Private Invite Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Private Invite")
                            .font(.headline)
                        
                        HStack {
                            Spacer()
                            Button(action: {
                                // TODO: Show QR code
                            }) {
                                Image(systemName: "qrcode")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                // TODO: Copy URL logic
                            }) {
                                Text("Copy")
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                // TODO: Delete invite
                            }) {
                                Text("Delete")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .padding(.horizontal)
            }
        }
    }
} 