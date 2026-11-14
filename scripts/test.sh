#!/usr/bin/env bash
# Baut den Kern (Swift-Paket HubiplanKern) und führt seine Tests lokal aus
# (Linux oder WSL mit dem Swift-Werkzeug, oder macOS).
#
#   scripts/test.sh [Argumente für „swift test“ …]
#
# Regeln: nur lokal testen. Das Skript holt sich einen lokalen Testplatz mit testplatz (aus
# hubiplan/scripts/testplatz.sh, siehe hubiplan/docs/testserver.md); Swift bekommt so viele
# Aufträge wie der Platz Kerne.
set -euo pipefail

if [ -z "${TESTPLATZ:-}" ]; then
    if ! command -v testplatz > /dev/null; then
        echo "Abbruch: testplatz fehlt (siehe README.md, „Bauen und testen“)." >&2
        exit 2
    fi
    exec testplatz "$0" "$@"
fi

cd "$(dirname "$0")/.."
if ! command -v swift > /dev/null; then
    echo "Abbruch: swift fehlt (Swift-Werkzeug ab 5.9, siehe README.md)." >&2
    exit 2
fi
# Zwischenstände ins lokal eingestellte Temp-Verzeichnis, nicht ins Repo
SCRATCH="${TESTPLATZ_TMP:-${TMPDIR:-/tmp}}/hubiplan-ios-build"
mkdir -p "$SCRATCH"
swift test --scratch-path "$SCRATCH" --jobs "${TEST_KERNE:-2}" "$@"
echo "OK: $(git rev-parse --short HEAD) gebaut und getestet."
