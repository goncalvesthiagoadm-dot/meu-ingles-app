#!/usr/bin/env bash
set -euo pipefail
umask 077
APP=/opt/travel-talk-v25
SERVICE=travel-talk-v25.service
PUBLIC=https://traveltalk.2-25-210-118.sslip.io
URL=https://raw.githubusercontent.com/goncalvesthiagoadm-dot/meu-ingles-app/travel-talk-v27-20261117/Travel_Talk_FL27_versao_2_7.zip.b64
EXPECTED=ff10111b97ae59f7c03b11dfa8d66c25ec7a1756e671c40bccbb17926ea08056
STAGE=$(mktemp -d /root/tt27-stage.XXXXXXXX)
BACKUP=/root/tt27-backup-$(date +%Y%m%d-%H%M%S)
MUTATED=0
restore(){
 if [ "$MUTATED" = 1 ]; then
   echo 'FALHA: restaurando codigo anterior do Travel Talk'
   tar -xzf "$BACKUP/code.tar.gz" -C "$APP" || true
   systemctl restart "$SERVICE" || true
 fi
}
trap 'restore; rm -rf "$STAGE"' ERR
trap 'rm -rf "$STAGE"' EXIT
echo '=== VERIFICACOES ==='
test -d "$APP" && test -f "$APP/index.html" && test -x "$APP/bin/node"
test "$(systemctl is-active "$SERVICE")" = active
curl -fsS --max-time 10 http://127.0.0.1:17628/healthz | grep -q '"version":"2.6-hostinger"'
curl -fsS --max-time 10 "$PUBLIC/healthz" | grep -q '"version":"2.6-hostinger"'
nginx -t
if ss -H -ltn '( sport = :17632 )' | grep -q .; then echo 'Porta de teste ocupada';exit 1;fi
echo '=== DOWNLOAD E SHA256 ==='
curl -fLsS --retry 2 --max-time 50 "$URL" -o "$STAGE/pkg.b64"
base64 -d "$STAGE/pkg.b64" > "$STAGE/pkg.zip"
echo "$EXPECTED  $STAGE/pkg.zip" | sha256sum -c -
unzip -tq "$STAGE/pkg.zip" | tail -1
unzip -qo "$STAGE/pkg.zip" -d "$STAGE"
cd "$STAGE/travel-talk-v27"
FILES=(index.html server.mjs content-pool.mjs service-worker.js netlify/functions/discover.mjs)
for f in "${FILES[@]}"; do test -f "$f";done
echo '=== TESTES LOCAIS ==='
"$APP/bin/node" --test test_hostinger.mjs test_mobile25.mjs test_memory24.mjs test_v26.mjs test_v27.mjs
"$APP/bin/node" --check server.mjs
"$APP/bin/node" --check content-pool.mjs
python3 - <<'PY'
from pathlib import Path
s=Path('index.html').read_text()
a=s.index('    <script>',s.index('</style>'))+len('    <script>')
b=s.index('    </script>',a)
Path('/tmp/tt27-client-check.js').write_text(s[a:b])
PY
"$APP/bin/node" --check /tmp/tt27-client-check.js
echo '=== TESTE ISOLADO ==='
mkdir -p "$STAGE/testdata"
TRAVEL_TALK_PORT=17632 TRAVEL_TALK_ADMIN_PORT=0 TRAVEL_TALK_DATA_DIR="$STAGE/testdata" "$APP/bin/node" server.mjs > "$STAGE/smoke.log" 2>&1 &
PID=$!
ready=0
for n in {1..40};do
 if curl -fsS --max-time 1 http://127.0.0.1:17632/healthz 2>/dev/null | grep -q '"version":"2.7-hostinger"';then ready=1;break;fi
 sleep .25
done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
test "$ready" = 1
echo '=== BACKUP ==='
install -d -m 700 "$BACKUP"
tar -czf "$BACKUP/code.tar.gz" -C "$APP" "${FILES[@]}"
cp -p /etc/systemd/system/travel-talk-v25.service "$BACKUP/systemd.service"
if [ -d /var/lib/travel-talk-v25 ];then tar -czf "$BACKUP/profiles.tar.gz" -C /var/lib/travel-talk-v25 .;fi
chmod -R go-rwx "$BACKUP"
echo '=== PUBLICACAO ==='
MUTATED=1
for f in "${FILES[@]}";do install -D -m 644 "$f" "$APP/$f";done
systemctl restart "$SERVICE"
ready=0
for n in {1..40};do
 if curl -fsS --max-time 1 http://127.0.0.1:17628/healthz 2>/dev/null | grep -q '"version":"2.7-hostinger"';then ready=1;break;fi
 sleep .25
done
test "$ready" = 1
curl -fsS --max-time 12 "$PUBLIC/healthz" | grep -q '"version":"2.7-hostinger"'
test "$(systemctl is-active "$SERVICE")" = active
nginx -t
MUTATED=0
trap - ERR
echo 'TRAVEL TALK 2.7 PUBLICADO E VALIDADO'
echo "BACKUP: $BACKUP"
echo 'PERFIS PRESERVADOS; OUTROS SERVICOS INTACTOS'
echo 'TESTES REAIS DE VOZ/VIDEO NO IPHONE AINDA PENDENTES'
