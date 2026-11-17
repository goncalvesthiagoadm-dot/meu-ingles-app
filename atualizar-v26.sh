#!/usr/bin/env bash
set -euo pipefail
umask 077
APP=/opt/travel-talk-v25
SVC=travel-talk-v25.service
PUBLIC=https://traveltalk.2-25-210-118.sslip.io
BASE=https://raw.githubusercontent.com/goncalvesthiagoadm-dot/meu-ingles-app/travel-talk-v26-unificada-20261117
HASH=8f43d41d1cad8a159df02e079d7a9eb090413dffa161cab95ec1becddb3e6bc8
TMP=$(mktemp -d /root/tt26.XXXXXXXX)
BACK="/root/travel-talk-v26-backup-$(date +%Y%m%d-%H%M%S)"
CHANGED=0
FILES="index.html server.mjs mobile-auth.mjs content-pool.mjs service-worker.js manifest.webmanifest robots.txt icon-192.png icon-512.png netlify/functions/gemini.mjs netlify/functions/discover.mjs"
rollback() {
 if [ "$CHANGED" -eq 1 ]; then
  echo "FALHA: restaurando codigo anterior"
  tar -xzf "$BACK/code.tar.gz" -C "$APP" || true
  systemctl restart "$SVC" || true
 fi
}
trap rollback ERR
trap 'rm -rf "$TMP"' EXIT
echo '=== PRECHECKS TRAVEL TALK ==='
test -f "$APP/server.mjs" && test -x "$APP/bin/node"
test "$(systemctl is-active "$SVC")" = active
curl -fsS --max-time 15 http://127.0.0.1:17628/healthz | grep -q '"version":"2.5-hostinger"'
curl -fsS --max-time 15 "$PUBLIC/healthz" | grep -q '"version":"2.5-hostinger"'
if ss -H -ltn '( sport = :17630 )' | grep -q .; then echo "Porta 17630 ocupada; sem alteracoes"; exit 1; fi
echo '=== DOWNLOAD E INTEGRIDADE ==='
curl -fLsS --retry 2 --max-time 45 "$BASE/travel-talk-v26.zip.b64" -o "$TMP/package.b64"
base64 -d "$TMP/package.b64" > "$TMP/package.zip"
echo "$HASH  $TMP/package.zip" | sha256sum -c -
unzip -tq "$TMP/package.zip" | tail -1
unzip -qo "$TMP/package.zip" -d "$TMP"
cd "$TMP/travel-talk-v26"
for F in $FILES; do test -f "$F"; done
echo '=== TESTES DA NOVA VERSAO ==='
"$APP/bin/node" --test test_hostinger.mjs test_mobile25.mjs test_memory24.mjs test_v26.mjs
"$APP/bin/node" --check server.mjs
"$APP/bin/node" --check content-pool.mjs
"$APP/bin/node" --check netlify/functions/gemini.mjs
python3 - <<'PY'
from pathlib import Path
s=Path('index.html').read_text()
start=s.index('    <script>',s.index('</style>'))+len('    <script>')
end=s.index('    </script>',start)
Path('/tmp/travel-talk-v26-js-check.js').write_text(s[start:end])
PY
"$APP/bin/node" --check /tmp/travel-talk-v26-js-check.js
echo '=== TESTE LOCAL SEM PUBLICAR ==='
mkdir -p "$TMP/temp-data"
TRAVEL_TALK_PORT=17630 TRAVEL_TALK_ADMIN_PORT=0 TRAVEL_TALK_DATA_DIR="$TMP/temp-data" "$APP/bin/node" server.mjs > "$TMP/smoke.log" 2>&1 &
PID=$!
READY=0
for N in $(seq 1 30); do
 if curl -fsS --max-time 1 http://127.0.0.1:17630/healthz 2>/dev/null | grep -q '"version":"2.6-hostinger"'; then READY=1; break; fi
 sleep 0.25
done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
test "$READY" = 1
echo '=== BACKUP ==='
install -d -m 700 "$BACK"
EXISTING=""
for F in $FILES; do if [ -f "$APP/$F" ]; then EXISTING="$EXISTING $F"; fi; done
# Word splitting here intentionally names only the fixed whitelist above.
tar -czf "$BACK/code.tar.gz" -C "$APP" $EXISTING
cp -p /etc/systemd/system/travel-talk-v25.service "$BACK/systemd.service"
DATA=$(readlink -f /var/lib/travel-talk-v25)
if [ -d "$DATA" ]; then tar -czf "$BACK/profiles-private.tar.gz" -C "$DATA" .; fi
chmod -R go-rwx "$BACK"
echo '=== INSTALANDO SOMENTE TRAVEL TALK ==='
CHANGED=1
for F in $FILES; do install -D -m 644 "$F" "$APP/$F"; done
systemctl restart "$SVC"
READY=0
for N in $(seq 1 30); do
 if curl -fsS --max-time 2 http://127.0.0.1:17628/healthz 2>/dev/null | grep -q '"version":"2.6-hostinger"'; then READY=1; break; fi
 sleep 0.3
done
test "$READY" = 1
curl -fsS --max-time 15 "$PUBLIC/healthz" | grep -q '"version":"2.6-hostinger"'
test "$(systemctl is-active "$SVC")" = active
CHANGED=0
trap - ERR
echo "TRAVEL TALK 2.6 PUBLICADO E VALIDADO"
echo "BACKUP: $BACK"
echo "PERFIS PRIVADOS PRESERVADOS"
