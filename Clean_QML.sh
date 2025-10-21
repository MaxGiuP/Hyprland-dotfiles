python3 - <<'PY'
import os, io, re, sys
root = os.path.expanduser("~/.config/quickshell/ii")
if not os.path.isdir(root):
    print("Missing:", root); sys.exit(1)

# 1) Insert root-relative module import wherever Appearance/Config/Directories/Persistent are used
need_mod_pat = re.compile(r'\b(?:Appearance|Config|Directories|Persistent)\s*\.', re.S)
already_mod_pat = re.compile(r'^\s*import\s+qs\.modules\.common\b', re.M)
def insert_module_import(txt):
    if not need_mod_pat.search(txt): return txt, False
    if already_mod_pat.search(txt): return txt, False
    # insert after the last "import ..." line
    lines = txt.splitlines(True)
    last_imp = -1
    for i,l in enumerate(lines):
        if re.match(r'^\s*import\b', l): last_imp = i
    ins = last_imp + 1 if last_imp >= 0 else 0
    lines.insert(ins, "import qs.modules.common 1.0\n")
    return ("".join(lines), True)

# 2) Normalize imports to the functions directory
#    - If file lives in modules/common/, use:   import "functions"
#    - Elsewhere, use:                          import qs.modules.common.functions
fn_rel_pat = re.compile(r'^\s*import\s+["\'](?:\./)?modules/common/functions/?["\']\s*$', re.M)
fn_rel_dup_pat = re.compile(r'^\s*import\s+["\'](?:\./)?modules/common/modules/common/functions/?["\']\s*$', re.M)
fn_root_pat = re.compile(r'^\s*import\s+["\']qs/modules/common/functions/?["\']\s*$', re.M)
fn_mod_pat  = re.compile(r'^\s*import\s+qs\.modules\.common\.functions\b(?:\s+[0-9]+\.[0-9]+)?\s*$', re.M)

def fix_functions_import(txt, file_dir):
    changed = False
    in_common_dir = file_dir.replace("\\","/").endswith("/modules/common")
    # collapse accidental duplicate path first
    if fn_rel_dup_pat.search(txt):
        if in_common_dir:
            txt = fn_rel_dup_pat.sub('import "functions"', txt); changed = True
        else:
            txt = fn_rel_dup_pat.sub('import qs.modules.common.functions', txt); changed = True
    # normalize root-relative quoted path
    if fn_root_pat.search(txt):
        txt = fn_root_pat.sub('import qs.modules.common.functions', txt); changed = True
    # normalize modules/common/functions quoted path
    if fn_rel_pat.search(txt):
        if in_common_dir:
            txt = fn_rel_pat.sub('import "functions"', txt); changed = True
        else:
            txt = fn_rel_pat.sub('import qs.modules.common.functions', txt); changed = True
    # de-duplicate accidental double import of module form (no versioning for functions)
    if fn_mod_pat.search(txt):
        # keep as-is (valid), no version needed
        pass
    return txt, changed

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
        s, c1 = insert_module_import(s)
        s, c2 = fix_functions_import(s, dp)
        if s != orig:
            io.open(p, "w", encoding="utf-8").write(s)
            patched.append(p)

print("Patched files:")
for p in patched:
    print("  ", p)
PY

# clear QML caches and relaunch your shell
rm -rf "$HOME/.cache/"*qml* 2>/dev/null || true
qs -c "$HOME/.config/quickshell/ii"
