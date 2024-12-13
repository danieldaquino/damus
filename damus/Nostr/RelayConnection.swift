//
//  NostrConnection.swift
//  damus
//
//  Created by William Casarin on 2022-04-02.
//

import Combine
import Foundation

enum NostrConnectionEvent {
    case ws_event(WebSocketEvent)
    case nostr_event(NostrResponse)
}

final actor RelayConnection: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    private var isDisabled = false
    
    private(set) var last_connection_attempt: TimeInterval = 0
    private(set) var last_pong: Date? = nil
    private(set) var backoff: TimeInterval = 1.0
    private lazy var socket = WebSocket(relay_url.url)
    private var subscriptionToken: AnyCancellable?

    private var handleEvent: (NostrConnectionEvent) -> ()
    private var processEvent: (WebSocketEvent) -> ()
    private let relay_url: RelayURL
    private var log: RelayLog?

    init(url: RelayURL,
         handleEvent: @escaping (NostrConnectionEvent) -> (),
         processEvent: @escaping (WebSocketEvent) -> ())
    {
        self.relay_url = url
        self.handleEvent = handleEvent
        self.processEvent = processEvent
    }
    
    func ping() {
        socket.ping { [weak self] err in
            guard let self else {
                return
            }
            
            Task {
                await self.handle_pong(err: err)
            }
        }
    }
    
    private func handle_pong(err: Error?) {
        if err == nil {
            self.last_pong = .now
            Log.info("Got pong from '%s'", for: .networking, self.relay_url.absoluteString)
            self.log?.add("Successful ping")
        } else {
            Log.info("Ping failed, reconnecting to '%s'", for: .networking, self.relay_url.absoluteString)
            self.isConnected = false
            self.isConnecting = false
            self.reconnect_with_backoff()
            self.log?.add("Ping failed")
        }
    }
    
    func add_log(_ content: String) {
        self.log?.add(content)
    }
    
    func set_log(_ new_log: RelayLog?) {
        self.log = new_log
    }
    
    func connect(force: Bool = false) {
        if !force && (isConnected || isConnecting) {
            return
        }
        
        isConnecting = true
        last_connection_attempt = Date().timeIntervalSince1970
        
        subscriptionToken = socket.subject
            .receive(on: DispatchQueue.global(qos: .default))
            .sink { [weak self] completion in
                guard let self else { return }
                Task {
                    switch completion {
                    case .failure(let error):
                        await self.receive(event: .error(error))
                    case .finished:
                        await self.receive(event: .disconnected(.normalClosure, nil))
                    }
                }
            } receiveValue: { [weak self] event in
                guard let self else { return }
                Task {
                    await self.receive(event: event)
                }
            }
            
        socket.connect()
    }

    func disconnect() {
        socket.disconnect()
        subscriptionToken = nil
        
        isConnected = false
        isConnecting = false
    }
    
    func disablePermanently() {
        isDisabled = true
    }
    
    func send_raw(_ req: String) {
        socket.send(.string(req))
    }
    
    func send(_ req: NostrRequestType, callback: ((String) -> Void)? = nil) {
        switch req {
        case .typical(let req):
            guard let req = make_nostr_req(req) else {
                print("failed to encode nostr req: \(req)")
                return
            }
            send_raw(req)
            callback?(req)
            
        case .custom(let req):
            send_raw(req)
            callback?(req)
        }
    }
    
    private func receive(event: WebSocketEvent) {
        processEvent(event)
        switch event {
        case .connected:
            self.backoff = 1.0
            self.isConnected = true
            self.isConnecting = false
        case .message(let message):
            self.receive(message: message)
        case .disconnected(let closeCode, let reason):
            if closeCode != .normalClosure {
                Log.error("⚠️ Warning: RelayConnection (%d) closed with code: %s", for: .networking, String(describing: closeCode), String(describing: reason))
            }
            self.isConnected = false
            self.isConnecting = false
            self.reconnect()
        case .error(let error):
            Log.error("⚠️ Warning: RelayConnection (%s) error: %s", for: .networking, self.relay_url.absoluteString, error.localizedDescription)
            let nserr = error as NSError
            if nserr.domain == NSPOSIXErrorDomain && nserr.code == 57 {
                // ignore socket not connected?
                return
            }
            if nserr.domain == NSURLErrorDomain && nserr.code == -999 {
                // these aren't real error, it just means task was cancelled
                return
            }
            self.isConnected = false
            self.isConnecting = false
            self.reconnect_with_backoff()
        }
        self.handleEvent(.ws_event(event))
        
        if let description = event.description {
            log?.add(description)
        }
    }
    
    func reconnect_with_backoff() {
        self.backoff *= 2.0
        self.reconnect_in(after: self.backoff)
    }
    
    /// This is used to retry a dead connection
    func connect_to_disconnected() {
        if self.isConnecting && (Date.now.timeIntervalSince1970 - self.last_connection_attempt) > 5 {
            self.add_log("stale connection detected. retrying...")
            self.reconnect()
        } else if self.isConnecting || self.isConnected {
            return
        } else {
            self.reconnect()
        }
    }
    
    func reconnect() {
        guard !isConnecting && !isDisabled else {
            self.log?.add("Cancelling reconnect, already connecting")
            return  // we're already trying to connect or we're disabled
        }

        guard !self.isConnected else {
            self.log?.add("Cancelling reconnect, already connected")
            return
        }

        disconnect()
        connect()
        log?.add("Reconnecting...")
    }
    
    func reconnect_in(after: TimeInterval) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + after) {
            Task { await self.reconnect() }
        }
    }
    
    private func receive(message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let messageString):
            if let ev = decode_nostr_event(txt: messageString) {
                Task {
                    self.handleEvent(.nostr_event(ev))
                }
                return
            }
            print("failed to decode event \(messageString)")
        case .data(let messageData):
            if let messageString = String(data: messageData, encoding: .utf8) {
                receive(message: .string(messageString))
            }
        @unknown default:
            print("An unexpected URLSessionWebSocketTask.Message was received.")
        }
    }
}

func make_nostr_req(_ req: NostrRequest) -> String? {
    switch req {
    case .subscribe(let sub):
        return make_nostr_subscription_req(sub.filters, sub_id: sub.sub_id)
    case .unsubscribe(let sub_id):
        return make_nostr_unsubscribe_req(sub_id)
    case .event(let ev):
        return make_nostr_push_event(ev: ev)
    case .auth(let ev):
        return make_nostr_auth_event(ev: ev)
    }
}

func make_nostr_auth_event(ev: NostrEvent) -> String? {
    guard let event = encode_json(ev) else {
        return nil
    }
    let encoded = "[\"AUTH\",\(event)]"
    print(encoded)
    return encoded
}

func make_nostr_push_event(ev: NostrEvent) -> String? {
    guard let event = encode_json(ev) else {
        return nil
    }
    let encoded = "[\"EVENT\",\(event)]"
    print(encoded)
    return encoded
}

func make_nostr_unsubscribe_req(_ sub_id: String) -> String? {
    "[\"CLOSE\",\"\(sub_id)\"]"
}

func make_nostr_subscription_req(_ filters: [NostrFilter], sub_id: String) -> String? {
    let encoder = JSONEncoder()
    var req = "[\"REQ\",\"\(sub_id)\""
    for filter in filters {
        req += ","
        guard let filter_json = try? encoder.encode(filter) else {
            return nil
        }
        let filter_json_str = String(decoding: filter_json, as: UTF8.self)
        req += filter_json_str
    }
    req += "]"
    return req
}
