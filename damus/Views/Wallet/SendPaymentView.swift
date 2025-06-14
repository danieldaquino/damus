//
//  SendPaymentView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-06-13.
//

import SwiftUI
import CodeScanner

struct SendPaymentView: View {
    enum SendState {
        case enterInvoice
        case confirmPayment(invoice: String)
        case processingPayment
        case completed
        case failed(String)
    }
    
    let damus_state: DamusState
    let model: WalletModel
    let nwc: WalletConnectURL
    
    @State private var sendState: SendState = .enterInvoice
    @State private var errorMessage: String = ""
    @State private var scannerError: ScannerError? = nil
    @State private var isShowingScanner: Bool = true
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    func fillColor() -> Color {
        colorScheme == .light ? DamusColors.white : DamusColors.black
    }
    
    func fontColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }
    
    var body: some View {
        VStack(alignment: .center) {
            switch sendState {
            case .enterInvoice:
                invoiceInputView
            case .confirmPayment(let invoice):
                confirmationView(invoice: invoice)
            case .processingPayment:
                processingView
            case .completed:
                completedView
            case .failed(let error):
                failedView(error: error)
            }
        }
        .padding(40)
        .onTapGesture {
            // No need for hideKeyboard as we don't have text fields in this view anymore
        }
    }
    
    var invoiceInputView: some View {
        VStack(spacing: 20) {
            Text("Scan Lightning Invoice", comment: "Title for the invoice scanning screen")
                .font(.title2)
                .bold()
            
            ZStack {
                if isShowingScanner {
                    CodeScannerView(
                        codeTypes: [.qr],
                        simulatedData: "lnbc10n1pj4d0d2pp5f70dr9c344rt98ng3wl5kjqza075qh5xgc2d3nr67ku568kr73sdqqcqzzsxqyz5vqsp5sz3k3j2h8xlnrqktzvlazd8rxnn2a6x97els9u24a3a52nj9jf4s9qyyssq67f3p8sxnpkdnz3q4g6qx8mmh63zwfd2ter7jp8qwvzrrdu2f9eq37knapshygh5vwl6dckhh99x9gkqamyy9jvgz80e50p3zknwa2gqkf5eus",
                        completion: handleScan
                    )
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.accentColor, lineWidth: 2)
                    )
                    .padding(.horizontal)
                } else {
                    VStack {
                        Text("QR Scanner Paused", comment: "Message shown when scanner is paused")
                            .font(.headline)
                        
                        Button(action: {
                            isShowingScanner = true
                        }) {
                            Text("Resume Scanning", comment: "Button to resume QR scanning")
                                .font(.headline)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .background(DamusColors.adaptableGrey)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal)
                }
            }
            
            VStack(spacing: 15) {
                Button(action: {
                    if let pastedInvoice = getPasteboardContent() {
                        processInvoice(pastedInvoice)
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste from Clipboard", comment: "Button to paste invoice from clipboard")
                    }
                    .frame(minWidth: 250, maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(DamusColors.adaptableGrey)
                    .foregroundColor(fontColor())
                    .cornerRadius(10)
                }
                .accessibilityLabel(NSLocalizedString("Paste invoice from clipboard", comment: "Accessibility label for the invoice paste button"))
            }
            .padding(.horizontal)
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(.top, 10)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .sheet(item: $scannerError) { error in
            errorSheet(error: error)
        }
    }
    
    func confirmationView(invoice: String) -> some View {
        VStack(spacing: 20) {
            Text("Confirm Payment", comment: "Title for payment confirmation screen")
                .font(.title2)
                .bold()
            
            VStack(alignment: .leading, spacing: 15) {
                Text("Invoice", comment: "Label for invoice in confirmation screen")
                    .font(.headline)
                
                Text(invoice.prefix(30) + "..." + invoice.suffix(10))
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(DamusColors.adaptableGrey)
                    .cornerRadius(10)
                    .frame(maxWidth: .infinity)
            }
            
            HStack(spacing: 15) {
                Button(action: {
                    sendState = .enterInvoice
                }) {
                    Text("Back", comment: "Button to go back to invoice input")
                        .font(.headline)
                        .frame(minWidth: 140)
                        .padding()
                }
                .buttonStyle(NeutralButtonStyle())
                
                Button(action: {
                    sendState = .processingPayment
                    
                    // Process payment
                    let payRequestEv = WalletConnect.pay(url: nwc, pool: damus_state.nostrNetwork.pool, post: damus_state.nostrNetwork.postbox, invoice: invoice, zap_request: nil, delay: nil)
                    
                    let waitTask = Task {
                        do {
                            let nwcUrl = nwc
                            var filter = NostrFilter(kinds: [.nwc_response])
                            filter.authors = [nwcUrl.pubkey]
                            filter.pubkeys = [nwcUrl.keypair.pubkey]
                            filter.limit = 0
                            for await item in damus_state.nostrNetwork.reader.subscribe(filters: [filter]) {
                                switch item {
                                case .eose:
                                    continue
                                case .event(borrow: let borrow):
                                    try borrow { note in
                                        guard note.known_kind == .nwc_response else { return }
                                        guard note.pubkey == nwcUrl.pubkey else { return }
                                        guard note.tags.note.referenced_pubkeys.contains(nwcUrl.keypair.pubkey) else { return }
                                        guard let resp = try? WalletConnect.FullWalletResponse(from: note.toOwned(), nwc: nwc) else { return }
                                        guard resp.req_id == payRequestEv?.id else { return }
                                        guard resp.response.result_type == .pay_invoice else { return }
                                        if let error = resp.response.error {
                                            sendState = .failed(error.message ?? "")
                                            return
                                        }
                                        else {
                                            switch resp.response.result {
                                            case .pay_invoice(let payInvoiceResponse):
                                                sendState = .completed
                                            default:
                                                return
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        catch {
                            if Task.isCancelled {
                                return  // the timeout task will handle throwing the timeout error
                            }
                            switch sendState {
                            case .processingPayment:
                                sendState = .failed(error.localizedDescription)
                            default:
                                break
                            }
                        }
                    }
                    
                    let timeoutTask = Task {
                        try await Task.sleep(for: .seconds(Int(10)))
                        switch sendState {
                        case .completed:
                            break
                        default:
                            sendState = .failed("Timeout")
                        }
                        waitTask.cancel()
                    }
                }) {
                    Text("Confirm", comment: "Button to confirm payment")
                        .font(.headline)
                        .frame(minWidth: 140)
                        .padding()
                }
                .buttonStyle(GradientButtonStyle(padding: 0))
            }
            
            Spacer()
        }
    }
    
    var processingView: some View {
        VStack(spacing: 30) {
            Text("Processing Payment", comment: "Title for payment processing screen")
                .font(.title2)
                .bold()
            
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            
            Text("Please wait while your payment is being processed…", comment: "Message while payment is being processed")
                .multilineTextAlignment(.center)
                .padding()
            
            Spacer()
        }
    }
    
    var completedView: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.green)
            
            Text("Payment Sent!", comment: "Title for successful payment screen")
                .font(.title2)
                .bold()
            
            Text("Your payment has been successfully sent.", comment: "Message for successful payment")
                .multilineTextAlignment(.center)
                .padding()
            
            Button(action: {
                dismiss()
            }) {
                Text("Done", comment: "Button to dismiss successful payment screen")
                    .font(.headline)
                    .frame(minWidth: 200)
            }
            .buttonStyle(GradientButtonStyle())
            
            Spacer()
        }
    }
    
    func failedView(error: String) -> some View {
        VStack(spacing: 30) {
            Image(systemName: "exclamationmark.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.red)
            
            Text("Payment Failed", comment: "Title for failed payment screen")
                .font(.title2)
                .bold()
            
            Text(error)
                .multilineTextAlignment(.center)
                .padding()
            
            Button(action: {
                sendState = .enterInvoice
            }) {
                Text("Try Again", comment: "Button to retry payment")
                    .font(.headline)
                    .frame(minWidth: 200)
                    .padding()
            }
            .buttonStyle(GradientButtonStyle(padding: 0))
            
            Button(action: {
                dismiss()
            }) {
                Text("Cancel", comment: "Button to cancel payment")
                    .font(.headline)
                    .frame(minWidth: 200)
                    .padding()
            }
            .buttonStyle(NeutralButtonStyle())
            
            Spacer()
        }
    }
    
    // New functions for QR code scanning
    func handleScan(result: Result<ScanResult, ScanError>) {
        isShowingScanner = false
        
        switch result {
        case .success(let result):
            processInvoice(result.string)
        case .failure(let error):
            scannerError = .scanFailed(error.localizedDescription)
            errorMessage = NSLocalizedString("Failed to scan QR code", comment: "Error message for failed QR scan")
        }
        
        // Resume scanning after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isShowingScanner = true
        }
    }
    
    func processInvoice(_ text: String) {
        var processedInvoice = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle lightning: prefix
        if processedInvoice.lowercased().hasPrefix("lightning:") {
            processedInvoice = String(processedInvoice.dropFirst(10))
        }
        
        if !processedInvoice.isEmpty && processedInvoice.lowercased().hasPrefix("lnbc") {
            errorMessage = ""
            sendState = .confirmPayment(invoice: processedInvoice)
        } else {
            errorMessage = NSLocalizedString("Please scan a valid Lightning invoice", comment: "Error message when invoice is invalid")
        }
    }
    
    func errorSheet(error: ScannerError) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(.orange)
            
            Text("Scanner Error", comment: "Title for scanner error sheet")
                .font(.title2)
                .bold()
            
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .padding()
            
            Button(action: {
                scannerError = nil
                isShowingScanner = true
            }) {
                Text("OK", comment: "Button to dismiss error")
                    .font(.headline)
                    .frame(minWidth: 200)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
        .presentationDetents([.medium])
    }
    
    // Error handling for scanner
    enum ScannerError: Error, Identifiable {
        case invalidData
        case scanFailed(String)
        case permissionDenied
        
        var id: String {
            switch self {
            case .invalidData: return "invalid_data"
            case .scanFailed: return "scan_failed"
            case .permissionDenied: return "permission_denied"
            }
        }
        
        var localizedDescription: String {
            switch self {
            case .invalidData:
                return NSLocalizedString("The scanned QR code does not contain a valid Lightning invoice.", comment: "Error message for invalid QR code data")
            case .scanFailed(let message):
                return message
            case .permissionDenied:
                return NSLocalizedString("Camera access is required to scan QR codes. Please enable it in Settings.", comment: "Error message for camera permission denied")
            }
        }
    }
    
    // Helper function to get pasteboard content
    func getPasteboardContent() -> String? {
        return UIPasteboard.general.string
    }
}
