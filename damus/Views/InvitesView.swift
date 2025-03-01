import SwiftUI

struct InvitesView: View {
    let damus_state: DamusState
    @State private var inviteLink: String = ""
    @State private var invites: [Invite] = []
    @State private var isCreatingInvite: Bool = false
    @State private var newInviteLabel: String = ""
    @State private var newInviteMaxUses: String = ""
    @State private var showingQRCode: Bool = false
    @State private var selectedInviteURL: String = ""
    
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
                        createNewInvite(isPrivate: false)
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
                    
                    // Display existing invites
                    ForEach(invites.indices, id: \.self) { index in
                        let invite = invites[index]
                        InviteCardView(
                            invite: invite,
                            onShowQR: {
                                selectedInviteURL = invite.getUrl()
                                showingQRCode = true
                            },
                            onCopy: {
                                UIPasteboard.general.string = invite.getUrl()
                            },
                            onDelete: {
                                invites.remove(at: index)
                                // TODO: Implement proper deletion from storage
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            loadInvites()
        }
        .sheet(isPresented: $isCreatingInvite) {
            CreateInviteView(
                isPresented: $isCreatingInvite,
                label: $newInviteLabel,
                maxUses: $newInviteMaxUses,
                onCreate: { isPrivate in
                    createNewInvite(isPrivate: isPrivate)
                }
            )
        }
        .sheet(isPresented: $showingQRCode) {
            InviteQRCodeView(url: selectedInviteURL)
        }
    }
    
    private func loadInvites() {
        // TODO: Load invites from storage
        // For now, we'll just create a sample invite for testing
        do {
            if let keypair = damus_state.keypair.to_full() {
                let publicInvite = try Invite.createNew(inviter: keypair.pubkey, label: "Public Invite")
                invites.append(publicInvite)
                
                let privateInvite = try Invite.createNew(inviter: keypair.pubkey, label: "Private Invite", maxUses: 1)
                invites.append(privateInvite)
            }
        } catch {
            print("Error creating sample invites: \(error)")
        }
    }
    
    private func createNewInvite(isPrivate: Bool) {
        do {
            if let keypair = damus_state.keypair.to_full() {
                let maxUses = isPrivate ? Int(newInviteMaxUses) : nil
                let invite = try Invite.createNew(
                    inviter: keypair.pubkey,
                    label: newInviteLabel.isEmpty ? (isPrivate ? "Private Invite" : "Public Invite") : newInviteLabel,
                    maxUses: maxUses
                )
                
                // Create and publish event for public invites
                if !isPrivate {
                    let event = invite.getEvent(keypair: keypair)
                    damus_state.pool.send(.event(event))
                }
                
                invites.append(invite)
                
                // Reset form fields
                newInviteLabel = ""
                newInviteMaxUses = ""
                isCreatingInvite = false
            }
        } catch {
            print("Error creating invite: \(error)")
        }
    }
}

struct InviteCardView: View {
    let invite: Invite
    let onShowQR: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(invite.label ?? (invite.maxUses != nil ? "Private Invite" : "Public Invite"))
                .font(.headline)
            
            if let maxUses = invite.maxUses {
                Text("Uses: \(invite.usedBy.count)/\(maxUses)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Spacer()
                Button(action: onShowQR) {
                    Image(systemName: "qrcode")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                
                Button(action: onCopy) {
                    Text("Copy")
                }
                .buttonStyle(.bordered)
                
                Button(action: onDelete) {
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
}

struct CreateInviteView: View {
    @Binding var isPresented: Bool
    @Binding var label: String
    @Binding var maxUses: String
    let onCreate: (Bool) -> Void
    @State private var isPrivate: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Invite Details")) {
                    TextField("Label (optional)", text: $label)
                    
                    Toggle("Private Invite", isOn: $isPrivate)
                    
                    if isPrivate {
                        TextField("Maximum Uses", text: $maxUses)
                            .keyboardType(.numberPad)
                    }
                }
                
                Section {
                    Button("Create Invite") {
                        onCreate(isPrivate)
                    }
                }
            }
            .navigationTitle("Create Invite")
            .navigationBarItems(trailing: Button("Cancel") {
                isPresented = false
            })
        }
    }
}

struct InviteQRCodeView: View {
    let url: String
    
    var body: some View {
        VStack {
            if let qrCode = generateQRCode(from: url) {
                Image(uiImage: qrCode)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
            }
            
            Text(url)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding()
            
            Button("Copy Link") {
                UIPasteboard.general.string = url
            }
            .padding()
        }
        .padding()
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: .utf8)
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("H", forKey: "inputCorrectionLevel")
            if let outputImage = filter.outputImage {
                let transform = CGAffineTransform(scaleX: 10, y: 10)
                let scaledImage = outputImage.transformed(by: transform)
                let context = CIContext()
                if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                    return UIImage(cgImage: cgImage)
                }
            }
        }
        return nil
    }
} 