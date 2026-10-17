#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Tinta contributors
# Copia um plugin do repositório para o Kindle (spec 15.4), sem tests/ e sem arquivos ocultos.
#
#   scripts/deploy.sh [opções] [PONTO_DE_MONTAGEM]
#
#   (sem --ssh)         USB: rsync para <montagem>/koreader/plugins/<plugin>.koplugin (padrão /Volumes/Kindle)
#   --ssh IP            SSH do KOReader (porta 2222, root, senha vazia): tar sobre ssh, porque o Kindle não tem
#                       rsync. Copia para uma pasta nova e troca no fim, para não deixar meio plugin.
#   --plugin NOME       tinta (padrão); aceita também "tinta.koplugin"
#   --app PASTA         copia só uma pasta de app (com init.lua) para koreader/tinta-apps/<id>/, fora do plugin:
#                       sobrevive a atualizações do plugin. Ex.: scripts/deploy.sh --app caminho/minha_app --ssh IP
#                       (USB e --ssh; o id é o nome da pasta). Não mexe no plugin.
#   --dry-run           mostra o que seria copiado e os comandos, sem copiar nada
#
# Depois: USB -> ejete ('diskutil eject /Volumes/Kindle') e reinicie o KOReader; SSH -> reinicie o KOReader
# (o plugin novo só carrega num KOReader novo). O SSH só responde com o Wi-Fi ligado e o aparelho acordado.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="tinta"
APP=""
MOUNT="/Volumes/Kindle"
SSH_IP=""
DRY=0
SSH_PORT="${KINDLE_SSH_PORT:-2222}"
KINDLE_KOREADER="${KINDLE_KOREADER:-/mnt/us/koreader}"

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --ssh) [ $# -ge 2 ] || { echo "ERRO: --ssh precisa do IP do Kindle." >&2; exit 2; }; SSH_IP="$2"; shift 2 ;;
        --plugin) [ $# -ge 2 ] || { echo "ERRO: --plugin precisa de um nome." >&2; exit 2; }; PLUGIN="$2"; shift 2 ;;
        --app) [ $# -ge 2 ] || { echo "ERRO: --app precisa da pasta do app." >&2; exit 2; }; APP="$2"; shift 2 ;;
        --dry-run|-n) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "ERRO: opção desconhecida '$1'." >&2; usage >&2; exit 2 ;;
        *) MOUNT="$1"; shift ;;
    esac
done

# o que vai e para onde: o plugin (koreader/plugins/<nome>.koplugin) ou uma pasta de app (koreader/tinta-apps/<id>)
if [ -n "$APP" ]; then
    [ -f "$APP/init.lua" ] || { echo "ERRO: '$APP' não tem init.lua (passe a pasta do app, ex.: tinta.koplugin/apps/minha_app)." >&2; exit 1; }
    SRC="$(cd "$APP" && pwd)"
    PLUGIN="$(basename "$SRC")"
    case "$PLUGIN" in *[!a-z0-9_]*|"") echo "ERRO: id de app inválido '$PLUGIN' (só a-z, 0-9 e _)." >&2; exit 2 ;; esac
    SUBDIR="tinta-apps"; SUFFIX=""
else
    PLUGIN="${PLUGIN%.koplugin}"
    case "$PLUGIN" in *[!a-z0-9_]*|"") echo "ERRO: nome de plugin inválido '$PLUGIN'." >&2; exit 2 ;; esac
    SRC="$ROOT/$PLUGIN.koplugin"
    SUBDIR="plugins"; SUFFIX=".koplugin"
    [ -d "$SRC" ] || { echo "ERRO: '$SRC' não existe. Nada para copiar." >&2; exit 1; }
fi
NAME="$PLUGIN$SUFFIX"
if [ -n "$SSH_IP" ]; then
    case "$SSH_IP" in *[!0-9A-Za-z.:-]*) echo "ERRO: endereço inválido '$SSH_IP'." >&2; exit 2 ;; esac
fi

# arquivos que vão para o Kindle: tudo do plugin, menos tests/ e arquivos/pastas ocultos
list_files() {
    (cd "$SRC" && find . \( -name '.*' ! -name '.' -o -name tests \) -prune -o -type f -print | sed 's|^\./||' | sort)
}

FILES="$(list_files)"
COUNT="$(printf '%s\n' "$FILES" | grep -c . || true)"

if [ -z "$SSH_IP" ]; then
    DEST="$MOUNT/koreader/$SUBDIR"
    if [ "$DRY" = 1 ]; then
        echo "[dry-run] USB: $SRC/ -> $DEST/$NAME/ ($COUNT arquivos)"
        printf '  %s\n' $FILES
        echo "[dry-run] rsync -rltv --delete --exclude 'tests/' --exclude '.*' \"$SRC/\" \"$DEST/$NAME/\""
        exit 0
    fi
    [ -d "$MOUNT" ] || { echo "ERRO: Kindle não montado em '$MOUNT' (conecte o USB ou passe o caminho como argumento)." >&2; exit 1; }
    [ -d "$MOUNT/koreader" ] || { echo "ERRO: '$MOUNT/koreader' não existe — KOReader não está instalado nesse volume." >&2; exit 1; }
    mkdir -p "$DEST"
    rsync -rltv --delete --exclude 'tests/' --exclude '.*' "$SRC/" "$DEST/$NAME/"
    echo
    echo "Copiado para $DEST/$NAME ($COUNT arquivos)"
    echo "Ejete o Kindle (Finder ou 'diskutil eject \"$MOUNT\"') e reinicie o KOReader."
    exit 0
fi

# SSH: empacota localmente, extrai numa pasta nova no Kindle e troca no fim
REMOTE_DIR="$KINDLE_KOREADER/$SUBDIR"
REMOTE_NEW="$REMOTE_DIR/$NAME.new"
REMOTE_OLD="$REMOTE_DIR/$NAME"
SSH_OPTS=(-p "$SSH_PORT" -o PubkeyAuthentication=no -o ConnectTimeout=10)
REMOTE_CMD="set -e; mkdir -p '$REMOTE_DIR'; rm -rf '$REMOTE_NEW'; mkdir '$REMOTE_NEW'; tar xf - -C '$REMOTE_NEW'; rm -rf '$REMOTE_OLD'; mv '$REMOTE_NEW' '$REMOTE_OLD'; echo ok: \$(find '$REMOTE_OLD' -type f | wc -l) arquivos em '$REMOTE_OLD'"

if [ "$DRY" = 1 ]; then
    echo "[dry-run] SSH: $SRC/ -> root@$SSH_IP:$REMOTE_OLD/ ($COUNT arquivos)"
    printf '  %s\n' $FILES
    echo "[dry-run] (cd \"$SRC\" && COPYFILE_DISABLE=1 tar --format ustar --no-xattrs --no-mac-metadata -cf - <arquivos acima>) | ssh ${SSH_OPTS[*]} root@$SSH_IP \"$REMOTE_CMD\""
    exit 0
fi

echo "Copiando $COUNT arquivos para root@$SSH_IP:$REMOTE_OLD (senha vazia: aperte Enter se pedir)"
# ustar sem xattrs nem metadados do macOS (arquivos ._*): o tar do busybox no Kindle lê sem avisos
(cd "$SRC" && printf '%s\n' "$FILES" | COPYFILE_DISABLE=1 tar --format ustar --no-xattrs --no-mac-metadata -cf - -T -) \
    | ssh "${SSH_OPTS[@]}" "root@$SSH_IP" "$REMOTE_CMD"
echo
if [ -n "$APP" ]; then echo "Reinicie o KOReader (ou feche e abra a Tinta) para carregar o app."; else echo "Reinicie o KOReader para carregar o plugin novo."; fi
