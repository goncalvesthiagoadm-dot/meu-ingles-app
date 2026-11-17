#!/usr/bin/env bash
# Instalação segura do Travel & Talk FL27 2.7.2.
# Corrige somente a montagem dos testes no staging. Não altera outros serviços.
set -Eeuo pipefail
umask 077
ZIP=/root/Travel_Talk_FL27_2.7.2_CONSOLIDADO.zip
DIR=/root/tt272-candidato
HASH=ef4aa8f21df56d09d24848d3419f89703b2df9fb2e8049c10df2d58e04457dbd
[ "$(id -u)" = 0 ] || { echo 'ERRO: execute no Web console da Hostinger como root'; exit 1; }
[ -f "$ZIP" ] || { echo 'ERRO: pacote ZIP não encontrado. Nenhuma alteração realizada.'; exit 1; }
printf '%s  %s\n' "$HASH" "$ZIP" | sha256sum -c -
unzip -tq "$ZIP" >/dev/null
mkdir -p "$DIR"
# Extrair novamente o pacote validado, para descartar alterações de tentativas anteriores.
unzip -oq "$ZIP" -d "$DIR"
( cd "$DIR" && sha256sum -c MANIFEST.sha256 ) || { echo 'ERRO: integridade dos arquivos falhou'; exit 1; }
# O instalador original copiava o app atual para o staging, mas substituía
# apenas alguns testes; isso podia misturar testes de versões diferentes.
# Usar o pacote 2.7.2 inteiro no staging mantém o teste de memória e os
# demais testes coerentes com o código candidato, sem tocar em produção.
python3 - "$DIR/deploy_travel_talk_272.sh" "$DIR/deploy_272_staging_fixed.sh" <<'PY'
from pathlib import Path
import sys
source, target = map(Path, sys.argv[1:])
code = source.read_text(encoding='utf-8')
old = 'cp -a "$APP/." "$STAGING/"\n'
new = (old + '# staging completo e imutável da mesma release verificada por SHA\n'
       'cp -a "$SOURCE/." "$STAGING/"\n')
if code.count(old) != 1:
    raise SystemExit('Instalador inesperado: patch não aplicado. Nada foi modificado.')
target.write_text(code.replace(old, new, 1), encoding='utf-8')
target.chmod(0o700)
PY
bash -n "$DIR/deploy_272_staging_fixed.sh"
echo 'TESTES CONSISTENTES: pacote completo preparado; instalação só prossegue se todos passarem.'
# O instalador preserva os prechecks, executa todos os testes, faz backup
# e publica apenas o Travel & Talk. Falhas interrompem antes da publicação.
bash "$DIR/deploy_272_staging_fixed.sh"
