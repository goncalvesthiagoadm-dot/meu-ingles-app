#!/usr/bin/env python3
"""Travel & Talk 2.7.1 — iPhone keyboard focus zoom fix, reversible."""
import hashlib
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
from datetime import datetime, timezone
from urllib.request import urlopen
import subprocess

APP=Path("/opt/travel-talk-v25")
INDEX=APP/"index.html"
SW=APP/"service-worker.js"
HTML_SHA="717186b7267dac65d33864bab4c834508a0f6effbfdb100a42456cdd1931773c"
SW_SHA="9066110a2116396b3a0bc39d0b3666a033130657a01c650ef19bfaf8166a6d6f"
MARKER="TT271-IOS-FOCUS-NO-AUTOZOOM"
OLD_CACHE="travel-talk-static-hostinger-v2-7-1-structured-fix"
NEW_CACHE="travel-talk-static-hostinger-v2-7-1-ios-zoom-fix"
ANCHOR="        .tt-blind {filter: blur(6px); user-select:none; pointer-events:none;}"
CSS="""        /* TT271-IOS-FOCUS-NO-AUTOZOOM: input focus must not auto-zoom Safari. */
        @supports (-webkit-touch-callout: none) {
          @media screen and (max-width: 600px) {
            input:not([type="hidden"]):not([type="file"]):not([type="radio"]):not([type="checkbox"]):not([type="submit"]):not([type="button"]),
            textarea, select, [contenteditable="true"] {
              font-size: 16px !important;
            }
          }
        }
"""

def sha(b):
    return hashlib.sha256(b).hexdigest()

def overwrite(file,data):
    st=file.stat()
    fd,tmp=tempfile.mkstemp(dir=str(file.parent),prefix=".tt-zoom-")
    try:
        with os.fdopen(fd,"wb") as out:
            out.write(data);out.flush();os.fsync(out.fileno())
        os.chmod(tmp,stat.S_IMODE(st.st_mode))
        os.chown(tmp,st.st_uid,st.st_gid)
        os.replace(tmp,file)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def main():
    old_i,old_s=INDEX.read_bytes(),SW.read_bytes()
    if MARKER.encode() in old_i and NEW_CACHE.encode() in old_s:
        print("CORRECAO JA PRESENTE. Nada alterado.");return
    if sha(old_i)!=HTML_SHA or sha(old_s)!=SW_SHA:
        raise RuntimeError("Arquivos diferentes da versao homologada. Nenhuma alteracao.")
    i=old_i.decode("utf-8");s=old_s.decode("utf-8")
    if i.count(ANCHOR)!=1 or s.count(OLD_CACHE)!=1:
        raise RuntimeError("Marcadores inesperados. Nenhuma alteracao.")
    if "user-scalable=no" in i or "maximum-scale=1" in i:
        raise RuntimeError("Zoom manual bloqueado no HTML. Nenhuma alteracao.")
    if subprocess.run(["systemctl","is-active","--quiet","travel-talk-v25.service"]).returncode!=0:
        raise RuntimeError("Servico Travel Talk inativo. Nenhuma alteracao.")
    new_i=i.replace(ANCHOR,CSS+ANCHOR,1).encode("utf-8")
    new_s=s.replace(OLD_CACHE,NEW_CACHE,1).encode("utf-8")
    folder=Path("/root")/("tt271-ios-zoom-backup-"+datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S"))
    folder.mkdir(mode=0o700)
    shutil.copy2(INDEX,folder/"index.html")
    shutil.copy2(SW,folder/"service-worker.js")
    try:
        overwrite(INDEX,new_i);overwrite(SW,new_s)
        for uri,needle in [("/",MARKER),("/service-worker.js",NEW_CACHE)]:
            with urlopen("http://127.0.0.1:17628"+uri,timeout=8) as r:
                if r.status!=200 or needle not in r.read().decode("utf-8"):
                    raise RuntimeError("Validacao HTTP falhou: "+uri)
    except Exception:
        overwrite(INDEX,old_i);overwrite(SW,old_s)
        print("Falha: arquivos anteriores restaurados.",file=sys.stderr)
        raise
    print("CORRECAO DE ZOOM IOS PUBLICADA")
    print("BACKUP:",folder)
    print("PERFIS PRESERVADOS")
    print("Feche e abra o aplicativo no iPhone.")

if __name__=="__main__":
    try: main()
    except Exception as err:
        print("ERRO:",err,file=sys.stderr);sys.exit(1)
