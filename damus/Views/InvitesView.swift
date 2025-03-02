import SwiftUI
import CodeScanner

struct InvitesView: View {
    let damus_state: DamusState
    @State private var inviteLink: String = ""
    @State private var publicInvite: Invite?
    @State private var privateInvite: Invite?
    @State private var isCreatingInvite: Bool = false
    @State private var newInviteLabel: String = ""
    @State private var newInviteMaxUses: String = ""
    @State private var showingQRScanner = false
    @State private var inviteToShow: Invite? = nil
    @State private var qrCodeURL: QRCodeURL? = nil
    
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
                        if let publicInvite = publicInvite {
                            InviteCardView(
                                invite: publicInvite,
                                onShowQR: {
                                    qrCodeURL = QRCodeURL(url: publicInvite.getUrl(), label: publicInvite.label ?? "Public Invite")
                                },
                                onCopy: {
                                    UIPasteboard.general.string = publicInvite.getUrl()
                                }
                            )
                        }
                        
                        if let privateInvite = privateInvite {
                            InviteCardView(
                                invite: privateInvite,
                                onShowQR: {
                                    qrCodeURL = QRCodeURL(url: privateInvite.getUrl(), label: privateInvite.label ?? "Private Invite")
                                },
                                onCopy: {
                                    UIPasteboard.general.string = privateInvite.getUrl()
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            loadInvites()
        }
        .sheet(item: $qrCodeURL) { qrCode in
            InviteQRCodeView(url: qrCode.url, label: qrCode.label)
        }
    }
    
    private func loadInvites() {
        // Only load invites if private key is present
        guard damus_state.keypair.privkey != nil else {
            return
        }
        
        // TODO: Load invites from storage
        // For now, we'll just create sample invites for testing
        do {
            if let keypair = damus_state.keypair.to_full() {
                publicInvite = try Invite.createNew(inviter: keypair.pubkey, label: "Public Invite")
                privateInvite = try Invite.createNew(inviter: keypair.pubkey, label: "Private Invite")
            }
        } catch {
            print("Error creating sample invites: \(error)")
        }
    }
}

struct InviteCardView: View {
    let invite: Invite
    let onShowQR: () -> Void
    let onCopy: () -> Void
    
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

// Create a simple wrapper struct for the URL string
struct QRCodeURL: Identifiable {
    let id = UUID()
    let url: String
    let label: String
} 