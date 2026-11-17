#!/usr/bin/env python3
"""Travel & Talk 2.7.1: hotfix iOS keyboard-focus automatic zoom.

Changes only index.html CSS and service-worker.js cache label. No secrets,
profiles, auth, API routes, Nginx, systemd units, or other services changed.
Requires the exact published 2.7.1 file hashes; aborts on any divergence.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from urllib.request import urlopen

APP = Path('/opt/travel-talk-v25')
OLD_HTML_SHA = '717186b7267dac65d33864bab4c834508a0f6effbfdb100a42456cdd1931773c'
OLD_SW_SHA = '9066110a2116396b3a0bc39d0b3666a033130657a01c650ef19bfaf8166a6d6f'
OLD_CACHE = "travel-talk-static-hostinger-v2-7-1-structured-fix"
NEW_CACHE = "travel-talk-static-hostinger-v2-7-1-ios-zoom-fix"
MARKER = 'TT271-IOS-FOCUS-NO-AUTOZOOM'

CSS = '''        /* TT271-IOS-FOCUS-NO-AUTOZOOM
           iOS Safari increases page scale when a focused editable field has
           computed font-size under 16px. Do NOT disable user pinch zoom. */
        @supports (-webkit-touch-callout: none) {
          @media screen and (max-width: 600px) {
            input:not([type="hidden"]):not([type="file"]):not([type="radio"]):not([type="checkbox"]):not([type="submit"]):not([type="button"]),
            textarea, select, [contenteditable="true"] {
              font-size: 16px !important;
            }
          }
        }
'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def patch_content(html: bytes, sw: bytes) -> tuple[bytes, bytes]:
    if digest(html) != OLD_HTML_SHA or digest(sw) != OLD_SW_SHA:
        raise RuntimeError('Versao local diferente da 2.7.1 validada: NENHUMA ALTERACAO. Informe os hashes ao suporte.')
    text = html.decode('utf-8')
    anchor = '        .tt-blind {filter: blur(6px); user-select:none; pointer-events:none;}'
    if text.count(anchor) != 1:
        raise RuntimeError('Marcador CSS inesperado: NENHUMA ALTERACAO.')
    text = text.replace(anchor, CSS + anchor, 1)
    cache = sw.decode('utf-8')
    if cache.count(OLD_CACHE) != 1:
        raise RuntimeError('Marcador de cache inesperado: NENHUMA ALTERACAO.')
    cache = cache.replace(OLD_CACHE, NEW_CACHE, 1)
    if 'user-scalable=no' in text or 'maximum-scale=1' in text:
        raise RuntimeError('Viewport nao acessivel detectado: NENHUMA ALTERACAO.')
    return text.encode('utf-8'), cache.encode('utf-8')


def replace_preserving_metadata(path: Path, data: bytes) -> None:
    st = path.stat()
    fd, temp = tempfile.mkstemp(prefix='.tt271-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(temp, stat.S_IMODE(st.st_mode))
        os.chown(temp, st.st_uid, st.st_gid)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def assert_http() -> None:
    for suffix, expected in [('/', MARKER), ('/service-worker.js', NEW_CACHE)]:
        with urlopen('http://127.0.0.1:17628' + suffix, timeout=8) as r:
            response = r.read().decode('utf-8')
            if r.status != 200 or expected not in response:
                raise RuntimeError('Resposta HTTP sem a correcao: ' + suffix)


def main() -> None:
    html_path = APP / 'index.html'
    sw_path = APP / 'service-worker.js'
    old_html = html_path.read_bytes()
    old_sw = sw_path.read_bytes()
    if MARKER.encode() in old_html and NEW_CACHE.encode() in old_sw:
        print('ZOOM JA CORRIGIDO; nenhuma mudanca')
        return

    patched_html, patched_sw = patch_content(old_html, old_sw)
    service = subprocess.run(['systemctl', 'is-active', 'travel-talk-v25.service'],
                             capture_output=True, text=True, check=False)
    if service.returncode != 0 or service.stdout.strip() != 'active':
        raise RuntimeError('Servico Travel Talk nao esta ativo. NENHUMA ALTERACAO.')

    backup = Path('/root') / ('travel-talk-ios-zoom-backup-' + datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S'))
    backup.mkdir(mode=0o700)
    shutil.copy2(html_path, backup / 'index.html')
    shutil.copy2(sw_path, backup / 'service-worker.js')
    try:
        replace_preserving_metadata(html_path, patched_html)
        replace_preserving_metadata(sw_path, patched_sw)
        assert_http()
    except Exception:
        replace_preserving_metadata(html_path, old_html)
        replace_preserving_metadata(sw_path, old_sw)
        print('FALHA NA VALIDACAO. Arquivos anteriores restaurados.', file=sys.stderr)
        raise
    print('CORRECAO DO ZOOM IOS PUBLICADA')
    print('BACKUP:', backup)
    print('PERFIS E OUTROS SERVICOS NAO ALTERADOS')
    print('Feche e reabra o aplicativo no iPhone para atualizar o cache.')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('ERRO:', exc, file=sys.stderr)
        sys.exit(1)
