import SwiftUI
import CodeScanner

// Create a simple wrapper struct for the URL string
struct QRCodeURL: Identifiable {
    var id = UUID()
    let url: String
    let label: String
}

struct InvitesView: View {
    let damus_state: DamusState
    
    @State private var inviteLink: String = ""
    @State private var isCreatingInvite: Bool = false
    @State private var newInviteLabel: String = ""
    @State private var newInviteMaxUses: String = ""
    @State private var showingQRScanner = false
    @State private var qrCodeURL: QRCodeURL? = nil
    @State private var isProcessingInvite = false
    @State private var inviteError: String? = nil
    
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
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: inviteLink) { newValue in
                                processInviteLink(newValue)
                            }
                        
                        Button(action: {
                            showingQRScanner = true
                        }) {
                            Image(systemName: "qrcode.viewfinder")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .sheet(isPresented: $showingQRScanner) {
                            InviteQRScannerView(inviteLink: $inviteLink, isPresented: $showingQRScanner)
                        }
                    }
                    
                    if isProcessingInvite {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 5)
                            Text("Processing invite...")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let error = inviteError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding(.horizontal)
                
                // Share Invite Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Share your invite link")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if damus_state.keypair.privkey == nil {
                        Text("Private key not present")
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                    } else {
                        // Display existing invites
                        let invites = damus_state.session_manager.getInvites()
                        
                        ForEach(Array(invites.enumerated()), id: \.offset) { index, invite in
                            InviteCardView(
                                invite: invite,
                                onShowQR: {
                                    qrCodeURL = QRCodeURL(url: invite.getUrl(), label: invite.label ?? "Invite")
                                },
                                onCopy: {
                                    UIPasteboard.general.string = invite.getUrl()
                                }
                            )
                        }
                        
                        Button(action: {
                            isCreatingInvite = true
                        }) {
                            Label(invites.isEmpty ? "Create Invite" : "Create Another Invite", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.bordered)
                        .sheet(isPresented: $isCreatingInvite) {
                            CreateInviteView(
                                isPresented: $isCreatingInvite,
                                label: $newInviteLabel,
                                maxUses: $newInviteMaxUses,
                                onCreate: { isPrivate in
                                    // Handle invite creation
                                    createInvite(isPrivate: isPrivate)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .sheet(item: $qrCodeURL) { qrCode in
            InviteQRCodeView(url: qrCode.url, label: qrCode.label)
        }
    }
    
    private func processInviteLink(_ link: String) {
        // Reset error state
        inviteError = nil
        
        // Skip empty links
        guard !link.isEmpty else { return }
        
        // Check if the link looks like an invite link
        guard link.contains("damus.io/invite") || link.contains("relay.damus.io") || link.contains("iris.to") else {
            return
        }
        
        // Try to parse the invite
        guard let url = URL(string: link) else {
            inviteError = "Invalid URL format"
            return
        }
        
        isProcessingInvite = true
        
        Task {
            do {
                // Try to import the invite
                let invite = try damus_state.session_manager.importInviteFromUrl(url)
                
                // Accept the invite
                let session = try await damus_state.session_manager.acceptInvite(invite)
                
                // Update UI on main thread
                await MainActor.run {
                    isProcessingInvite = false
                    inviteLink = ""
                    // Optionally show success message or navigate to a chat view with the new session
                }
                
                print("Successfully accepted invite and created session: \(session.name)")
            } catch {
                await MainActor.run {
                    isProcessingInvite = false
                    inviteError = "Failed to process invite: \(error.localizedDescription)"
                    print("Error processing invite: \(error)")
                }
            }
        }
    }
    
    private func createInvite(isPrivate: Bool) {
        do {
            let maxUsesInt = !newInviteMaxUses.isEmpty ? Int(newInviteMaxUses) : nil
            try damus_state.session_manager.createInvite(
                label: newInviteLabel.isEmpty ? nil : newInviteLabel,
                maxUses: maxUsesInt
            )
            
            newInviteLabel = ""
            newInviteMaxUses = ""
            isCreatingInvite = false
        } catch {
            print("Error creating invite: \(error)")
        }
    }
}

struct InviteCardView: View {
    let invite: Invite
    let onShowQR: () -> Void
    let onCopy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(invite.label ?? "Invite")
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
    let label: String
    
    var body: some View {
        VStack {
            Text(label)
                .font(.headline)
                .padding(.bottom, 8)
            
            Image(uiImage: generateQRCode(from: url))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .background(Color.white)
                .cornerRadius(10)
            
            Button("Copy Link") {
                UIPasteboard.general.string = url
            }
            .padding()
        }
        .padding()
    }
    
    private func generateQRCode(from string: String) -> UIImage {
        // Ensure we have valid data
        guard let data = string.data(using: .utf8) else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }
        
        // Create the QR code filter
        let qrFilter = CIFilter(name: "CIQRCodeGenerator")
        qrFilter?.setValue(data, forKey: "inputMessage")
        
        // Scale the image
        guard let qrImage = qrFilter?.outputImage else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }
        
        // Scale the image
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledQrImage = qrImage.transformed(by: transform)
        
        // Convert to UIImage
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledQrImage, from: scaledQrImage.extent) else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }
        
        return UIImage(cgImage: cgImage)
    }
}

struct InviteQRScannerView: View {
    @Binding var inviteLink: String
    @Binding var isPresented: Bool
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .center) {
                DamusGradient()
                
                VStack {
                    Text("Scan Invite QR Code")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.top, 50)
                    
                    Spacer()
                    
                    CodeScannerView(codeTypes: [.qr], scanMode: .continuous, scanInterval: 1, showViewfinder: true, simulatedData: "https://damus.io/invite/example", shouldVibrateOnSuccess: true) { result in
                        handleScan(result)
                    }
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 300)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(DamusColors.white, lineWidth: 5.0).scaledToFit())
                    .shadow(radius: 10)
                    
                    Spacer()
                    
                    Text("Point your camera to an invite QR code")
                        .foregroundColor(.white)
                        .padding()
                    
                    Spacer()
                    
                    Button(action: {
                        dismiss()
                    }) {
                        HStack {
                            Text("Cancel")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 12, alignment: .center)
                    }
                    .buttonStyle(GradientButtonStyle())
                    .padding(20)
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    func handleScan(_ result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            let scannedCode = result.string
            
            // Check if the scanned code is a valid invite link
            if scannedCode.contains("damus.io/invite") || scannedCode.contains("relay.damus.io") {
                inviteLink = scannedCode
                isPresented = false
            }
            
        case .failure(let error):
            print("Scanning failed: \(error.localizedDescription)")
        }
    }
} 