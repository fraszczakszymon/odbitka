import Foundation
import Testing
@testable import PixportKit

@Suite("Progi rozdzielczości")
struct TargetSizeTests {

    @Test("Nazwy progów odpowiadają rzeczywistym formatom obrazu")
    func presetNamesAreTruthful() {
        let byName = Dictionary(uniqueKeysWithValues: TargetSize.presets.compactMap { preset in
            preset.name.map { ($0, preset.pixels) }
        })
        // Długi bok każdego z tych formatów. Gdyby ktoś kiedyś podmienił wartość,
        // nazwa zaczęłaby kłamać — a to jedyna rzecz, której ten zestaw ma nie robić.
        #expect(byName["SD"] == 640)        // 480p
        #expect(byName["HD"] == 1280)       // 720p
        #expect(byName["Full HD"] == 1920)  // 1080p
        #expect(byName["QHD"] == 2560)      // 1440p
        #expect(byName["4K"] == 3840)       // 2160p / UHD
        #expect(byName["2K"] == nil, "2K znaczy co innego w kinie, a co innego w sklepie")
    }

    @Test("Etykieta łączy nazwę z liczbą pikseli")
    func labelFormat() {
        #expect(TargetSize.label(forLongEdge: 1920) == "Full HD (1920 px)")
        #expect(TargetSize.label(forLongEdge: 3840) == "4K (3840 px)")
    }

    @Test("Wartość spoza progów pokazuje same piksele")
    func unnamedValue() {
        #expect(TargetSize.label(forLongEdge: 1600) == "1600 px")
        #expect(TargetSize.label(forLongEdge: 777) == "777 px")
    }

    @Test("Progi są uporządkowane rosnąco i bez powtórzeń")
    func presetsAreOrdered() {
        let values = TargetSize.presetValues
        #expect(values == values.sorted())
        #expect(Set(values).count == values.count)
    }

    @Test("Najniższy próg nie schodzi poniżej dolnej granicy trybu budżetowego")
    func lowestPresetMatchesBudgetFloor() {
        // Inaczej solver mógłby zejść niżej, niż użytkownik może wybrać ręcznie.
        #expect(TargetSize.presetValues.first == BudgetSolver.longEdgeFloor)
    }

    @Test("Domyślne ustawienie trafia w nazwany próg")
    func defaultIsANamedPreset() {
        let pixels = ConversionSettings.default.targetSize.pixels
        #expect(pixels == 1920)
        #expect(TargetSize.presets.contains { $0.pixels == pixels })
    }
}
