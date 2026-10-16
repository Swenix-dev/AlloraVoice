#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SeaQ
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Updates the translation template (po/alloravoice.pot) and merges new strings into every po/<lang>.po.
# Needs gettext (xgettext, msgmerge).
set -euo pipefail
cd "$(dirname "$0")/.."
xgettext --from-code=UTF-8 -C -kde -ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 \
    --package-name=AlloraVoice --msgid-bugs-address="" \
    -o po/alloravoice.pot $(find package/contents/ui -name '*.qml' -o -name '*.js' | sort)
for po in po/*.po; do
    msgmerge --quiet --update --backup=none "$po" po/alloravoice.pot
    echo "✔ $po"
done
