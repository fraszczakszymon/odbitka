<p align="center">
  <img src="docs/icon.png" alt="Pixport" width="168">
</p>

<h1 align="center">Pixport</h1>

<p align="center">
  <strong>Przygotowuje zdjęcia z iPhone'a do wysłania.</strong><br>
  HEIC → JPG lub PNG, zmniejszanie, czyszczenie metadanych, wspólna nazwa z numeracją, ZIP.<br>
  W całości na urządzeniu — aplikacja nie ma serwera.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platforma-iOS%2026-black" alt="iOS 26">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/zale%C5%BCno%C5%9Bci-brak-brightgreen" alt="bez zależności">
</p>

---

## Problem

Zdjęcia z iPhone'a zapisują się w HEIC. Ten format **nie otwiera się** na sporej części
Windowsów, starszych Androidów, w wielu systemach CRM i w połowie firmowych narzędzi.
Do tego jedno zdjęcie z nowoczesnego aparatu potrafi ważyć 5 MB, a Gmail przyjmuje
25 MB załączników — czyli pięć zdjęć.

Narzędzia, które to rozwiązują, zwykle każą wysłać zdjęcia na cudzy serwer albo
zapłacić abonament za przekonwertowanie pliku.

## Co robi Pixport

- **Konwertuje** HEIC (oraz JPEG, PNG i RAW) na **JPG albo PNG**
- **Zmniejsza** — dłuższy bok do wyboru: SD, HD, Full HD, QHD, 4K lub własna wartość
- **Mieści w limicie** — tryb „zmieść wszystko w 25 MB" przetwarza naprawdę i w razie
  potrzeby obniża jakość, więc limit maila jest **gwarantowany, nie szacowany**
- **Czyści metadane** — osobno lokalizacja, data i dane aparatu. Opisy, słowa kluczowe
  i dane producenta wycinane są zawsze
- **Nazywa całą paczkę** — wpisujesz „Łazienka", dostajesz `Lazienka_001.jpg … Lazienka_047.jpg`
- **Pakuje do ZIP**, z opcjonalnym podziałem na części mieszczące się w limicie maila
- **Udostępnia** — arkusz systemowy, zapis do Plików (a przez nie na Dysk Google)
  albo z powrotem do biblioteki zdjęć
- **Radzi sobie z limitem 10 zdjęć** w komunikatorach — ekran porcji z ręczną kontrolą
- Działa też jako **rozszerzenie udostępniania**: Zdjęcia → Udostępnij → Pixport

## Czego nie robi

- **Nie wysyła niczego na serwer.** Nie ma serwera. Jedyny ruch sieciowy to pobranie
  z iCloud zdjęć, których nie ma na urządzeniu — robi to sam system, z Twojego konta
- **Nie zmienia oryginałów.** Biblioteka zdjęć nie jest modyfikowana, powstają kopie
- Nie ma reklam, konta ani zakupów w aplikacji
- Nie jest edytorem — kadrowanie, filtry i znaki wodne to inna aplikacja

## Jak to jest zbudowane

SwiftUI i Swift 6, minimum iOS 26, **zero zależności zewnętrznych** — łącznie z zapisem
archiwum ZIP, który jest własny (strumieniowy, ZIP64).

```
Packages/PixportKit/   silnik: konwersja, metadane, nazewnictwo, ZIP, pipeline
                       nie zna PhotoKit ani UIKit, więc testuje się zwykłymi plikami
Pixport/               aplikacja — cienka warstwa SwiftUI
PixportShare/          rozszerzenie udostępniania
```

Testowany jest **wyłącznie silnik**, i to celowo: sprawdzamy to, czego nie widać na
ekranie. Najważniejszy test bierze prawdziwy plik ze współrzędnymi GPS i sprawdza, że po
konwersji **ich nie ma** — błąd w tym miejscu jest niewidoczny, a kosztowałby użytkownika
wysłanie obcej osobie adresu swojego mieszkania.

## Budowanie

```bash
xcodegen generate                              # projekt Xcode powstaje z project.yml
swift test --package-path Packages/PixportKit  # testy silnika, bez symulatora
./Tools/release.sh --check-only                # kontrola przed wydaniem
./Tools/release.sh                             # archiwum + .ipa dla TestFlight
```

`Pixport.xcodeproj` jest **artefaktem**, nie źródłem — zmiany wprowadzone w edytorze
Xcode znikną przy najbliższym `xcodegen generate`. Ustawienia projektu żyją w `project.yml`.

Ikona też powstaje kodem:

```bash
swift Tools/make-icon.swift Pixport/Assets.xcassets/AppIcon.appiconset/AppIcon.png
swift Tools/make-icon.swift docs/icon.png --rounded --size 512
```

## Dokumentacja

| Plik | Co zawiera |
|---|---|
| [`SPEC.md`](SPEC.md) | specyfikacja produktowa: każda decyzja wraz z uzasadnieniem i świadomie odrzucone warianty |
| [`AGENTS.md`](AGENTS.md) | stack, architektura, konwencje, pułapki i procedura wydawnicza |

## Status

Wersja 1.0, przygotowana do TestFlight. Aplikacja prywatna, darmowa, bez reklam.
