import Foundation
import UniformTypeIdentifiers

/// Formaty, do których Odbitka potrafi zapisać.
///
/// HEIC i PDF świadomie poza zakresem v1 — patrz `SPEC.md`, sekcja „Poza zakresem".
public enum ImageFormat: String, CaseIterable, Sendable, Codable {
    case jpeg
    case png

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        }
    }

    public var utType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        }
    }

    /// PNG jest bezstratny — suwak jakości nie ma tam żadnego znaczenia.
    public var supportsQuality: Bool { self == .jpeg }
}
