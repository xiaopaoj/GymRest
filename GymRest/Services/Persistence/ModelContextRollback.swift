import SwiftData

extension ModelContext {
    @MainActor func discardPendingChanges() {
        // Register synchronous model edits before asking SwiftData to restore committed values.
        // No save is performed here: failed edits must never reach the persistent store.
        processPendingChanges()
        rollback()
    }
}
