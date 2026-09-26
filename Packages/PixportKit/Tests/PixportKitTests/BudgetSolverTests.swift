import Foundation
import Testing
@testable import PixportKit

@Suite("Dobieranie ustawień pod limit")
struct BudgetSolverTests {

    @Test("Nic nie zmienia, gdy jesteśmy w limicie")
    func stopsWhenWithinBudget() {
        let result = BudgetSolver.tighten(.default, achieved: 10_000_000, budget: 25_000_000, sourceLongEdge: 4032)
        #expect(result == nil)
    }

    @Test("Najpierw schodzi z jakości, nie z rozdzielczości")
    func lowersQualityFirst() throws {
        var settings = ConversionSettings.default
        settings.targetSize = .longEdge(1600)
        settings.quality = 0.85

        let tightened = try #require(
            BudgetSolver.tighten(settings, achieved: 50_000_000, budget: 25_000_000, sourceLongEdge: 4032)
        )
        #expect(tightened.quality < 0.85)
        #expect(tightened.targetSize == .longEdge(1600), "Rozdzielczość to ostateczność, nie pierwszy odruch")
    }

    @Test("Po wyczerpaniu jakości schodzi z rozdzielczości")
    func lowersResolutionAfterQuality() throws {
        var settings = ConversionSettings.default
        settings.quality = BudgetSolver.qualityFloor
        settings.targetSize = .longEdge(2560)

        let tightened = try #require(
            BudgetSolver.tighten(settings, achieved: 40_000_000, budget: 25_000_000, sourceLongEdge: 4032)
        )
        #expect(tightened.targetSize.pixels ?? 0 < 2560)
        #expect(tightened.quality == BudgetSolver.qualityFloor)
    }

    @Test("PNG nie ma jakości, więc od razu schodzi z rozdzielczości")
    func pngGoesStraightToResolution() throws {
        var settings = ConversionSettings.default
        settings.format = .png
        settings.targetSize = .longEdge(2048)

        let tightened = try #require(
            BudgetSolver.tighten(settings, achieved: 90_000_000, budget: 25_000_000, sourceLongEdge: 4032)
        )
        #expect(tightened.targetSize.pixels ?? 0 < 2048)
    }

    @Test("Poddaje się przy obu dolnych granicach zamiast mielić w nieskończoność")
    func givesUpAtFloors() {
        var settings = ConversionSettings.default
        settings.quality = BudgetSolver.qualityFloor
        settings.targetSize = .longEdge(BudgetSolver.longEdgeFloor)

        let result = BudgetSolver.tighten(settings, achieved: 99_000_000, budget: 1_000_000, sourceLongEdge: 4032)
        #expect(result == nil)
    }

    @Test("Każdy krok jest zauważalny — pętla nie drepcze w miejscu")
    func alwaysMakesProgress() throws {
        var settings = ConversionSettings.default
        settings.quality = 0.9
        // Minimalne przekroczenie limitu mogłoby dać krok bliski zeru.
        let tightened = try #require(
            BudgetSolver.tighten(settings, achieved: 25_100_000, budget: 25_000_000, sourceLongEdge: 4032)
        )
        #expect(settings.quality - tightened.quality >= 0.049)
    }
}
