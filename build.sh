#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SeaQ
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Baut das installierbare Widget-Paket  →  dist/alloravoice-<version>.plasmoid
# Builds the installable widget package →  dist/alloravoice-<version>.plasmoid
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(python3 -c "import json;print(json.load(open('package/metadata.json'))['KPlugin']['Version'])")
OUT="dist/alloravoice-${VERSION}.plasmoid"

# Übersetzungen kompilieren (falls gettext installiert ist – sonst die mitgelieferten .mo-Dateien nutzen)
if command -v msgfmt >/dev/null; then ./po/compile.sh >/dev/null; fi

mkdir -p dist
rm -f "$OUT"
find package -name "__pycache__" -type d -prune -exec rm -rf {} +
chmod +x package/contents/backend/*.sh
(cd package && zip -qr "../$OUT" metadata.json contents)

echo "✔ $OUT"
echo
echo "Installieren / Install:"
echo "  kpackagetool6 -t Plasma/Applet -i $OUT     # erstmalig / first time"
echo "  kpackagetool6 -t Plasma/Applet -u $OUT     # Update"
