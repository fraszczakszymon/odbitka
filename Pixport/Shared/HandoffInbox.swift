import Foundation
import PixportKit

/// Odbiór paczki przekazanej przez rozszerzenie udostępniania.
@Observable
@MainActor
final class HandoffInbox {
    private(set) var pending: HandoffSession?

    func receive(_ url: URL) {
        guard let sessionID = HandoffStore.sessionID(from: url),
              let manifest = HandoffStore.read(sessionID: sessionID)
        else { return }

        let photos = HandoffStore.photos(for: manifest)
        guard !photos.isEmpty else { return }
        pending = HandoffSession(id: sessionID, photos: photos)
    }

    func clear() {
        if let sessionID = pending?.id {
            HandoffStore.cleanUp(keeping: nil)
            _ = sessionID
        }
        pending = nil
    }
}

struct HandoffSession: Identifiable {
    let id: String
    let photos: [any SourcePhoto]
}
