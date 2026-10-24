#!/bin/bash
# Télécharge VLCKit 3.7.4 (MobileVLCKit pour iPhone/iPad, TVVLCKit pour Apple TV) dans Frameworks/.
# Les fichiers (plusieurs centaines de Mo) ne sont pas dans le dépôt : ce script les récupère (GitHub le lance à chaque build).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Frameworks
fetch() {  # nom url sha256
  local name=$1 url=$2 sum=$3
  if [ -d "Frameworks/$name.xcframework" ]; then echo "${name} déjà présent"; return; fi
  local tmp; tmp=$(mktemp -d)
  echo "Téléchargement de ${name}…"
  curl -fsSL -o "$tmp/a.tar.xz" "$url"
  echo "$sum  $tmp/a.tar.xz" | shasum -a 256 -c -
  tar xf "$tmp/a.tar.xz" -C "$tmp"
  local fw; fw=$(find "$tmp" -maxdepth 3 -name "$name.xcframework" | head -1)
  # symboles de débogage inutiles ici (des centaines de Mo) : dossiers vidés, mais gardés car Xcode les exige
  find "$fw" -name dSYMs -type d -prune | while read -r d; do rm -rf "$d"; mkdir -p "$d"; done
  # appareil : on ne garde que arm64 (les anciens armv7 alourdissent l'appli pour rien)
  for d in "$fw"/ios-arm64_armv7_armv7s "$fw"/tvos-arm64; do
    [ -d "$d" ] || continue
    local bin="$d/$name.framework/$name"
    if lipo -archs "$bin" | grep armv7 >/dev/null; then lipo -thin arm64 "$bin" -output "$bin.arm64" && mv "$bin.arm64" "$bin"; fi
  done
  # Info.plist de l'xcframework : ne déclarer que les architectures restantes
  python3 - "$fw/Info.plist" <<'PY'
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, "rb"))
for lib in d["AvailableLibraries"]:
    if lib.get("SupportedPlatformVariant") != "simulator":
        lib["SupportedArchitectures"] = ["arm64"]
plistlib.dump(d, open(p, "wb"))
PY
  mv "$fw" "Frameworks/$name.xcframework"
  rm -rf "$tmp"
  du -sh "Frameworks/$name.xcframework"
}
fetch MobileVLCKit https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-3.0-20260922-1512.tar.xz c649c4c47bd065b3a5511746361b5a9066a34033f2df9cbc9454409c0f363b52
fetch TVVLCKit https://download.videolan.org/cocoapods/prod/TVVLCKit-3.0-20260930-0854.tar.xz 07892cae8e59e95a23f1fcf11692f802eae106312aa5ad9782faa2556b2d65d5
