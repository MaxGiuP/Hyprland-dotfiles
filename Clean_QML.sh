#!/usr/bin/env bash
set -euo pipefail

ROOT="${HOME}/.config/quickshell/ii"

python3 - <<'PY'
import os, io, re, sys

root = os.path.expanduser("~/.config/quickshell/ii")
if not os.path.isdir(root):
    print("Missing:", root); sys.exit(1)

# 1) Ensure qs.modules.common is imported when using singletons
need_mod_pat = re.compile(r'\b(?:Appearance|Config|Directories|Persistent)\s*\.', re.S)
already_mod_pat = re.compile(r'^\s*import\s+qs\.modules\.common\b', re.M)
def insert_module_import(txt):
    if not need_mod_pat.search(txt): return txt, False
    if already_mod_pat.search(txt):  return txt, False
    lines = txt.splitlines(True)
    last_imp = -1
    for i,l in enumerate(lines):
        if re.match(r'^\s*import\b', l): last_imp = i
    ins = last_imp + 1 if last_imp >= 0 else 0
    lines.insert(ins, "import qs.modules.common\n")
    return ("".join(lines), True)

# 2) Normalize imports to the functions directory
fn_rel_pat     = re.compile(r'^\s*import\s+["\'](?:\./)?modules/common/functions/?["\']\s*$', re.M)
fn_rel_dup_pat = re.compile(r'^\s*import\s+["\'](?:\./)?modules/common/modules/common/functions/?["\']\s*$', re.M)
fn_root_pat    = re.compile(r'^\s*import\s+["\']qs/modules/common/functions/?["\']\s*$', re.M)
fn_mod_pat     = re.compile(r'^\s*import\s+qs\.modules\.common\.functions\b(?:\s+\d+(?:\.\d+)+)?\s*$', re.M)

def fix_functions_import(txt, file_dir):
    changed = False
    in_common_dir = file_dir.replace("\\","/").endswith("/modules/common")
    if fn_rel_dup_pat.search(txt):
        txt = fn_rel_dup_pat.sub('import "functions"' if in_common_dir else 'import qs.modules.common.functions', txt); changed = True
    if fn_root_pat.search(txt):
        txt = fn_root_pat.sub('import qs.modules.common.functions', txt); changed = True
    if fn_rel_pat.search(txt):
        txt = fn_rel_pat.sub('import "functions"' if in_common_dir else 'import qs.modules.common.functions', txt); changed = True
    return txt, changed

# 3) Replace ANY import "." or "./" with import qs
dot_import_pat = re.compile(r'^\s*import\s+["\']\s*\.(?:/)?\s*["\'](?:\s+\d+(?:\.\d+)*)?\s*$', re.M)
def fix_dot_imports(txt):
    if not dot_import_pat.search(txt): return txt, False
    txt2 = dot_import_pat.sub('import qs', txt)
    return txt2, txt2 != txt

# 4) Deduplicate import lines (drop versions for qs*, keep one)
import_line_pat = re.compile(r'^(\s*)import\s+(.+?)\s*$', re.M)
def dedupe_imports(txt):
    seen = set()
    out_lines = []
    changed = False
    for line in txt.splitlines(True):
        m = import_line_pat.match(line)
        if not m:
            out_lines.append(line); continue
        indent, body = m.groups()
        body_norm = " ".join(body.split())
        key = body_norm
        if body_norm.startswith("qs"):
            key = re.sub(r'\s+\d+(?:\.\d+)*$', '', body_norm)

        if key.lower() in seen:
            changed = True
            continue
        seen.add(key.lower())

        if body_norm.startswith("qs"):
            canon = re.sub(r'\s+\d+(?:\.\d+)*$', '', body_norm)
            out_lines.append(f"{indent}import {canon}\n")
            if canon != body_norm: changed = True
        else:
            out_lines.append(line)

    new_txt = "".join(out_lines)
    return new_txt, (changed or new_txt != txt)

patched = []
for dp,_,files in os.walk(root):
    for fn in files:
        if not fn.endswith(".qml"): continue
        p = os.path.join(dp, fn)
        try:
            s = io.open(p, "r", encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        orig = s
        s, _ = insert_module_import(s)
        s, _ = fix_functions_import(s, dp)
        s, _ = fix_dot_imports(s)
        s, _ = dedupe_imports(s)
        if s != orig:
            io.open(p, "w", encoding="utf-8").write(s)
            patched.append(p)

print("Patched files:")
for p in patched:
    print("  ", p)
PY

# clear QML caches and relaunch
find "$HOME/.cache" -maxdepth 3 -type d -iname '*qml*' -print -exec rm -rf {} + 2>/dev/null
qs -c "$ROOT"
