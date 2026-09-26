#!/usr/bin/env bash
# Usuwa z cache'u Xcode profile provisioningu dotyczące Pixporta.
#
# Potrzebne, gdy zmienią się uprawnienia (np. identyfikator grupy aplikacji):
# Xcode chętnie sięgnie po istniejący profil zamiast poprosić Apple o nowy,
# a wtedy podpisana aplikacja prosi o coś, czego profil nie autoryzuje.
# Kasowanie jest bezpieczne — przy najbliższym budowaniu z -allowProvisioningUpdates
# profile pobiorą się na nowo.
set -euo pipefail

DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
removed=0

for profile in "$DIR"/*.mobileprovision; do
  [ -e "$profile" ] || continue
  if security cms -D -i "$profile" 2>/dev/null | grep -q "pl\.froncek\.pixport"; then
    name=$(security cms -D -i "$profile" 2>/dev/null | plutil -p - | awk -F'"' '/"Name"/{print $4}')
    rm -f "$profile"
    echo "usunięto: $name"
    removed=$((removed + 1))
  fi
done

echo "$removed profil(e) usunięte — najbliższy build pobierze świeże."
