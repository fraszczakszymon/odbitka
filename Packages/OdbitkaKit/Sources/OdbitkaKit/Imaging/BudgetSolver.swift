import Foundation

/// Dobieranie ustawień pod limit „zmieść wszystko w X MB".
///
/// Tryb budżetowy nie zgaduje — przetwarza naprawdę, mierzy wynik i jeśli trzeba,
/// powtarza z ostrzejszymi ustawieniami. Dzięki temu limit maila jest gwarantowany,
/// a nie szacowany. Ta funkcja odpowiada na jedno pytanie: „nie zmieściliśmy się,
/// co spróbować następnym razem".
///
/// Kolejność ustępstw jest przemyślana: **najpierw jakość, dopiero potem rozdzielczość.**
/// Zejście z jakości JPEG z 85% na 70% jest praktycznie niewidoczne, a zbija rozmiar
/// o jedną trzecią. Zejście z rozdzielczości nieodwracalnie usuwa piksele.
public enum BudgetSolver {

    /// Poniżej tej jakości JPEG zaczyna być widocznie brzydki (artefakty na gładkich
    /// przejściach, obwódki przy krawędziach). Wolimy zejść z rozdzielczości.
    public static let qualityFloor = 0.35
    /// Poniżej tej rozdzielczości zdjęcie przestaje być użyteczne do czegokolwiek.
    public static let longEdgeFloor = 640

    /// Proponuje ostrzejsze ustawienia po nieudanej próbie.
    ///
    /// - Returns: `nil`, gdy nie ma już czego oddać — wtedy przebieg kończy się błędem
    ///   `budgetUnreachable`, a użytkownik dostaje konkretną informację zamiast
    ///   w nieskończoność mielącego telefonu.
    public static func tighten(
        _ settings: ConversionSettings,
        achieved: Int64,
        budget: Int64,
        sourceLongEdge: Int
    ) -> ConversionSettings? {
        guard achieved > budget, budget > 0 else { return nil }
        let ratio = Double(budget) / Double(achieved)

        var next = settings

        if settings.format.supportsQuality, settings.quality > qualityFloor {
            // Rozmiar JPEG zmienia się wolniej niż liniowo wraz z jakością, stąd
            // pierwiastek — zbyt agresywny krok potrafi przestrzelić w dół o połowę
            // i niepotrzebnie zepsuć zdjęcia.
            let proposed = settings.quality * ratio.squareRoot()
            // Wymuszamy zauważalny krok, żeby pętla nie dreptała w miejscu.
            let stepped = min(proposed, settings.quality - 0.05)
            next.quality = max(qualityFloor, stepped)
            if next.quality < settings.quality { return next }
        }

        let currentLongEdge = settings.targetSize.pixels ?? sourceLongEdge
        guard currentLongEdge > longEdgeFloor else { return nil }

        // Liczba pikseli rośnie z kwadratem boku, więc żeby zbić rozmiar o `ratio`,
        // bok musi zmaleć o pierwiastek z `ratio`.
        let proposedEdge = Int((Double(currentLongEdge) * ratio.squareRoot()).rounded(.down))
        let steppedEdge = min(proposedEdge, Int(Double(currentLongEdge) * 0.85))
        let newEdge = max(longEdgeFloor, steppedEdge)
        guard newEdge < currentLongEdge else { return nil }

        next.targetSize = .longEdge(newEdge)
        return next
    }
}
