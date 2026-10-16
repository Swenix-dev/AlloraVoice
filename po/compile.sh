#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SeaQ
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Compiles po/<lang>.po → package/contents/locale/<lang>/LC_MESSAGES/plasma_applet_org.seaq.alloravoice.mo
# Plasma loads these automatically and uses the language chosen in System Settings → Region & Language.
set -euo pipefail
cd "$(dirname "$0")/.."
DOMAIN="plasma_applet_org.seaq.alloravoice"
for po in po/*.po; do
    lang=$(basename "$po" .po)
    mkdir -p "package/contents/locale/$lang/LC_MESSAGES"
    msgfmt --check -o "package/contents/locale/$lang/LC_MESSAGES/$DOMAIN.mo" "$po"
    echo "✔ $lang"
done
