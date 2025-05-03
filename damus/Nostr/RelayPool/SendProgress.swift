//
//  SendProgress.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-04-30.
//

import Combine

extension RelayPool {
    class SendProgress {
        private(set) var statuses: [RelayURL: Future<NostrRequest.Response, Never>]
        
        init() {
            self.statuses = [:]
        }
        
        init(aggregating progressObjects: [SendProgress]) {
            var statuses: [RelayURL: Future<NostrRequest.Response, Never>] = [:]
            for sendProgressObject in progressObjects {
                statuses.merge(sendProgressObject.statuses) { (_, new) in new }
            }
            self.statuses = statuses
        }
        
        func add(relay: RelayURL, future: Future<NostrRequest.Response, Never>) {
            self.statuses[relay] = future
        }
        
        func waitAll() async -> [RelayURL: NostrRequest.Response] {
            var responses: [RelayURL: NostrRequest.Response] = [:]
            for (relay, future) in self.statuses {
                responses[relay] = await future.value
            }
            return responses
        }
    }
}
