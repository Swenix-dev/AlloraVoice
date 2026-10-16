#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SeaQ
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Liest die Farben des aktiven KDE-Farbschemas (Systemeinstellungen → Farben) aus kdeglobals.
# Ausgabe: key=r,g,b  – fehlende Werte bleiben leer (das Widget nimmt dann Standardfarben).
K=$(command -v kreadconfig6 || command -v kreadconfig5)
[ -z "$K" ] && exit 0
r() { "$K" --file kdeglobals --group "$1" --key "$2" 2>/dev/null; }

echo "win=$(r Colors:Window BackgroundNormal)"
echo "winAlt=$(r Colors:Window BackgroundAlternate)"
echo "winText=$(r Colors:Window ForegroundNormal)"
echo "winInactive=$(r Colors:Window ForegroundInactive)"
echo "view=$(r Colors:View BackgroundNormal)"
echo "viewText=$(r Colors:View ForegroundNormal)"
echo "button=$(r Colors:Button BackgroundNormal)"
echo "buttonText=$(r Colors:Button ForegroundNormal)"
echo "selection=$(r Colors:Selection BackgroundNormal)"
echo "selectionText=$(r Colors:Selection ForegroundNormal)"
echo "accent=$(r General AccentColor)"
echo "link=$(r Colors:View ForegroundLink)"
echo "positive=$(r Colors:Window ForegroundPositive)"
echo "neutral=$(r Colors:Window ForegroundNeutral)"
echo "negative=$(r Colors:Window ForegroundNegative)"
