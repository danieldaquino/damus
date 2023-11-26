//
//  NotificationService.swift
//  DamusNotificationService
//
//  Created by Daniel D’Aquino on 2023-11-10.
//

import UserNotifications
import Foundation

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        
        guard let nostrEventJSON = request.content.userInfo["nostr_event"] as? String,
              let nostrEvent = NdbNote.owned_from_json(json: nostrEventJSON)
        else {
            // No nostr event detected. Just display the original notification
            contentHandler(request.content)
            return;
        }
        
        // Log that we got a push notification
        Log.debug("Got nostr event push notification from pubkey %s", for: .push_notifications, nostrEvent.pubkey.hex())
        
        
        guard let ndb = try? Ndb(owns_db_file: false),
              let our_keypair = get_saved_keypair(),
              let display_name = ndb.lookup_profile(nostrEvent.pubkey).unsafeUnownedValue?.profile?.display_name
        else {
            // Something failed to initialize so let's go for the next best thing
            guard let improved_content = NotificationFormatter.shared.format_message(event: nostrEvent) else {
                // We cannot format this nostr event. Suppress notification.
                contentHandler(UNNotificationContent())
                return
            }
            contentHandler(improved_content)
            return
        }
        
        // Initialize some stuff that we will need for processing notification
        let contacts = Contacts(our_pubkey: our_keypair.pubkey)
        let muted_threads = MutedThreadsManager(keypair: our_keypair)
        let profiles = Profiles(ndb: ndb)
        let settings = UserSettingsStore()
        
        guard should_display_notification(ndb: ndb, settings: settings, contacts: contacts, muted_threads: muted_threads, user_keypair: our_keypair, profiles: profiles, event: nostrEvent) else {
            // We should not display notification for this event. Suppress notification.
            contentHandler(UNNotificationContent())
            return
        }
        
        guard let notification_object: LocalNotification = generate_local_notification_object(
            ndb: ndb,
            from: nostrEvent,
            settings: settings,
            user_keypair: our_keypair,
            profiles: profiles
        ) else {
            // We could not process this notification. Probably an unsupported nostr event kind. Suppress.
            contentHandler(UNNotificationContent())
            return
        }
        
        let (improvedContent, _) = NotificationFormatter.shared.format_message(displayName: display_name, notify: notification_object)
        contentHandler(improvedContent)
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}
