//
//  InsertSort.swift
//  damus
//
//  Created by William Casarin on 2022-05-09.
//

import Foundation

func insert_uniq_sorted_zap(zaps: inout [Zapping], new_zap: Zapping, cmp: (Zapping, Zapping) -> Bool) -> Bool {
    var i: Int = 0
    
    for zap in zaps {
        if new_zap.request.ev.id == zap.request.ev.id {
            // replace pending
            if !new_zap.is_pending && zap.is_pending {
                print("nwc: replacing pending with real zap \(new_zap.request.ev.id)")
                zaps[i] = new_zap
                return true
            }
            // don't insert duplicate events
            return false
        }
        
        if cmp(new_zap, zap)  {
            zaps.insert(new_zap, at: i)
            return true
        }
        i += 1
    }
    
    zaps.append(new_zap)
    return true
}

@discardableResult
func insert_uniq_sorted_zap_by_created(zaps: inout [Zapping], new_zap: Zapping) -> Bool {
    return insert_uniq_sorted_zap(zaps: &zaps, new_zap: new_zap) { (a, b) in
        a.created_at > b.created_at
    }
}

@discardableResult
func insert_uniq_sorted_zap_by_amount(zaps: inout [Zapping], new_zap: Zapping) -> Bool {
    return insert_uniq_sorted_zap(zaps: &zaps, new_zap: new_zap) { (a, b) in
        a.amount > b.amount
    }
}

func insert_uniq_sorted_event_created(events: inout [NostrEvent], new_ev: NostrEvent) -> Bool {
    return insert_uniq_sorted_event(events: &events, new_ev: new_ev) {
        $0.created_at > $1.created_at
    }
}

@discardableResult
func insert_uniq_sorted_event(events: inout [NostrEvent], new_ev: NostrEvent, cmp: (NostrEvent, NostrEvent) -> Bool) -> Bool {
    return insert_unique_sorted_for_presorted_items(items: &events, new_item: new_ev, comparator: cmp)
}

@discardableResult
/// An efficient O(log(n)) sorted insertion function for items that are pre-sorted.
/// - Parameters:
///   - items: The items array where to insert the new item. MUST adhere to the following assumptions for the algorithm to work:
///     - MUST be pre-sorted
///     - Items with the same ID must have the same value that is being used for sorting.
///   - new_item: The new item to insert
///   - comparator: The comparison function
/// - Returns: Whether item was inserted or not
func insert_unique_sorted_for_presorted_items<T: Identifiable>(items: inout [T], new_item: T, comparator: (T, T) -> Bool) -> Bool {
    if items.isEmpty {
        items.append(new_item)
        return true
    }
    
    var low = 0
    var high = items.count - 1
    
    while low <= high {
        let mid = low + (high - low) / 2
        if items[mid].id == new_item.id {
            return false // Element already exists
        }
        
        if comparator(new_item, items[mid]) {
            high = mid - 1
        } else {
            low = mid + 1
        }
    }
    
    // Check boundaries for exact match with neighboring elements on the found index low
    if low < items.count && items[low].id == new_item.id {
        return false // Checks if the low position contains a duplicate id
    }
    if low > 0 && items[low - 1].id == new_item.id {
        return false // Checks the previous position for a duplicate id
    }

    // Insert element at the calculated position
    items.insert(new_item, at: low)
    return true
}
