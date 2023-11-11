//
//  NotificationService.swift
//  DamusNotificationService
//
//  Created by Daniel D’Aquino on 2023-11-10.
//

import UserNotifications
import Foundation

/// The representation of a JSON-encoded Nostr Event used by the push notification server
/// Needs to match with https://gitlab.com/soapbox-pub/strfry-policies/-/raw/433459d8084d1f2d6500fdf916f22caa3b4d7be5/src/types.ts
struct NostrEventInfoFromPushNotification: Codable {
    let id: String          // Hex-encoded
    let sig: String         // Hex-encoded
    let kind: Int
    let tags: [[String]]
    let pubkey: String      // Hex-encoded
    let content: String
    let created_at: Int
    
    static func from(dictionary: [AnyHashable: Any]) -> NostrEventInfoFromPushNotification? {
        guard let id = dictionary["id"] as? String,
              let sig = dictionary["sig"] as? String,
              let kind = dictionary["kind"] as? Int,
              let tags = dictionary["tags"] as? [[String]],
              let pubkey = dictionary["pubkey"] as? String,
              let content = dictionary["content"] as? String,
              let created_at = dictionary["created_at"] as? Int else {
            return nil
        }
        return NostrEventInfoFromPushNotification(id: id, sig: sig, kind: kind, tags: tags, pubkey: pubkey, content: content, created_at: created_at)
    }
}

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        
        do {
            // Get the shared container URL
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.damus") else {
                print("Error getting shared container URL")
                return
            }
            
            // Get the contents of the directory
            let fileURLs = try FileManager.default.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil)
            
            // Print the names of the files
            for fileURL in fileURLs {
                print("File: \(fileURL.lastPathComponent)")
            }
        } catch {
            print("Error reading file: \(error.localizedDescription)")
        }
        
        if let bestAttemptContent = bestAttemptContent {
            // Modify the notification content here...
            guard let nostrEventInfoDictionary = request.content.userInfo["nostr_event"] as? [AnyHashable: Any],
                  let nostrEventInfo = NostrEventInfoFromPushNotification.from(dictionary: nostrEventInfoDictionary) else {
                contentHandler(request.content)
                return;
            }
            
//            guard let ndb = Ndb() else {
//                contentHandler(request.content)
//            }
//            
//            ndb.process_event(JSONEncoder().encode(nostrEventInfo))
//            
//            let ndbTxn: NdbTxn<NostrEvent?> = ndb.lookup_note(nostrEventInfo.id)
//            
//            bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
            
            contentHandler(bestAttemptContent)
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}
