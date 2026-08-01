#!/usr/bin/env bash
# Esegue TUTTE le verifiche del progetto in un comando solo.
#
#   ./tools/check_all.sh
#
# 1. Invarianti di design del bilanciamento (Python)
# 2. Validita' sintattica dei JSON
# 3. Self test dell'engine: i dati caricati da Godot devono produrre gli stessi
#    numeri del simulatore, e il tick loop deve girare alla frequenza dichiarata
#
# Esce con codice 1 se una qualunque verifica fallisce: usabile in un hook di
# pre-commit o in CI.
#
# Il binario di Godot si cerca in $GODOT, poi nel PATH. Se non c'e', il passo 3
# viene saltato con un avviso (i primi due girano comunque).

set -uo pipefail
cd "$(dirname "$0")/.."

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
FAILURES=0

step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$OFF"; }
ok()   { printf '%s    OK%s  %s\n' "$GREEN" "$OFF" "$1"; }
bad()  { printf '%s    FAIL%s  %s\n' "$RED" "$OFF" "$1"; FAILURES=$((FAILURES+1)); }
warn() { printf '%s    SKIP%s  %s\n' "$YELLOW" "$OFF" "$1"; }

# ---------------------------------------------------------------- 1. design --
step "1/3  Invarianti di design del bilanciamento"
if python3 tools/balance_sim.py --check > /tmp/_bal.log 2>&1; then
    ok "$(grep -c '\[OK\]' /tmp/_bal.log) controlli superati (17 invarianti)"
else
    bad "invarianti violate:"
    grep -A20 'INVARIANTI VIOLATE' /tmp/_bal.log || cat /tmp/_bal.log
fi

# ------------------------------------------------------------------ 2. JSON --
step "2/3  Validita' dei file di dati"
for f in data/*.json; do
    if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
        ok "$f"
    else
        bad "$f non e' JSON valido"
    fi
done

# ---------------------------------------------------------------- 3. engine --
step "3/3  Self test dell'engine (Godot headless)"
GODOT_BIN="${GODOT:-}"
if [ -z "$GODOT_BIN" ]; then
    for c in godot godot4 Godot; do
        if command -v "$c" > /dev/null 2>&1; then GODOT_BIN="$c"; break; fi
    done
fi

if [ -z "$GODOT_BIN" ]; then
    warn "Godot non trovato. Imposta \$GODOT o mettilo nel PATH."
    warn "  export GODOT=/percorso/Godot_v4.4.1-stable_linux.x86_64"
elif ! "$GODOT_BIN" --headless --version > /dev/null 2>&1; then
    bad "'$GODOT_BIN' non e' un binario Godot funzionante"
else
    if "$GODOT_BIN" --headless --path . -- --selftest > /tmp/_godot.log 2>&1; then
        grep -E '^(OK|FAIL)' /tmp/_godot.log | sed 's/^/    /'
        ok "engine allineato al simulatore"
    else
        bad "self test dell'engine fallito:"
        grep -E '^(FAIL|ERROR)' /tmp/_godot.log | sed 's/^/    /'
    fi
fi

# ------------------------------------------------------------------ verdetto --
printf '\n'
if [ "$FAILURES" -eq 0 ]; then
    printf '%s%s  TUTTO VERDE  %s\n\n' "$BOLD$GREEN" "" "$OFF"
    exit 0
fi
printf '%s%s  %d VERIFICHE FALLITE  %s\n\n' "$BOLD$RED" "" "$FAILURES" "$OFF"
exit 1
