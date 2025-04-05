//
//  Ndb+.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-04-04.
//

/// ## Implementation notes
///
/// 1. This was created as a separate file because it contains dependencies to damus-specific structures such as `NostrFilter`, which is not yet available in the NostrDB codebase.

import Foundation

extension Ndb {
    func subscribe(filters: [NostrFilter], maxSimultaneousResults: Int = 1000) throws(NdbStreamError) -> AsyncStream<StreamItem> {
        let filtersPointer = UnsafeMutablePointer<ndb_filter>.allocate(capacity: filters.count)
        for (index, filter) in filters.enumerated() {
            do {
                let filterPointer = try filter.toNdbFilter()
                filtersPointer.advanced(by: index).pointee = filterPointer.pointee
            }
            catch {
                throw .cannotConvertFilter(error)
            }
        }
        
        // Fetch initial results
        guard let txn = NdbTxn(ndb: self) else { throw .cannotOpenTransaction }
        let count = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        let results = UnsafeMutablePointer<ndb_query_result>.allocate(capacity: maxSimultaneousResults)
        guard ndb_query(&txn.txn, filtersPointer,  Int32(filters.count), results, Int32(maxSimultaneousResults), count) == 1 else {
            throw .initialQueryFailed
        }
        
        return AsyncStream<StreamItem> { continuation in
            // Stream all results already present in the database
            for i in 0..<count.pointee {
                continuation.yield(.event(results.advanced(by: Int(i)).pointee.note_id))
            }
            
            // Indicate this is the end of the results currently present in the database
            continuation.yield(.eose)
            
            // Stream new results
            let subid = ndb_subscribe(self.ndb.ndb, filtersPointer, Int32(filters.count))
            let streamTask = Task {
                while true {
                    let result = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
                    ndb_wait_for_notes(self.ndb.ndb, subid, result, 1)
                    continuation.yield(.event(result.pointee))
                }
            }
            
            // Handle gracefully closing the stream
            continuation.onTermination = { @Sendable _ in
                streamTask.cancel()
                ndb_unsubscribe(self.ndb.ndb, subid)
            }
        }
    }
    
    private func waitWithoutTimeout(for noteId: NoteId) async throws(NdbLookupError) -> NdbTxn<NdbNote>? {
        do {
            for await item in try self.subscribe(filters: [NostrFilter(ids: [noteId])]) {
                switch item {
                case .eose: continue
                case .event(let noteKey):
                    guard let txn = NdbTxn(ndb: self) else { throw NdbLookupError.cannotOpenTransaction }
                    guard let note = self.lookup_note_by_key_with_txn(noteKey, txn: txn) else { throw NdbLookupError.internalInconsistency }
                    if note.id == noteId {
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
    
    func waitFor(noteId: NoteId, timeout: TimeInterval = 10) async throws(NdbLookupError) -> NdbTxn<NdbNote>? {
        do {
            return try await withCheckedThrowingContinuation({ continuation in
                let waitTask = Task {
                    do {
                        let result = try await self.waitWithoutTimeout(for: noteId)
                        continuation.resume(returning: result)
                    }
                    catch {
                        continuation.resume(throwing: error)
                    }
                }
                
                let timeoutTask = Task {
                    try await Task.sleep(for: .seconds(Int(timeout)))
                    waitTask.cancel()
                    continuation.resume(throwing: NdbLookupError.timeout)
                }
            })
        }
        catch {
            if let error = error as? NdbLookupError { throw error }
            else { throw .internalInconsistency }
        }
    }
    
    enum NdbStreamError: Error {
        case cannotOpenTransaction
        case cannotConvertFilter(NostrFilter.NdbFilterConversionError)
        case initialQueryFailed
    }
    
    enum NdbLookupError: Error {
        case cannotOpenTransaction
        case streamError(NdbStreamError)
        case internalInconsistency
        case timeout
    }
    
    enum StreamItem {
        case eose
        case event(NoteKey)
    }
}
