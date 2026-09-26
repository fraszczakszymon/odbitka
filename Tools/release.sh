#!/usr/bin/env bash
# Buduje paczkę .ipa gotową do wysłania na TestFlight.
#
#   ./Tools/release.sh            # archiwum + eksport .ipa
#   ./Tools/release.sh --upload   # dodatkowo wysyłka do App Store Connect
#   ./Tools/release.sh --check-only   # sama kontrola wstępna, nic nie buduje
#   ./Tools/release.sh --skip-tests
#
# Numer builda to LICZBA COMMITÓW. Zawsze rośnie, nigdy się nie powtarza i da się
# z niego odtworzyć dokładny stan kodu. App Store Connect odrzuca powtórzony numer,
# a ręczne zwiększanie prędzej czy później się zapomni.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="Pixport"
PROJECT="Pixport.xcodeproj"
APP_ICON="Pixport/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
INFO_PLIST="Pixport/Info.plist"

UPLOAD=0
RUN_TESTS=1
CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --upload) UPLOAD=1 ;;
    --skip-tests) RUN_TESTS=0 ;;
    --check-only) CHECK_ONLY=1 ;;
    *) echo "nieznany przełącznik: $arg"; exit 1 ;;
  esac
done

# Wartości z project.yml — pole bywa w cudzysłowie albo bez, więc zdejmujemy oba.
read_setting() {
  grep -E "^ *$1:" project.yml | head -1 | sed -E "s/^ *$1: *//; s/^\"(.*)\"$/\1/"
}

TEAM=$(read_setting DEVELOPMENT_TEAM)
VERSION=$(read_setting MARKETING_VERSION)
BUILD=$(git rev-list --count HEAD)

if [ -z "$TEAM" ]; then
  cat <<'MSG'
Brakuje identyfikatora zespołu.

  1. developer.apple.com → Account → Membership details → Team ID
  2. wpisz go w project.yml w polu DEVELOPMENT_TEAM
  3. uruchom ponownie
MSG
  exit 1
fi

echo "→ Pixport $VERSION ($BUILD), zespół $TEAM"

# ---------------------------------------------------------------- kontrola wstępna
#
# Każda z tych reguł odpowiada realnemu błędowi, którym App Store odbija paczkę.
# Sprawdzenie ich tutaj kosztuje sekundę; dowiedzenie się o nich od Apple kosztuje
# pełny cykl archiwum, eksportu, wysyłki i czekania na walidację.

fail=0
check() {
  if [ "$1" = "ok" ]; then
    printf '   ✓ %s\n' "$2"
  else
    printf '   ✗ %s\n     %s\n' "$2" "$3"
    fail=1
  fi
}

echo "→ kontrola wstępna"

# 90717: ikona nie może mieć kanału alfa.
if [ "$(sips -g hasAlpha "$APP_ICON" 2>/dev/null | awk '/hasAlpha/{print $2}')" = "no" ]; then
  check ok "ikona bez kanału alfa"
else
  check bad "ikona bez kanału alfa" "przegeneruj: swift Tools/make-icon.swift $APP_ICON  (błąd App Store 90717)"
fi

# Deklaracja eksportowa. Bez niej App Store Connect pyta o zgodność przy KAŻDYM buildzie.
if plutil -extract ITSAppUsesNonExemptEncryption raw "$INFO_PLIST" >/dev/null 2>&1; then
  check ok "zadeklarowana zgodność eksportowa"
else
  check bad "zadeklarowana zgodność eksportowa" "dodaj ITSAppUsesNonExemptEncryption do $INFO_PLIST"
fi

# 90474: rodzina "1,2" wymaga wszystkich czterech orientacji na iPadzie.
FAMILY=$(read_setting TARGETED_DEVICE_FAMILY)
if [ "$FAMILY" = "1" ] || plutil -extract 'UISupportedInterfaceOrientations~ipad' raw "$INFO_PLIST" >/dev/null 2>&1; then
  check ok "rodzina urządzeń zgodna z orientacjami"
else
  check bad "rodzina urządzeń zgodna z orientacjami" \
    "rodzina $FAMILY obejmuje iPada, więc potrzeba UISupportedInterfaceOrientations~ipad z czterema orientacjami (błąd 90474)"
fi

# Grupa aplikacji z uprawnień musi zgadzać się z tą, o którą prosi kod. Niezgodność
# jest niewidoczna dla kompilatora i objawia się dopiero na urządzeniu: containerURL
# zwraca nil, przekazywanie zdjęć z rozszerzenia przestaje działać, a ustawienia
# cichutko rozjeżdżają się między aplikacją a rozszerzeniem.
CODE_GROUP=$(grep -E 'appGroupID *= *"' Packages/PixportKit/Sources/PixportKit/Handoff/Handoff.swift | sed -E 's/.*"(.*)".*/\1/')
# PlistBuddy, nie plutil: plutil traktuje kropki jako separator ścieżki, a sam klucz
# „com.apple.security.application-groups" jest ich pełen.
read_group() {
  /usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" "$1" 2>/dev/null || echo ""
}
APP_GROUP=$(read_group Pixport/Pixport.entitlements)
EXT_GROUP=$(read_group PixportShare/PixportShare.entitlements)
if [ -n "$CODE_GROUP" ] && [ "$CODE_GROUP" = "$APP_GROUP" ] && [ "$CODE_GROUP" = "$EXT_GROUP" ]; then
  check ok "grupa aplikacji spójna z kodem ($CODE_GROUP)"
else
  check bad "grupa aplikacji spójna z kodem" "kod: $CODE_GROUP, aplikacja: $APP_GROUP, rozszerzenie: $EXT_GROUP"
fi

# Wersja i numer builda rozszerzenia muszą zgadzać się z aplikacją — rozjazd odbija paczkę.
app_ver=$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")
ext_ver=$(plutil -extract CFBundleShortVersionString raw PixportShare/Info.plist)
app_bld=$(plutil -extract CFBundleVersion raw "$INFO_PLIST")
ext_bld=$(plutil -extract CFBundleVersion raw PixportShare/Info.plist)
if [ "$app_ver" = "$ext_ver" ] && [ "$app_bld" = "$ext_bld" ]; then
  check ok "wersja rozszerzenia zgodna z aplikacją"
else
  check bad "wersja rozszerzenia zgodna z aplikacją" "aplikacja $app_ver/$app_bld, rozszerzenie $ext_ver/$ext_bld"
fi

[ "$fail" = "0" ] || { echo; echo "Kontrola wstępna nie przeszła — nic nie budowałem."; exit 1; }

# Wyjście przed archiwum. Przydatne, bo archiwum i eksport ruszają certyfikaty
# dystrybucyjne na koncie Apple, a sama kontrola niczego nie dotyka.
[ "$CHECK_ONLY" = "0" ] || { echo; echo "Kontrola wstępna przeszła. Bez --check-only poszłoby archiwum."; exit 0; }

if [ -n "$(git status --porcelain)" ]; then
  echo "   ! w drzewie są niezacommitowane zmiany — numer builda ($BUILD) ich nie obejmie"
fi

# ------------------------------------------------------------------------- testy
if [ "$RUN_TESTS" = "1" ]; then
  echo "→ testy silnika"
  swift test --package-path Packages/PixportKit 2>&1 | tail -1
fi

xcodegen generate >/dev/null

# ----------------------------------------------------------------------- archiwum
OUT="build/Pixport-$VERSION-$BUILD"
rm -rf "$OUT"; mkdir -p "$OUT"

# `-allowProvisioningUpdates` jest konieczne przy pierwszym wydaniu na koncie:
# certyfikat dystrybucyjny i profile App Store jeszcze nie istnieją, a bez tej flagi
# xcodebuild nie ma prawa ich założyć. Przy EKSPORCIE tak samo — profil dystrybucyjny
# powstaje dopiero tam, więc brak flagi kończy się „No profiles for <bundle id> were found”,
# mimo że archiwum przeszło bez szemrania.
echo "→ archiwum"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "generic/platform=iOS" -configuration Release \
  -archivePath "$OUT/$SCHEME.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  -allowProvisioningUpdates \
  archive 2>&1 | grep -E "error:|ARCHIVE" || true

[ -d "$OUT/$SCHEME.xcarchive" ] || { echo "archiwum nie powstało"; exit 1; }

echo "→ eksport"
xcodebuild -exportArchive \
  -archivePath "$OUT/$SCHEME.xcarchive" \
  -exportOptionsPlist Tools/ExportOptions.plist \
  -allowProvisioningUpdates \
  -exportPath "$OUT" 2>&1 | grep -E "error:|EXPORT" || true

IPA=$(find "$OUT" -name "*.ipa" | head -1)
[ -n "$IPA" ] || { echo "nie powstała paczka .ipa"; exit 1; }

echo "→ gotowe: $IPA ($(du -h "$IPA" | cut -f1))"

if [ "$UPLOAD" = "1" ]; then
  : "${ASC_KEY_ID:?ustaw ASC_KEY_ID, ASC_ISSUER_ID i połóż klucz w ~/.appstoreconnect/private_keys/}"
  : "${ASC_ISSUER_ID:?ustaw ASC_ISSUER_ID}"
  echo "→ wysyłka do App Store Connect"
  xcrun altool --upload-app --type ios --file "$IPA" \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "→ wysłane. Przetwarzanie trwa kilka–kilkanaście minut,"
  echo "  potem build pojawi się w App Store Connect → TestFlight → Builds."
else
  echo
  echo "Wysyłka: ./Tools/release.sh --upload"
  echo "     lub przeciągnij paczkę do aplikacji Transporter."
fi
