//
//  PresentSheetNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct PresentSheetNotify: Notify {
    typealias Payload = Sheets
    var payload: Payload
}

extension NotifyHandler {
    static var present_sheet: NotifyHandler<PresentSheetNotify> {
        .init()
    }
}

extension Notifications {
    static func present_sheet(_ sheet: Sheets) -> Notifications<PresentSheetNotify> {
        .init(.init(payload: sheet))
    }
}





struct PresentFullScreenItemNotify: Notify {
    typealias Payload = FullScreenItem
    var payload: Payload
}

extension NotifyHandler {
    static var present_full_screen_item: NotifyHandler<PresentFullScreenItemNotify> {
        .init()
    }
}

extension Notifications {
    static func present_full_screen_item(_ item: FullScreenItem) -> Notifications<PresentFullScreenItemNotify> {
        .init(.init(payload: item))
    }
}

func present(full_screen_item: FullScreenItem) {
    notify(.present_full_screen_item(full_screen_item))
}
