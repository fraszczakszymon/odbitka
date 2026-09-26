import Foundation
import PixportKit

/// Tłumaczenie błędów silnika na komunikaty dla człowieka.
///
/// Semantyka wszystko-albo-nic sprawia, że każdy błąd kosztuje użytkownika całą paczkę.
/// Komunikat musi więc mówić, co konkretnie poszło nie tak i co z tym zrobić —
/// „wystąpił błąd" byłoby tu wyjątkowo kosztowne.
struct ErrorPresentation {
    let title: String
    let message: String

    init(_ error: any Error) {
        guard let conversionError = error as? ConversionError else {
            title = L.s("error.generic.title")
            message = error.localizedDescription
            return
        }

        switch conversionError {
        case .photosNotAvailableOffline(let count):
            title = L.s("error.offline.title")
            message = L.f("error.offline.message", count)

        case .insufficientDiskSpace(let required, let available):
            title = L.s("error.space.title")
            message = L.f(
                "error.space.message",
                ByteFormatting.string(required),
                ByteFormatting.string(available)
            )

        case .cannotReadSource(let fileName):
            title = L.s("error.read.title")
            message = L.f("error.read.message", fileName)

        case .unsupportedSource(let fileName):
            title = L.s("error.unsupported.title")
            message = L.f("error.unsupported.message", fileName)

        case .encodingFailed(let fileName):
            title = L.s("error.encoding.title")
            message = L.f("error.encoding.message", fileName)

        case .cannotWriteOutput(let underlying):
            title = L.s("error.write.title")
            message = L.f("error.write.message", underlying)

        case .budgetUnreachable(let target, let best):
            title = L.s("error.budget.title")
            message = L.f(
                "error.budget.message",
                ByteFormatting.string(target),
                ByteFormatting.string(best)
            )

        case .fileLargerThanPart(let fileName, let fileSize, let partLimit):
            title = L.s("error.part.title")
            message = L.f(
                "error.part.message",
                fileName,
                ByteFormatting.string(fileSize),
                ByteFormatting.string(partLimit)
            )

        case .cancelled:
            title = L.s("error.cancelled.title")
            message = L.s("error.cancelled.message")
        }
    }
}
