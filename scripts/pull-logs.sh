#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Tinta contributors
# Traz do Kindle o crash.log do KOReader, o log de bateria e o banco da Tinta (spec 15.4), para
# kindle-logs/<data-hora>/ (ignorada pelo git: o banco tem as configurações das apps, inclusive tokens).
#
#   scripts/pull-logs.sh --ssh IP [--out PASTA] [--dry-run]
#   scripts/pull-logs.sh --usb [PONTO_DE_MONTAGEM] [--out PASTA] [--dry-run]     (padrão /Volumes/Kindle)
#
# SSH: porta 2222, root, senha vazia (aperte Enter se pedir); só responde com o Wi-Fi ligado e o aparelho
# acordado. Não mostra o conteúdo de nada: só lista o que trouxe.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_IP=""
USB=""
OUT=""
DRY=0
SSH_PORT="${KINDLE_SSH_PORT:-2222}"
KINDLE_KOREADER="${KINDLE_KOREADER:-/mnt/us/koreader}"
# relativos à pasta do KOReader
FILES=(crash.log tinta-battery.csv tinta.sqlite3 tinta.sqlite3-wal tinta.sqlite3-shm)

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --ssh) [ $# -ge 2 ] || { echo "ERRO: --ssh precisa do IP do Kindle." >&2; exit 2; }; SSH_IP="$2"; shift 2 ;;
        --usb) USB="/Volumes/Kindle"; shift; if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then USB="$1"; shift; fi ;;
        --out) [ $# -ge 2 ] || { echo "ERRO: --out precisa de uma pasta." >&2; exit 2; }; OUT="$2"; shift 2 ;;
        --dry-run|-n) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERRO: argumento desconhecido '$1'." >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$SSH_IP" ] && [ -z "$USB" ]; then usage >&2; exit 2; fi
if [ -n "$SSH_IP" ]; then
    case "$SSH_IP" in *[!0-9A-Za-z.:-]*) echo "ERRO: endereço inválido '$SSH_IP'." >&2; exit 2 ;; esac
fi
OUT="${OUT:-$ROOT/kindle-logs/$(date +%Y%m%d-%H%M%S)}"

if [ -n "$USB" ]; then
    SRC="$USB/koreader"
    if [ "$DRY" = 1 ]; then
        echo "[dry-run] USB: de $SRC para $OUT:"
        printf '  %s\n' "${FILES[@]}"
        exit 0
    fi
    [ -d "$SRC" ] || { echo "ERRO: '$SRC' não existe (Kindle montado?)." >&2; exit 1; }
    mkdir -p "$OUT"
    for f in "${FILES[@]}"; do [ -f "$SRC/$f" ] && cp -p "$SRC/$f" "$OUT/"; done
else
    REMOTE_CMD="cd '$KINDLE_KOREADER' && set -- && for f in ${FILES[*]}; do [ -f \"\$f\" ] && set -- \"\$@\" \"\$f\"; done; [ \$# -gt 0 ] && tar cf - \"\$@\""
    SSH_OPTS=(-p "$SSH_PORT" -o PubkeyAuthentication=no -o ConnectTimeout=10)
    if [ "$DRY" = 1 ]; then
        echo "[dry-run] SSH: de root@$SSH_IP:$KINDLE_KOREADER para $OUT:"
        printf '  %s\n' "${FILES[@]}"
        echo "[dry-run] ssh ${SSH_OPTS[*]} root@$SSH_IP \"$REMOTE_CMD\" | tar xf - -C \"$OUT\""
        exit 0
    fi
    mkdir -p "$OUT"
    ssh "${SSH_OPTS[@]}" "root@$SSH_IP" "$REMOTE_CMD" | tar xf - -C "$OUT"
fi

echo "Trazido para $OUT:"
(cd "$OUT" && ls -l | sed 1d)
