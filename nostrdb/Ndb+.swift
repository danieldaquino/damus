//
//  Ndb+.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-04-04.
//

/// ## Implementation notes
///
/// 1. This was created as a separate file because it contains dependencies to damus-specific structures such as `NostrFilter`, which is not yet available inside the NostrDB codebase.

import Foundation

extension Ndb {
    /// Subscribes to NostrDB using a `NostrFilter`
    func subscribe(filters: [NostrFilter], maxSimultaneousResults: Int = 1000) throws(NdbStreamError) -> AsyncStream<StreamItem> {
        var ndbFilters: [ndb_filter] = []
        for (index, filter) in filters.enumerated() {
            do {
                let filter = try filter.toNdbFilter()
                ndbFilters.append(filter)
            }
            catch {
                throw .cannotConvertFilter(error)
            }
        }
        
        return try self.subscribe(filters: filters, maxSimultaneousResults: maxSimultaneousResults)
    }
    
    private func waitWithoutTimeout(for noteId: NoteId) async throws(NdbLookupError) -> NdbTxn<NdbNote>? {
        do {
            for try await item in try self.subscribe(filters: [NostrFilter(ids: [noteId])]) {
                switch item {
                case .eose:
                    continue
                case .event(let noteKey):
                    guard let txn = NdbTxn(ndb: self) else { throw NdbLookupError.cannotOpenTransaction }
                    guard let note = self.lookup_note_by_key_with_txn(noteKey, txn: txn) else { throw NdbLookupError.internalInconsistency }
                    if note.id == noteId {
                        Log.debug("ndb wait: %d has matching id %s. Returning transaction", for: .ndb, noteKey, noteId.hex())
                        return NdbTxn<NdbNote>.pure(ndb: self, val: note)
                    }
                }
            }
        }
        catch {
            if let error = error as? NdbStreamError { throw NdbLookupError.streamError(error) }
            else if let error = error as? NdbLookupError { throw error }
            else { throw .internalInconsistency }
        }
        return nil
    }
    
    /// Waits until a given note id is available in NostrDB
    func waitFor(noteId: NoteId, timeout: TimeInterval = 10) async throws(NdbLookupError) -> NdbTxn<NdbNote>? {
        do {
            return try await withCheckedThrowingContinuation({ continuation in
                var done = false
                Task {
                    do {
                        Log.debug("ndb wait: Waiting for %s", for: .ndb, noteId.hex())
                        let result = try await self.waitWithoutTimeout(for: noteId)
                        if !done {
                            Log.debug("ndb wait: Found %s", for: .ndb, noteId.hex())
                            continuation.resume(returning: result)
                            done = true
                        }
                    }
                    catch {
                        if !done {
                            Log.debug("ndb wait: Error on %s: %s", for: .ndb, noteId.hex(), error.localizedDescription)
                            continuation.resume(throwing: error)
                            done = true
                        }
                    }
                }
                
                Task {
                    try await Task.sleep(for: .seconds(Int(timeout)))
                    if !done {
                        Log.debug("ndb wait: Timeout on %s", for: .ndb, noteId.hex())
                        continuation.resume(throwing: NdbLookupError.timeout)
                        done = true
                    }
                }
            })
        }
        catch {
            if let error = error as? NdbLookupError { throw error }
            else { throw .internalInconsistency }
        }
    }
}
