# Odbitka — specyfikacja aplikacji

> Aplikacja na iPhone'a, która przygotowuje zdjęcia do wysłania: zamienia HEIC na JPG
> lub PNG, zmniejsza je, czyści metadane, nadaje wspólną nazwę z numeracją i pakuje.
> Wszystko dzieje się na urządzeniu — aplikacja nie ma serwera i nie wysyła nigdzie
> Twoich zdjęć.

Nazwa niesie całą ideę: **robisz odbitkę, żeby komuś dać — oryginał zostaje u Ciebie.**
Biblioteka zdjęć nigdy nie jest modyfikowana.

Interfejs po polsku i angielsku. Bundle ID: `pl.froncek.odbitka`.

---

## 1. Stack technologiczny

- **SwiftUI** w całości, **Swift 6**, minimalny system **iOS 26** (bieżące pokolenie —
  dzięki temu w kodzie nie ma ani jednego `if #available`).
- Obrazy: **ImageIO** i **Core Graphics**. Biblioteka zdjęć: **PhotoKit**.
- **Zero zależności zewnętrznych.** Zapis ZIP jest własny (patrz §9).
- Trzy cele kompilacji:
  - `Odbitka` — aplikacja,
  - `OdbitkaShare` — rozszerzenie udostępniania,
  - `Packages/OdbitkaKit` — lokalny pakiet SPM z całym silnikiem i testami.
- Projekt Xcode generowany przez **XcodeGen** z `project.yml` (plik `.xcodeproj`
  jest artefaktem, nie źródłem).

## 2. Przepływ

```
1. Galeria          siatka biblioteki, filtr „tylko HEIC", zaznaczanie wielokrotne
                    pasek u dołu: „47 zdjęć · 182 MB"                      [Dalej]
2. Ustawienia       wszystkie opcje naraz, wartości z ostatniego użycia
                    szacunek „~14 MB"                                  [Przetwórz]
3. Postęp           „12 z 47", nazwa bieżącego pliku                      [Anuluj]
4. Wynik            „182 MB → 14,3 MB (−92%)" + miniatury
                    [Udostępnij] [Zapisz w Plikach] [Zapisz w Zdjęciach]
                    [Udostępnij porcjami] — gdy plików jest więcej niż 10
```

Aplikacja otwiera się **prosto na galerii**. Ekran powitalny pokazuje się wyłącznie
przy pierwszym uruchomieniu (§11).

## 3. Wejście — co wpuszczamy

- Widoczne są **wszystkie zdjęcia**: HEIC, JPEG, PNG, RAW/ProRAW, zrzuty ekranu, panoramy.
- **Wideo nie pojawia się w ogóle.** Aplikacja konwertuje zdjęcia; pokazanie filmu,
  którego nie umie przetworzyć, rodziłoby tylko pytanie „czemu się nie zmniejszył".
- **Live Photo** → sama klatka, część filmowa odrzucana.
- **Filtr „tylko HEIC"** jednym tapnięciem. `PHAsset` nie wystawia typu pliku wprost,
  więc formaty są indeksowane raz, w tle, z widocznym wskaźnikiem, i cache'owane na sesję.
- Bierzemy **wersję edytowaną** (zasób `fullSizePhoto`), a nie oryginał sprzed edycji —
  kto wyprostował horyzont, oczekuje wyprostowanego zdjęcia w paczce.

**Zdjęcia w iCloud.** Przy włączonej optymalizacji pamięci oryginały nie leżą na
urządzeniu. Odbitka je **pobiera** (`isNetworkAccessAllowed = true`) i to jest **jedyne
miejsce w całej aplikacji, które dotyka sieci**. Obietnica „wszystko lokalnie" pozostaje
prawdziwa: nic nie wychodzi na zewnątrz, zdjęcia wracają z konta użytkownika.

## 4. Formaty wyjściowe

**JPG** i **PNG**. Tylko te dwa.

PNG jest bezstratny, więc zdjęcie z aparatu potrafi w nim zająć kilka razy więcej niż
źródłowy HEIC — interfejs ostrzega o tym wprost przy wyborze PNG.

## 5. Rozmiar — trzy niezależne pokrętła

**Dłuższy bok**: 1280 / 1600 / 2048 / 2560 / Oryginał / Własna.
Nigdy nie powiększamy: wybranie 2560 px dla zdjęcia o boku 1200 px nie doda pikseli,
których nie ma.

**Jakość**: 30–100%, wyłącznie dla JPEG (PNG jest bezstratny — suwak znika).

**Limit „zmieść wszystko w X MB"**: aplikacja przetwarza naprawdę, mierzy wynik i jeśli
trzeba, powtarza przebieg z ostrzejszymi ustawieniami. Limit jest **gwarantowany, nie
szacowany**. Kolejność ustępstw: **najpierw jakość** (85% → 70% jest praktycznie
niewidoczne, a zbija rozmiar o jedną trzecią), **dopiero potem rozdzielczość**.
Dolne granice: jakość 35%, dłuższy bok 640 px, maksymalnie 4 przebiegi — po nich
czytelny błąd zamiast mielenia telefonu w nieskończoność.

W interfejsie nie pada sformułowanie „bez utraty jakości". Zmniejszenie rozdzielczości
to z definicji utrata informacji — takiej, której nie widać na typowym ekranie.

## 6. Kolory

iPhone fotografuje w **Display P3**. Programy ignorujące profil ICC — czyli większość
świata poza Apple — pokażą takie zdjęcie **przesycone**. To ten sam gatunek problemu
co HEIC: „u mnie wygląda dobrze, u odbiorcy nie".

Domyślnie konwertujemy do **sRGB**. Przełącznik „Zgodność kolorów" pozwala zachować
oryginalny profil.

## 7. Metadane

**Zasada nadrzędna: budujemy od zera.** Zaczynamy od pustego słownika i dokładamy
wyłącznie to, na co polityka użytkownika pozwala. Nigdy nie kopiujemy metadanych źródła
z wycinaniem wybranych pól — przy takim podejściu każdy klucz, o którym nie pomyśleliśmy
(Maker Notes, XMP, tagi trybu portretowego, cokolwiek dojdzie w przyszłym iOS),
przeciekłby do pliku wysłanego obcej osobie.

| Grupa | Domyślnie | Przełącznik |
|---|---|---|
| Lokalizacja (GPS) | **usuwana** | tak |
| Data i czas | zachowywana | tak |
| Aparat i parametry (marka, model, obiektyw, ISO, przysłona, czas, ogniskowa) | zachowywane | tak |
| Opisy IPTC, słowa kluczowe, autor, XMP, Apple Maker Notes | **zawsze usuwane** | nie |

Nie podlegają negocjacji, bo ich usunięcie psuje zdjęcie:
- **orientacja** — obrót jest wpalany w piksele, tag ustawiany na neutralny;
- **profil kolorów** — patrz §6.

**Data pliku** ustawiana z EXIF-a, żeby u odbiorcy pliki sortowały się chronologicznie.
Gdy użytkownik świadomie usuwa datę z metadanych, nie przywracamy jej tylnymi drzwiami.

## 8. Nazewnictwo

Jedno pole tekstowe i podgląd na żywo. Wpisujesz `Łazienka`, dostajesz
`Lazienka_001.jpg … Lazienka_047.jpg`.

- **Nazwa zawsze normalizowana**, bez przełącznika: polskie znaki i inne diakrytyki →
  ASCII, spacje i znaki specjalne → `_`, nadmiar podkreśleń sklejany, długość ≤ 60 znaków.
  Powód: archiwum ZIP nie ma zdefiniowanego kodowania nazw. Flagę UTF-8 ustawiamy, ale
  starszy Eksplorator Windows i część narzędzi korporacyjnych i tak zgadują stronę
  kodową — i `Łazienka` przyjeżdża jako krzaki. Taniej nie wysyłać ogonków, niż tłumaczyć
  odbiorcy, co się stało.
- **Kolejność numerowania: rosnąco wg daty zrobienia.** Nie wg kolejności zaznaczania
  (nikt nie pamięta, co tapnął pierwsze) i nie wg nazwy oryginalnej (`IMG_9998` wypadłoby
  po `IMG_10001`).
- **Liczba cyfr dobierana automatycznie** z liczby zdjęć, minimum trzy.
- **Puste pole = nazwy oryginalne**, zmieniane jest tylko rozszerzenie. Powtórzenia
  rozstrzygane przyrostkiem `_2`, `_3`.

## 9. Pakowanie

**ZIP, metodą STORE (bez kompresji).** JPEG i PNG są już skompresowane — deflate daje
na nich 0–2% przy kilkukrotnie dłuższym czasie. Wartością ZIP-a jest **zwinięcie
czterdziestu siedmiu plików w jeden**, nie zmniejszenie; interfejs mówi „Spakuj do
jednego pliku ZIP", nigdy „Kompresuj".

**Podział na części** o zadanym limicie (domyślnie 25 MB, czyli limit załączników
Gmaila): `Lazienka_cz1.zip`, `Lazienka_cz2.zip`. Kolejność zachowana — część pierwsza
zawiera początek, nie losowy podzbiór. Plik większy od limitu części kończy się jasnym
błędem, a nie cichym przekroczeniem limitu.

Zapis jest strumieniowy i obsługuje ZIP64 (archiwa > 4 GB, > 65 535 wpisów).

**RAR jest niemożliwy i nie jest to kwestia nakładu pracy.** Format jest własnościowy;
publicznie dostępny jest wyłącznie dekoder, którego licencja wprost zakazuje użycia
do zbudowania kompresora. Nie istnieje żadna legalna biblioteka tworząca archiwa RAR.

## 10. Udostępnianie

**Reguła nienegocjowalna: przekazujemy `URL`-e plików z dysku, nigdy `UIImage`.**
Aplikacja, która dostaje obiekt obrazu, ma prawo osadzić go w treści wiadomości
i przekodować po swojemu. Plik na dysku Gmail dokłada jako **załącznik** — i to jedyna
dźwignia, jaką nad tym mamy.

Trzy drogi z ekranu wyniku:
- **Udostępnij** — systemowy arkusz (Gmail, Signal, WhatsApp, AirDrop…).
- **Zapisz w Plikach** — `UIDocumentPickerViewController(forExporting:)`, a przez niego
  Dysk Google, iCloud Drive, OneDrive, Dropbox. Krótsza droga „na dysk" niż przez arkusz.
- **Zapisz w Zdjęciach** — uprawnienie `addOnly`, pytane dopiero przy pierwszym użyciu
  tego przycisku.

**Limit 10 zdjęć.** Signal i Viber przyjmują naraz najwyżej dziesięć elementów.
Nie da się tego wykryć: nie wiemy, którą aplikację użytkownik wybierze, a
`completionHandler` arkusza mówi tylko tyle, że arkusz się zamknął — nie że wiadomość
poszła. Dlatego porcjami **steruje użytkownik**: ekran z listą porcji (po 5/10/20),
każda wysyłana tapnięciem, wysłane odhaczane. Automatyczny łańcuch wyskakujących arkuszy
wyglądałby sprawniej dokładnie do pierwszego anulowania.

**Świadomie nie robimy** integracji z Gmail API ani Google Drive API. Wymagałoby to
OAuth, konta Google w aplikacji, ruchu sieciowego ze zdjęciami i deklaracji w privacy
labels, że aplikacja wysyła dane — czyli zaprzeczenia głównej obietnicy produktu.

## 11. Uprawnienia i pierwsze uruchomienie

Systemowy prompt pojawia się **raz w życiu aplikacji**, a po odmowie użytkownik może ją
odblokować wyłącznie w Ustawieniach systemu. Dlatego:

1. Pierwszy start → **ekran powitalny**: co aplikacja robi i zdanie „Wszystko dzieje się
   na Twoim telefonie. Nie mamy serwera."
2. Tapnięcie „Wybierz zdjęcia" → dopiero teraz systemowy prompt.
3. Przed tym momentem aplikacja **nie dotyka biblioteki zdjęć w żaden sposób** — nawet
   nie pyta o status uprawnień ani nie rejestruje obserwatora zmian, bo samo sięgnięcie
   po `PHPhotoLibrary` potrafi prompt wywołać.

**Dostęp ograniczony** (użytkownik wskazuje konkretne zdjęcia) jest obsłużony
pełnoprawnie: galeria pokazuje wybrane zdjęcia plus stały pasek „Wybierz więcej".
To nie jest błąd — to wybór, który system aktywnie promuje.

## 12. Szacowanie rozmiaru

Na ekranie ustawień widoczne jest `~14 MB`, liczone z 3 zdjęć wybranych **równomiernie**
po całym zaznaczeniu (nie pierwszych trzech), odświeżane z opóźnieniem 400 ms.

Tylda i podpis są celowe: rozmiar JPEG zależy przede wszystkim od treści zdjęcia —
gładka ściana zejdzie do 200 kB, liście przy tych samych ustawieniach dadzą 1,8 MB.
Ekstrapolujemy po **liczbie pikseli wyjściowych**, którą znamy dokładnie, a nie po
rozmiarze plików źródłowych, który mieszałby ze sobą HEIC, JPEG, PNG i RAW.

Tryb „zmieść w X MB" **nie opiera się na tym szacunku** (§5).

## 13. Kontrakt przetwarzania

**Wszystko albo nic.** Pierwszy błąd przerywa przebieg, a wyniki częściowe są kasowane —
żeby nie dało się przypadkiem wysłać niekompletnej paczki. Anulowanie działa tak samo.

Żeby ta semantyka nie była okrutna, przed pierwszym kodowaniem działa **kontrola
wstępna**: dostępność zasobów (czy trzeba je ciągnąć z iCloud i czy jest sieć) oraz
wolne miejsce. Typowa porażka następuje w **pierwszej sekundzie z konkretnym
komunikatem**, a nie w dziesiątej minucie.

**Pamięć.** Skalowanie idzie przez `CGImageSourceCreateThumbnailAtIndex`, nie przez
wczytanie pełnego obrazu — zdjęcie 48 Mpx nigdy nie materializuje się jako ~190 MB
bitmapy. Każde zdjęcie w `autoreleasepool`, równoległość ograniczona do 2 zadań
(1 w rozszerzeniu).

**Miejsce na dysku.** Oryginały ściągane i kasowane po jednym, więc szczyt zapotrzebowania
to największy pojedynczy plik źródłowy plus komplet wyników (plus druga kopia, gdy
włączony ZIP). Wyjątkiem jest tryb budżetowy, który może potrzebować powtórki i dlatego
trzyma oryginały.

**Tło.** iOS daje aplikacji w tle około 30 sekund — przy 200 zdjęciach to nie wystarczy.
Nie obiecujemy przetwarzania w tle; ekran nie gaśnie w trakcie pracy.

## 14. Pliki robocze

Wszystko w `tmp/Odbitka/<sesja>/`, nie w `Documents/`: system może to posprzątać sam przy
niedoborze miejsca, a przetworzone duplikaty nie zżerają kopii zapasowej iCloud.

Pliki żyją do końca sesji — tyle, żeby dało się wrócić na ekran wyniku, dokończyć wysyłkę
porcjami albo zapisać do Plików. Sprzątanie przy następnym uruchomieniu, cicho i bez
pytania, plus przycisk „Wyczyść teraz" w ustawieniach aplikacji z pokazanym zajętym
miejscem.

## 15. Rozszerzenie udostępniania

Zdjęcia → Udostępnij → Odbitka.

- **Do 20 zdjęć** rozszerzenie robi wszystko na miejscu: ustawienia, przetwarzanie
  szeregowe, arkusz udostępniania. Użytkownik nie opuszcza Zdjęć.
- **Powyżej progu** kopiuje pliki do kontenera App Group (`group.pl.froncek.odbitka`),
  zapisuje manifest i otwiera aplikację przez `odbitka://handoff?session=…`.

Powód podziału: rozszerzenia dostają rzędu 120 MB pamięci wobec ponad 1 GB dla
aplikacji. Ubite rozszerzenie wygląda dla użytkownika jak zniknięcie okienka bez słowa.

Ustawienia są współdzielone (`UserDefaults` grupy aplikacji), więc przetwarzanie
z poziomu Zdjęć nie zaczyna się od wartości fabrycznych.

## 16. Stan trwały

Jeden wpis w `UserDefaults`: ostatnio użyte ustawienia. To wszystko.

**Nie ma presetów** ani ich zarządzania — ekran ustawień pokazuje wszystkie opcje naraz,
a domyślne wartości to te z poprzedniego użycia. **Prefiks nazwy nie przeżywa
uruchomienia**: opisuje konkretną paczkę, nie sposób przetwarzania, a podpisanie zdjęć
kuchni nazwą `Lazienka` zauważa się dopiero u odbiorcy.

## 17. Języki

Polski (źródłowy) i angielski, `Localizable.xcstrings`, klucze jawne (`library.title`),
nie zdania użyte jako klucze — poprawka literówki po polsku nie może cicho rozwalić
angielskiego tłumaczenia.

## 18. Testy

Testowany jest **wyłącznie pakiet silnika** (`swift-testing`, uruchamiane na macOS bez
symulatora). Zero testów interfejsu, zero CI.

Kryterium doboru: testujemy to, czego **nie widać na ekranie**.
- **Usuwanie GPS** — na prawdziwym pliku ze współrzędnymi, z asercją, że po konwersji
  ich nie ma. Błąd tutaj jest niewidoczny: zdjęcie wygląda tak samo, paczka waży tyle
  samo, aplikacja nic nie zgłasza — a użytkownik wysyła obcej osobie adres mieszkania.
- Nazewnictwo, numeracja, normalizacja znaków, kolizje nazw.
- Poprawność archiwum ZIP — weryfikowana **systemowym `unzip`**, nie własnym czytnikiem.
- Arytmetyka podziału na części, zbieżność doboru jakości.
- Semantyka wszystko-albo-nic i kontrola wstępna.

## 19. Dystrybucja

TestFlight, docelowo App Store. Darmowa, bez reklam, bez zakupów w aplikacji, bez konta.
`PrivacyInfo.xcprivacy` deklaruje zero zbieranych danych i zero śledzenia.

## 20. Poza zakresem (świadomie)

- **RAR** — niemożliwy prawnie i technicznie (§9). Nie „na później", tylko nigdy.
- **HEIC → HEIC** (sam resize i czyszczenie metadanych, bez konwersji) — kosztowałby
  zero, bo to ta sama ścieżka `ImageIO`. Odrzucony razem z decyzją o dwóch formatach.
- **PDF wielostronicowy** — rozwiązywałby naraz limit 10 zdjęć, gwarancję załącznika
  w Gmailu i wygodę odbiorcy (jedno tapnięcie zamiast rozpakowywania ZIP-a). Najmocniejszy
  kandydat do v2.
- **WebP i AVIF** — `ImageIO` na iOS nie daje pewnego enkodera, a odbiorcy (Windows,
  starsze Androidy, Outlook) mają z nimi ten sam problem, który aplikacja ma leczyć.
- **Wideo** — inna ścieżka eksportu, inne nazewnictwo, brak zmniejszania.
- **Projekty i zlecenia** (nazwa klienta, sesje po dacie, historia wysyłek) — wymagałyby
  trwałej bazy i migracji. Prefiks nazwy pokrywa większość tej potrzeby.
- **Presety** — wycięte świadomie na rzecz „wszystko widoczne, wartości z ostatniego użycia".
- **Integracje Gmail / Google Drive przez API** — złamałyby obietnicę lokalności (§10).
- **Edycja zdjęć** (kadrowanie, obrót, filtry, znak wodny) — to inna aplikacja.
