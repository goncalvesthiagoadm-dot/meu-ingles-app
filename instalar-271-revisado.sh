#!/usr/bin/env bash
# Travel & Talk 2.7.1 — self-contained, production-safe hotfix.
# Tested against complete 2.7 source. Does not modify Nginx, OpenClaw,
# other services, data in /var/lib, or authentication configuration.
set -euo pipefail
umask 077

APP=/opt/travel-talk-v25
SERVICE=travel-talk-v25.service
STATE=/var/lib/travel-talk-v25
PUBLIC=https://traveltalk.2-25-210-118.sslip.io
URL='https://raw.githubusercontent.com/goncalvesthiagoadm-dot/meu-ingles-app/travel-talk-v271-revisado-20261117/Travel_Talk_2_7_1_instalacao_revisada.zip.b64'
EXPECTED_ARCHIVE='31038a2240719598ab88b7167b5c3799097ce3c181f4098a3feed56bb38eb56c'
BASE_INDEX='d04f1f62a7889096b73dba7b6faf0480655db7580cd88592f9cfb78edf1e090c'
BASE_SW='ec04fd4f475cbf16816b8a04c6cfcd801145090df73573c4d1b8150de1ffd1af'
BASE_GEMINI='f4edff61528fe4685e154dc51e215af7119ee9157b85f9205305d2e4489b41f0'
PATCH_INDEX='717186b7267dac65d33864bab4c834508a0f6effbfdb100a42456cdd1931773c'
PATCH_SW='9066110a2116396b3a0bc39d0b3666a033130657a01c650ef19bfaf8166a6d6f'
PATCH_GEMINI='81cc8fb72cc4aa3a43464974afb4ff3961cf6c3b75cb38173d61fd7659478a4e'

STAGE=$(mktemp -d /root/tt271-validated.XXXXXXXX)
BACKUP="/root/tt271-backup-$(date +%Y%m%d-%H%M%S)"
CHANGED=0
SMOKE_PID=''
cleanup() {
  if [ -n "$SMOKE_PID" ]; then kill "$SMOKE_PID" 2>/dev/null || true; wait "$SMOKE_PID" 2>/dev/null || true; fi
  rm -rf "$STAGE"
}
rollback() {
  local status=$?
  if [ "$CHANGED" -eq 1 ]; then
    echo 'FALHA NA ATUALIZACAO: restaurando arquivos originais do Travel & Talk.'
    if [ -f "$BACKUP/code.tar.gz" ]; then tar -xzf "$BACKUP/code.tar.gz" -C "$APP" || true; fi
    systemctl restart "$SERVICE" || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap rollback ERR

hash_of() { sha256sum "$1" | awk '{print $1}'; }
check_hash() {
  if [ "$(hash_of "$1")" != "$2" ]; then
    echo "DIVERGENCIA: $1 nao corresponde ao pacote validado. Sem alteracoes."
    exit 1
  fi
}

printf '\n=== PRECHECK DE SEGURANCA ===\n'
[ "$(id -u)" -eq 0 ]
test -f "$APP/index.html" && test -f "$APP/service-worker.js"
test -f "$APP/netlify/functions/gemini.mjs" && test -x "$APP/bin/node"
test -f "$APP/server.mjs" && test -f "$APP/manifest.webmanifest"
test "$(systemctl is-active "$SERVICE")" = active
curl -fsS --max-time 10 http://127.0.0.1:17628/healthz | grep -q '"version":"2.7-hostinger"'
curl -fsS --max-time 12 "$PUBLIC/healthz" | grep -q '"version":"2.7-hostinger"'

# An exact content check is stronger than a version check and avoids mixing
# different releases. An unexpected file aborts without writing anything.
if [ "$(hash_of "$APP/index.html")" = "$PATCH_INDEX" ] && \
   [ "$(hash_of "$APP/service-worker.js")" = "$PATCH_SW" ] && \
   [ "$(hash_of "$APP/netlify/functions/gemini.mjs")" = "$PATCH_GEMINI" ]; then
  echo 'HOTFIX 2.7.1 JA INSTALADO; NENHUMA ALTERACAO.'
  exit 0
fi
check_hash "$APP/index.html" "$BASE_INDEX"
check_hash "$APP/service-worker.js" "$BASE_SW"
check_hash "$APP/netlify/functions/gemini.mjs" "$BASE_GEMINI"

printf '\n=== PACOTE COMPLETO COM VALIDACAO ===\n'
curl -fLsS --retry 2 --max-time 60 "$URL" -o "$STAGE/release.b64"
base64 -d "$STAGE/release.b64" > "$STAGE/release.zip"
echo "$EXPECTED_ARCHIVE  $STAGE/release.zip" | sha256sum -c -
unzip -tq "$STAGE/release.zip" | tail -1
unzip -qo "$STAGE/release.zip" -d "$STAGE"
CAND="$STAGE/travel-talk-v271"
for f in index.html manifest.webmanifest service-worker.js server.mjs \
  test_hostinger.mjs test_mobile25.mjs test_memory24.mjs \
  test_v26.mjs test_v27.mjs test_hotfix271.mjs netlify/functions/gemini.mjs; do
  test -f "$CAND/$f"
done
check_hash "$CAND/index.html" "$PATCH_INDEX"
check_hash "$CAND/service-worker.js" "$PATCH_SW"
check_hash "$CAND/netlify/functions/gemini.mjs" "$PATCH_GEMINI"

printf '\n=== TESTES COMPLETOS NO PACOTE ISOLADO ===\n'
cd "$CAND"
"$APP/bin/node" --check server.mjs
"$APP/bin/node" --check netlify/functions/gemini.mjs
python3 - <<'PY'
from pathlib import Path
import re
html=Path('index.html').read_text(encoding='utf8')
assert 'TT271-STRUCTURED-RESPONSE-HOTFIX' in html
parts=re.findall(r'<script(?:\s[^>]*)?>([\s\S]*?)</script>',html)
assert parts
for i,part in enumerate(parts):
    if part.strip(): Path(f'_syntax_{i}.js').write_text(part,encoding='utf8')
PY
for f in _syntax_*.js; do "$APP/bin/node" --check "$f"; done
"$APP/bin/node" --test test_hostinger.mjs test_mobile25.mjs test_memory24.mjs test_v26.mjs test_v27.mjs test_hotfix271.mjs

printf '\n=== TESTE DE SERVIDOR COMPLETO E SEM API PAGA ===\n'
if ss -H -ltn '( sport = :17636 )' | grep -q .; then
  echo 'Porta de teste 17636 ocupada; nenhuma alteracao.'; exit 1
fi
mkdir -p "$STAGE/temporary-state"
TRAVEL_TALK_PORT=17636 TRAVEL_TALK_DATA_DIR="$STAGE/temporary-state" \
  "$APP/bin/node" server.mjs > "$STAGE/smoke.log" 2>&1 &
SMOKE_PID=$!
READY=0
for i in {1..40}; do
  if curl -fsS --max-time 1 http://127.0.0.1:17636/healthz 2>/dev/null | grep -q '"version":"2.7-hostinger"'; then READY=1; break; fi
  sleep .25
done
test "$READY" -eq 1
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:17636/manifest.webmanifest)
test "$CODE" = 200
kill "$SMOKE_PID" 2>/dev/null || true
wait "$SMOKE_PID" 2>/dev/null || true
SMOKE_PID=''

printf '\n=== BACKUP DE CODIGO E PERFIS ===\n'
install -d -m 700 "$BACKUP"
tar -czf "$BACKUP/code.tar.gz" -C "$APP" index.html service-worker.js netlify/functions/gemini.mjs
if [ -d "$STATE" ]; then
  tar -czf "$BACKUP/private-profiles.tar.gz" -C "$STATE" .
fi
chmod -R go-rwx "$BACKUP"
tar -tzf "$BACKUP/code.tar.gz" >/dev/null

printf '\n=== CORRECAO SOMENTE DO TRAVEL TALK ===\n'
CHANGED=1
for f in index.html service-worker.js netlify/functions/gemini.mjs; do
  install -m 644 "$CAND/$f" "$APP/$f.tt271new"
  mv -f "$APP/$f.tt271new" "$APP/$f"
done
systemctl restart "$SERVICE"
READY=0
for i in {1..40}; do
  if curl -fsS --max-time 1 http://127.0.0.1:17628/healthz 2>/dev/null | grep -q '"version":"2.7-hostinger"'; then READY=1; break; fi
  sleep .25
done
test "$READY" -eq 1
test "$(systemctl is-active "$SERVICE")" = active
curl -fsS --max-time 15 "$PUBLIC/" -o "$STAGE/public.html"
grep -q 'TT271-STRUCTURED-RESPONSE-HOTFIX' "$STAGE/public.html"
check_hash "$APP/index.html" "$PATCH_INDEX"
check_hash "$APP/service-worker.js" "$PATCH_SW"
check_hash "$APP/netlify/functions/gemini.mjs" "$PATCH_GEMINI"
CHANGED=0
trap - ERR
printf '\nTRAVEL TALK 2.7.1 PUBLICADO E VALIDADO\n'
echo "BACKUP: $BACKUP"
echo 'PERFIS PRESERVADOS; OUTROS SERVICOS NAO ALTERADOS'
echo 'FECHAR E REABRIR O APLICATIVO NO IPHONE'
