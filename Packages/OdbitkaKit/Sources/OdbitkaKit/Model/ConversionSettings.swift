import Foundation

/// Docelowy rozmiar obrazu, wyrażony przez dłuższy bok.
public enum TargetSize: Sendable, Codable, Equatable {
    case original
    case longEdge(Int)

    public var pixels: Int? {
        switch self {
        case .original: nil
        case .longEdge(let value): value
        }
    }

    /// Wartości pokazywane na ekranie ustawień jako gotowe do wyboru.
    public static let presetValues = [1280, 1600, 2048, 2560]
}

/// Limit wielkości nałożony na cały wynik.
public struct SizeBudget: Sendable, Codable, Equatable {
    public var isEnabled: Bool
    public var megabytes: Int

    public init(isEnabled: Bool = false, megabytes: Int = 25) {
        self.isEnabled = isEnabled
        self.megabytes = megabytes
    }

    public var bytes: Int64 { Int64(megabytes) * 1_000_000 }
}

/// Ustawienia pakowania wyniku.
public struct PackagingSettings: Sendable, Codable, Equatable {
    public var makeZip: Bool
    public var splitIntoParts: Bool
    public var partMegabytes: Int

    public init(makeZip: Bool = false, splitIntoParts: Bool = false, partMegabytes: Int = 25) {
        self.makeZip = makeZip
        self.splitIntoParts = splitIntoParts
        self.partMegabytes = partMegabytes
    }

    public var partBytes: Int64 { Int64(partMegabytes) * 1_000_000 }
}

/// Komplet decyzji użytkownika z ekranu ustawień.
public struct ConversionSettings: Sendable, Codable, Equatable {
    public var format: ImageFormat
    public var targetSize: TargetSize
    /// 0.0 – 1.0, używane wyłącznie dla JPEG.
    public var quality: Double
    public var budget: SizeBudget
    /// Konwersja do sRGB. Display P3 wygląda przesycony wszędzie, gdzie profil ICC
    /// jest ignorowany — a to większość świata poza Apple.
    public var convertToSRGB: Bool
    public var metadata: MetadataPolicy
    /// Prefiks nazw plików. Puste = zachowujemy nazwy oryginalne.
    public var namePrefix: String
    public var packaging: PackagingSettings

    public init(
        format: ImageFormat = .jpeg,
        targetSize: TargetSize = .longEdge(1600),
        quality: Double = 0.85,
        budget: SizeBudget = SizeBudget(),
        convertToSRGB: Bool = true,
        metadata: MetadataPolicy = .default,
        namePrefix: String = "",
        packaging: PackagingSettings = PackagingSettings()
    ) {
        self.format = format
        self.targetSize = targetSize
        self.quality = quality
        self.budget = budget
        self.convertToSRGB = convertToSRGB
        self.metadata = metadata
        self.namePrefix = namePrefix
        self.packaging = packaging
    }

    public static let `default` = ConversionSettings()

    /// Efektywna jakość — PNG ignoruje suwak.
    public var effectiveQuality: Double {
        format.supportsQuality ? quality : 1.0
    }
}
