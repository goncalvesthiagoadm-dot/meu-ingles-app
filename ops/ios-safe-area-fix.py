#!/usr/bin/env python3
"""Travel & Talk 2.5: correct iPhone standalone status-bar overlap only.

No profile/session files, environment variables, nginx or server units are changed.
Idempotent; validates exact markers and writes a timestamped rollback copy.
"""
import os
import sys
import tempfile
import time
from pathlib import Path

DIR = Path(sys.argv[1] if len(sys.argv) > 1 else '/opt/travel-talk-v25')
HTML = DIR / 'index.html'
SW = DIR / 'service-worker.js'
MARKER = '/* TT25-IOS-SAFE-AREA-FIX */'
HTML_ANCHOR = '''    <!-- Fonte Inter -->'''
CSS_ANCHOR = '''        .no-scrollbar::-webkit-scrollbar { display: none; }'''
SCRIPT = '''    <script>
        // Em modo aplicativo, o iOS pode sobrepor a barra de status ao cabeçalho.
        // Detecta também o modo standalone antigo do Safari no iPhone.
        if (window.navigator.standalone === true || window.matchMedia('(display-mode: standalone)').matches) {
            document.documentElement.classList.add('tt-standalone');
            if (/iPhone|iPod/.test(navigator.userAgent)) {
                document.documentElement.classList.add('tt-ios-standalone');
            }
        }
    </script>
'''
CSS = '''        /* TT25-IOS-SAFE-AREA-FIX */
        html.tt-standalone body {
            padding-top: env(safe-area-inset-top, 0px);
        }
        html.tt-standalone #toast {
            top: calc(env(safe-area-inset-top, 0px) + 1rem);
        }
        /* Em iPhones com Dynamic Island, preserve uma margem mínima mesmo
           caso um webview devolva inset=0 ao abrir pela Tela de Início. */
        @media (orientation: portrait) and (max-width: 600px) {
            html.tt-ios-standalone body {
                padding-top: max(56px, env(safe-area-inset-top, 0px));
            }
            html.tt-ios-standalone #toast {
                top: calc(max(56px, env(safe-area-inset-top, 0px)) + 1rem);
            }
        }
'''

def replace_one(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f'Marcador ausente ou repetido: {old[:72]!r}')
    return source.replace(old, new, 1)

def safe_write(path, content):
    fd, temp = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name + '.')
    try:
        with os.fdopen(fd,'w',encoding='utf-8',newline='\n') as out:
            out.write(content)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(temp, path.stat().st_mode & 0o777)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp): os.unlink(temp)

def main():
    old_html = HTML.read_text(encoding='utf-8')
    old_sw = SW.read_text(encoding='utf-8')
    if MARKER in old_html:
        print('SAFE AREA: JA CORRIGIDA; NENHUMA ALTERACAO')
        return
    assert 'viewport-fit=cover' in old_html
    assert 'black-translucent' in old_html
    assert 'travel-talk-static-hostinger-v2-5-1' in old_sw
    new_html = replace_one(old_html, HTML_ANCHOR, SCRIPT + HTML_ANCHOR)
    new_html = replace_one(new_html, CSS_ANCHOR, CSS + CSS_ANCHOR)
    new_sw = replace_one(old_sw, 'travel-talk-static-hostinger-v2-5-1', 'travel-talk-static-hostinger-v2-5-ios-fix1')
    stamp = time.strftime('%Y%m%d-%H%M%S')
    backup_html = DIR / f'index.html.before-ios-fix.{stamp}.bak'
    backup_sw = DIR / f'service-worker.js.before-ios-fix.{stamp}.bak'
    # Backup copies reside beside the assets but cannot be reached through the
    # allowlisted HTTP routes in the Node app.
    backup_html.write_text(old_html, encoding='utf-8')
    backup_sw.write_text(old_sw, encoding='utf-8')
    os.chmod(backup_html,0o600)
    os.chmod(backup_sw,0o600)
    try:
        safe_write(HTML,new_html)
        safe_write(SW,new_sw)
        assert MARKER in HTML.read_text(encoding='utf-8')
        assert 'travel-talk-static-hostinger-v2-5-ios-fix1' in SW.read_text(encoding='utf-8')
    except Exception:
        safe_write(HTML,old_html)
        safe_write(SW,old_sw)
        raise
    print('SAFE AREA CORRIGIDA')
    print('BACKUP HTML:',backup_html)
    print('BACKUP SW:',backup_sw)
    print('Nao foi necessario reiniciar Nginx ou o servico Travel Talk.')

if __name__ == '__main__': main()
