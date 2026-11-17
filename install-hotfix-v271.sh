#!/usr/bin/env bash
# Travel & Talk 2.7.1: hotfix for structured Gemini response. No changes outside the app.
set -euo pipefail
umask 077
APP=/opt/travel-talk-v25
SERVICE=travel-talk-v25.service
PUBLIC=https://traveltalk.2-25-210-118.sslip.io
URL='https://raw.githubusercontent.com/goncalvesthiagoadm-dot/meu-ingles-app/travel-talk-hotfix-v271-20261117/Travel_Talk_hotfix_2_7_1.zip.b64'
SHA='61617460cfd852c56048243ec006f90d9b7e36ca3e83ffff3a942c40560dd048'
STAGE=$(mktemp -d /root/tt271-stage.XXXXXXXX)
BACKUP="/root/travel-talk-v271-backup-$(date +%Y%m%d-%H%M%S)"
MUTATED=0
restore(){
  if [ "$MUTATED" -eq 1 ]; then
    echo 'Falha no hotfix: restaurando somente os arquivos anteriores do Travel & Talk.'
    tar -xzf "$BACKUP/code.tar.gz" -C "$APP" || true
    systemctl restart "$SERVICE" || true
  fi
}
cleanup(){ rm -rf "$STAGE"; }
trap 'restore; cleanup' ERR
trap cleanup EXIT

echo '=== VERIFICANDO INSTALACAO ==='
test -f "$APP/index.html" && test -f "$APP/netlify/functions/gemini.mjs"
test -x "$APP/bin/node" && test -f "$APP/service-worker.js"
test "$(systemctl is-active "$SERVICE")" = active
curl -fsS --max-time 10 http://127.0.0.1:17628/healthz | grep -q '"version":"2.7-hostinger"'
curl -fsS --max-time 12 "$PUBLIC/healthz" | grep -q '"version":"2.7-hostinger"'
if grep -q 'TT271-STRUCTURED-RESPONSE-HOTFIX' "$APP/index.html"; then
  echo 'CORRECAO 2.7.1 JA APLICADA; NENHUMA ALTERACAO'
  exit 0
fi
grep -q 'TT27-STRICT-FEEDBACK' "$APP/index.html"

echo '=== BAIXANDO E VERIFICANDO O PACOTE ==='
curl -fLsS --retry 2 --max-time 60 "$URL" -o "$STAGE/package.b64"
base64 -d "$STAGE/package.b64" > "$STAGE/package.zip"
echo "$SHA  $STAGE/package.zip" | sha256sum -c -
unzip -tq "$STAGE/package.zip" | tail -1
mkdir -p "$STAGE/patch" "$STAGE/candidate/netlify/functions"
unzip -qo "$STAGE/package.zip" -d "$STAGE/patch"
for f in index.html service-worker.js netlify/functions/gemini.mjs test_hotfix271.mjs; do
  test -f "$STAGE/patch/$f"
done

echo '=== TESTANDO SEM CHAMADAS AO GEMINI ==='
# Prepare just the tested app code, never its credentials, sessions or profile data.
for f in "$APP"/*.mjs "$APP"/test_*.mjs; do
  test -f "$f" && cp -p "$f" "$STAGE/candidate/"
done
cp -a "$APP/netlify/." "$STAGE/candidate/netlify/"
for f in index.html service-worker.js netlify/functions/gemini.mjs test_hotfix271.mjs; do
  cp -p "$STAGE/patch/$f" "$STAGE/candidate/$f"
done
cd "$STAGE/candidate"
"$APP/bin/node" --check netlify/functions/gemini.mjs
python3 - <<'PY'
from pathlib import Path
import re
html=Path('index.html').read_text(encoding='utf-8')
scripts=re.findall(r'<script(?:\s[^>]*)?>([\s\S]*?)</script>',html)
assert any('TT271-STRUCTURED-RESPONSE-HOTFIX' in s for s in scripts)
for i,s in enumerate(scripts):
    if s.strip():Path(f'_check_inline_{i}.js').write_text(s,encoding='utf-8')
PY
for f in _check_inline_*.js; do "$APP/bin/node" --check "$f"; done
"$APP/bin/node" --test test_hostinger.mjs test_mobile25.mjs test_memory24.mjs test_v26.mjs test_v27.mjs test_hotfix271.mjs

echo '=== BACKUP RESTRITO AO TRAVEL TALK ==='
install -d -m 700 "$BACKUP"
tar -czf "$BACKUP/code.tar.gz" -C "$APP" index.html service-worker.js netlify/functions/gemini.mjs
# This hotfix does not change profile data; keep a recovery snapshot nonetheless.
if [ -d /var/lib/travel-talk-v25 ]; then
  tar -czf "$BACKUP/private-profiles.tar.gz" -C /var/lib/travel-talk-v25 .
fi
chmod -R go-rwx "$BACKUP"

echo '=== PUBLICANDO HOTFIX 2.7.1 ==='
MUTATED=1
for f in index.html service-worker.js netlify/functions/gemini.mjs; do
  install -D -m 644 "$STAGE/patch/$f" "$APP/$f"
done
systemctl restart "$SERVICE"
ready=0
for i in {1..40}; do
  if curl -fsS --max-time 2 http://127.0.0.1:17628/healthz 2>/dev/null | grep -q '"version":"2.7-hostinger"'; then
    ready=1;break
  fi
  sleep .25
done
test "$ready" = 1
test "$(systemctl is-active "$SERVICE")" = active
curl -fsS --max-time 12 "$PUBLIC/" -o "$STAGE/public.html"
grep -q 'TT271-STRUCTURED-RESPONSE-HOTFIX' "$STAGE/public.html"
MUTATED=0
trap - ERR
echo 'TRAVEL TALK 2.7.1 CORRECAO DO PROFESSOR PUBLICADA'
echo "BACKUP: $BACKUP"
echo 'PERFIS PRESERVADOS; NGINX E OUTROS SERVICOS NAO ALTERADOS'
echo 'NO IPHONE: FECHE E REABRA O APLICATIVO PARA ATUALIZAR'