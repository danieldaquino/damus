//
//  PostBox.swift
//  damus
//
//  Created by William Casarin on 2023-03-20.
//

import Foundation
import Combine


class Relayer {
    let relay: RelayURL
    var attempts: Int
    var retry_after: Double
    var last_attempt: Int64?

    init(relay: RelayURL, attempts: Int, retry_after: Double) {
        self.relay = relay
        self.attempts = attempts
        self.retry_after = retry_after
        self.last_attempt = nil
    }
}

enum OnFlush {
    case once((EventPostTracker) -> Void)
    case all((EventPostTracker) -> Void)
}

class EventPostTracker {
    let event: NostrEvent
    let skip_ephemeral: Bool
    var remaining: [Relayer]
    let flush_after: Date?
    var flushed_once: Bool
    let on_flush: OnFlush?
    var send_progress: Future<RelayPool.SendProgress, Never>

    init(event: NostrEvent, remaining: [RelayURL], skip_ephemeral: Bool, flush_after: Date?, on_flush: OnFlush?, send_progress: Future<RelayPool.SendProgress, Never>) {
        self.event = event
        self.skip_ephemeral = skip_ephemeral
        self.flush_after = flush_after
        self.on_flush = on_flush
        self.flushed_once = false
        self.remaining = remaining.map {
            Relayer(relay: $0, attempts: 0, retry_after: 10.0)
        }
        self.send_progress = send_progress
    }
}

enum CancelSendErr {
    case nothing_to_cancel
    case not_delayed
    case too_late
}

class PostBox {
    private let pool: RelayPool
    var events: [NoteId: EventPostTracker]
    var promises: [NoteId: (Result<RelayPool.SendProgress, Never>) -> Void] = [:]

    init(pool: RelayPool) {
        self.pool = pool
        self.events = [:]
        pool.register_handler(sub_id: "postbox", handler: handle_event)
    }
    
    // only works reliably on delay-sent events
    func cancel_send(evid: NoteId) -> CancelSendErr? {
        guard let ev = events[evid] else {
            return .nothing_to_cancel
        }
        
        guard let after = ev.flush_after else {
            return .not_delayed
        }
        
        guard Date.now < after else {
            return .too_late
        }
        
        events.removeValue(forKey: evid)
        return nil
    }
    
    func try_flushing_events() {
        let now = Int64(Date().timeIntervalSince1970)
        for kv in events {
            let event = kv.value
            
            // some are delayed
            if let after = event.flush_after, Date.now.timeIntervalSince1970 < after.timeIntervalSince1970 {
                continue
            }
            
            for relayer in event.remaining {
                if relayer.last_attempt == nil ||
                   (now >= (relayer.last_attempt! + Int64(relayer.retry_after))) {
                    print("attempt #\(relayer.attempts) to flush event '\(event.event.content)' to \(relayer.relay) after \(relayer.retry_after) seconds")
                    let send_progress = flush_event(event, to_relay: relayer)
                    if let promise = self.promises[event.event.id] {
                        promise(Result.success(send_progress))
                        self.promises[event.event.id] = nil
                    }
                }
            }
        }
    }

    func handle_event(relay_id: RelayURL, _ ev: NostrConnectionEvent) {
        guard case .nostr_event(let resp) = ev else {
            return
        }
        
        guard case .ok(let cr) = resp else {
            return
        }
        
        remove_relayer(relay_id: relay_id, event_id: cr.event_id)
    }

    @discardableResult
    func remove_relayer(relay_id: RelayURL, event_id: NoteId) -> Bool {
        guard let ev = self.events[event_id] else {
            return false
        }
        
        if let on_flush = ev.on_flush {
            switch on_flush {
            case .once(let cb):
                if !ev.flushed_once {
                    ev.flushed_once = true
                    cb(ev)
                }
            case .all(let cb):
                cb(ev)
            }
        }
        
        let prev_count = ev.remaining.count
        ev.remaining = ev.remaining.filter { $0.relay != relay_id }
        let after_count = ev.remaining.count
        if ev.remaining.count == 0 {
            self.events.removeValue(forKey: event_id)
        }
        return prev_count != after_count
    }
    
    private func flush_event(_ event: EventPostTracker, to_relay: Relayer? = nil) -> RelayPool.SendProgress {
        var relayers = event.remaining
        if let to_relay {
            relayers = [to_relay]
        }
        
        var totalSendProgress: RelayPool.SendProgress = .init()
        
        for relayer in relayers {
            relayer.attempts += 1
            relayer.last_attempt = Int64(Date().timeIntervalSince1970)
            relayer.retry_after *= 1.5
            if pool.get_relay(relayer.relay) != nil {
                print("flushing event \(event.event.id) to \(relayer.relay)")
            } else {
                print("could not find relay when flushing: \(relayer.relay)")
            }
            let sendProgress = pool.send(.event(event.event), to: [relayer.relay], skip_ephemeral: event.skip_ephemeral)
            totalSendProgress = RelayPool.SendProgress(aggregating: [sendProgress])
        }
        return totalSendProgress
    }

    func send(_ event: NostrEvent, to: [RelayURL]? = nil, skip_ephemeral: Bool = true, delay: TimeInterval? = nil, on_flush: OnFlush? = nil) -> EventPostTracker? {
        // Don't add event if we already have it
        if events[event.id] != nil {
            return nil
        }

        let remaining = to ?? pool.our_descriptors.map { $0.url }
        let after = delay.map { d in Date.now.addingTimeInterval(d) }
        
        let posted_ev = EventPostTracker(event: event, remaining: remaining, skip_ephemeral: skip_ephemeral, flush_after: after, on_flush: on_flush, send_progress: Future() { promise in
            self.promises[event.id] = promise
        })
        
        self.events[event.id] = posted_ev
        
        if after == nil {
            self.promises[event.id]?(Result.success(self.flush_event(posted_ev)))
            self.promises[event.id] = nil
        }
        
        return posted_ev
    }
}


