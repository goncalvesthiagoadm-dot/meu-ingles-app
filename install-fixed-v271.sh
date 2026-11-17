#!/usr/bin/env bash
set -euo pipefail
umask 077
APP=/opt/travel-talk-v25
SERVICE=travel-talk-v25.service
SITE=https://traveltalk.2-25-210-118.sslip.io
URL=https://raw.githubusercontent.com/goncalvesthiagoadm-dot/meu-ingles-app/travel-talk-hotfix-v271-corrigido-20261117/Travel_Talk_hotfix_2_7_1_corrigido.zip.b64
SHA=3fb491571d62bf8ed02b1e793e3253748afdad945f5cc7b63f7ee9ffa151cd49
STAGE=$(mktemp -d /root/travel-talk-271-fixed.XXXXXXXX)
BACKUP=/root/travel-talk-271-fixed-backup-$(date +%Y%m%d-%H%M%S)
MUTATED=0
NEWTEST=0
cleanup(){ rm -rf "$STAGE"; }
rollback(){
 if [ "$MUTATED" = 1 ]; then
  echo "Falha: restaurando codigo anterior do Travel Talk."
  tar -xzf "$BACKUP/code.tar.gz" -C "$APP" || true
  if [ "$NEWTEST" = 1 ]; then rm -f "$APP/test_hotfix271.mjs"; fi
  systemctl restart "$SERVICE" || true
 fi
}
trap rollback ERR
trap cleanup EXIT
echo "=== CHECAGENS ==="
test -f "$APP/index.html"
test -f "$APP/netlify/functions/gemini.mjs"
test -x "$APP/bin/node"
test "$(systemctl is-active "$SERVICE")" = active
curl -fsS --max-time 10 http://127.0.0.1:17628/healthz | grep -q '"version":"2.7-hostinger"'
curl -fsS --max-time 12 "$SITE/healthz" | grep -q '"version":"2.7-hostinger"'
if grep -q 'TT271-STRUCTURED-RESPONSE-HOTFIX' "$APP/index.html"; then echo "CORRECAO JA INSTALADA"; exit 0; fi
grep -q 'TT27-STRICT-FEEDBACK' "$APP/index.html"
echo "=== BAIXANDO PACOTE CORRIGIDO ==="
curl -fLsS --retry 2 "$URL" -o "$STAGE/archive.b64"
base64 -d "$STAGE/archive.b64" > "$STAGE/archive.zip"
echo "$SHA  $STAGE/archive.zip" | sha256sum -c -
unzip -tq "$STAGE/archive.zip" | tail -1
mkdir -p "$STAGE/patch" "$STAGE/candidate/netlify/functions"
unzip -qo "$STAGE/archive.zip" -d "$STAGE/patch"
FILES=(index.html service-worker.js netlify/functions/gemini.mjs test_hostinger.mjs test_mobile25.mjs test_hotfix271.mjs)
for f in "${FILES[@]}"; do test -f "$STAGE/patch/$f"; done
for f in "$APP"/*.mjs "$APP"/test_*.mjs; do if [ -f "$f" ]; then cp -p "$f" "$STAGE/candidate/"; fi; done
cp -a "$APP/netlify/." "$STAGE/candidate/netlify/"
for f in "${FILES[@]}"; do cp -p "$STAGE/patch/$f" "$STAGE/candidate/$f"; done
echo "=== 23 TESTES ==="
cd "$STAGE/candidate"
"$APP/bin/node" --check netlify/functions/gemini.mjs
python3 - <<'PY'
from pathlib import Path
import re
s=Path('index.html').read_text()
assert 'TT271-STRUCTURED-RESPONSE-HOTFIX' in s
for i,x in enumerate(re.findall(r'<script(?:\s[^>]*)?>([\s\S]*?)</script>',s)):
 if x.strip():Path(f'_syntax_{i}.js').write_text(x)
PY
for f in _syntax_*.js; do "$APP/bin/node" --check "$f"; done
"$APP/bin/node" --test test_hostinger.mjs test_mobile25.mjs test_memory24.mjs test_v26.mjs test_v27.mjs test_hotfix271.mjs
echo "=== BACKUP ==="
install -d -m 700 "$BACKUP"
OLD=(index.html service-worker.js netlify/functions/gemini.mjs test_hostinger.mjs test_mobile25.mjs)
if [ -f "$APP/test_hotfix271.mjs" ]; then OLD+=(test_hotfix271.mjs); else NEWTEST=1; fi
tar -czf "$BACKUP/code.tar.gz" -C "$APP" "${OLD[@]}"
if [ -d /var/lib/travel-talk-v25 ]; then tar -czf "$BACKUP/profiles.tar.gz" -C /var/lib/travel-talk-v25 .; fi
echo "=== PUBLICANDO ==="
MUTATED=1
for f in "${FILES[@]}"; do install -D -m 644 "$STAGE/patch/$f" "$APP/$f"; done
systemctl restart "$SERVICE"
ready=0
for n in {1..40}; do
 if curl -fsS --max-time 2 http://127.0.0.1:17628/healthz 2>/dev/null | grep -q '"version":"2.7-hostinger"'; then ready=1; break; fi
 sleep .25
done
test "$ready" = 1
test "$(systemctl is-active "$SERVICE")" = active
curl -fsS --max-time 15 "$SITE/" -o "$STAGE/actual.html"
grep -q 'TT271-STRUCTURED-RESPONSE-HOTFIX' "$STAGE/actual.html"
MUTATED=0
trap - ERR
echo "TRAVEL TALK 2.7.1 CORRIGIDO E PUBLICADO"
echo "BACKUP: $BACKUP"
echo "PERFIS PRESERVADOS; OUTROS SERVICOS INTACTOS"
