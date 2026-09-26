// Generator ikony aplikacji. Uruchamiany ręcznie:
//     swift Tools/make-icon.swift Pixport/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// Ikona powstaje kodem, a nie w edytorze graficznym, żeby dała się odtworzyć
// i poprawić razem z resztą projektu — bez szukania pliku źródłowego w cudzym katalogu.
//
// Motyw: dwa zdjęcia wysunięte jedno spod drugiego, gotowe do drogi. Dokładnie to,
// co robi aplikacja: z oryginałów robi kopie do wysłania, nie ruszając pierwowzorów.

import AppKit
import CoreGraphics
import Foundation

let side = 1024
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
          data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
          // Bez kanału alfa. App Store odrzuca ikony z przezroczystością błędem 90717,
          // a Core Graphics na macOS nie zna kontekstu 24-bitowego — `noneSkipLast`
          // daje cztery bajty na piksel z ostatnim ignorowanym, czyli obraz nieprzezroczysty.
          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )
else { fatalError("Nie udało się utworzyć kontekstu rysowania") }

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// Tło: ciepła ciemność ciemni fotograficznej.
let background = CGGradient(
    colorsSpace: space,
    colors: [color(0.13, 0.11, 0.14), color(0.06, 0.05, 0.07)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    background,
    start: CGPoint(x: 0, y: side),
    end: CGPoint(x: side, y: 0),
    options: []
)

/// Rysuje pojedyncze zdjęcie: biała ramka z obrazem w środku.
func drawPrint(center: CGPoint, size: CGSize, rotation: CGFloat, photo: [CGColor], shadow: Bool) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: rotation)

    let frame = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    let path = CGPath(roundedRect: frame, cornerWidth: 26, cornerHeight: 26, transform: nil)

    if shadow {
        context.setShadow(offset: CGSize(width: 0, height: -18), blur: 42, color: color(0, 0, 0, 0.55))
    }
    context.setFillColor(color(0.98, 0.97, 0.95))
    context.addPath(path)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    // Pole zdjęcia — z szerszym marginesem u dołu, jak w klasycznej odbitce.
    let inset: CGFloat = 34
    let photoRect = CGRect(
        x: frame.minX + inset,
        y: frame.minY + inset * 2.4,
        width: frame.width - inset * 2,
        height: frame.height - inset * 3.4
    )
    context.saveGState()
    context.addPath(CGPath(roundedRect: photoRect, cornerWidth: 10, cornerHeight: 10, transform: nil))
    context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: photo as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: photoRect.minX, y: photoRect.maxY),
        end: CGPoint(x: photoRect.maxX, y: photoRect.minY),
        options: []
    )
    context.restoreGState()

    context.restoreGState()
}

// Pixport spodnia — przygaszona, lekko odchylona: sygnał, że pracujemy na paczkach.
drawPrint(
    center: CGPoint(x: side / 2 - 60, y: side / 2 - 30),
    size: CGSize(width: 430, height: 500),
    rotation: -0.20,
    photo: [color(0.42, 0.45, 0.52), color(0.26, 0.28, 0.34)],
    shadow: true
)

// Pixport wierzchnia — pełna barwa.
drawPrint(
    center: CGPoint(x: side / 2 + 55, y: side / 2 + 20),
    size: CGSize(width: 430, height: 500),
    rotation: 0.10,
    photo: [color(0.96, 0.60, 0.22), color(0.85, 0.28, 0.24)],
    shadow: true
)

guard let image = context.makeImage() else { fatalError("Nie udało się wyrenderować ikony") }

// Zapis bez kanału alfa. App Store odbija ikony z przezroczystością błędem 90717.
//
// `NSBitmapImageRep(cgImage:)` wystarcza tylko dlatego, że kontekst wyżej jest
// `noneSkipLast` — reprezentacja dziedziczy po nim brak alfy. Wcześniejsza wersja
// przerysowywała obraz do reprezentacji 24-bitowej i wychodziła z tego czarna plama:
// Core Graphics nie zna kontekstu o trzech bajtach na piksel, więc
// `NSGraphicsContext(bitmapImageRep:)` zwracał nil, a rysowanie było pustą operacją.
let bitmap = NSBitmapImageRep(cgImage: image)

guard !bitmap.hasAlpha else {
    fatalError("Ikona wyszła z kanałem alfa — App Store odrzuci ją błędem 90717")
}

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Nie udało się zakodować PNG")
}
try data.write(to: URL(fileURLWithPath: outputPath))
print("Zapisano \(outputPath) — \(side)×\(side), bez kanału alfa")
