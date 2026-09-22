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

    /// Gotowy próg rozdzielczości pokazywany na ekranie ustawień.
    public struct Preset: Sendable, Hashable, Identifiable {
        public let pixels: Int
        /// Potoczna nazwa progu, o ile jakaś istnieje i jest prawdziwa.
        public let name: String?

        public var id: Int { pixels }

        /// „Full HD (1920 px)" albo samo „1600 px", gdy nazwy nie ma.
        public var label: String {
            guard let name else { return "\(pixels) px" }
            return "\(name) (\(pixels) px)"
        }
    }

    /// Progi do wyboru na ekranie ustawień.
    ///
    /// Wartości są **kanoniczne**, żeby nazwy nie kłamały. Każda odpowiada długiemu
    /// bokowi znanego formatu obrazu:
    /// 640 = 480p, 1280 = 720p, 1920 = 1080p, 2560 = 1440p, 3840 = 2160p (UHD).
    ///
    /// Świadomie nie ma tu „2K": w kinie oznacza 2048 px, w sprzedaży monitorów 2560 px,
    /// więc obok „4K" byłoby myląco niejednoznaczne. 1440p nazywamy QHD, bo to nazwa,
    /// która ma jedno znaczenie.
    public static let presets: [Preset] = [
        Preset(pixels: 640, name: "SD"),
        Preset(pixels: 1280, name: "HD"),
        Preset(pixels: 1920, name: "Full HD"),
        Preset(pixels: 2560, name: "QHD"),
        Preset(pixels: 3840, name: "4K")
    ]

    public static var presetValues: [Int] { presets.map(\.pixels) }

    /// Etykieta dowolnej wartości — nazwana, jeśli trafia w próg, inaczej same piksele.
    public static func label(forLongEdge pixels: Int) -> String {
        presets.first { $0.pixels == pixels }?.label ?? "\(pixels) px"
    }
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
        targetSize: TargetSize = .longEdge(1920),
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
