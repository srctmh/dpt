#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
APKSHIELD v3.1 — Nested Unicode + Valid Arsc
Integrated into SRC TMH DPT
"""
import os, sys, re, random, shutil, subprocess, time, signal
import zipfile, string, tempfile

AUTHOR     = "SRCTMH"
VERSION    = "3.1"
HOME       = os.path.expanduser("~")
OUTPUT_DIR = "/storage/emulated/0/@SRCTMH"
KS_PATH    = os.path.join(HOME, ".apkshield.keystore")
KS_ALIAS   = "apkshield"

def get_ks_pass():
    return os.environ.get("APKSHIELD_KS_PASS", "apkshield123")

PROCESS_TYPES = {
    "drawable", "layout", "menu", "anim", "animator",
    "mipmap", "color", "interpolator", "transition",
    "font", "raw", "xml",
}
SKIP_TYPES = {"values"}
UNI_CHARS = list("ۣ۟۠ۡۢۤۥۦۧۨ۩۪ۭ۫۬")
ASCII_LOW = string.ascii_lowercase

def log(m, t="i"):
    ic = {"ok":"✔", "err":"✘", "warn":"⚠", "i":"➜", "load":"◐"}
    print(f"  {ic.get(t,'·')}  {m}", flush=True)

def safe_remove(p):
    try:
        if os.path.islink(p): os.unlink(p)
        elif os.path.isfile(p): os.remove(p)
        elif os.path.isdir(p): shutil.rmtree(p, ignore_errors=True)
    except Exception:
        pass

def ensure_dir(p):
    if os.path.exists(p) and not os.path.isdir(p):
        safe_remove(p)
    os.makedirs(p, exist_ok=True)

def build_same_length_path(old_bytes):
    target_len = len(old_bytes)
    if not old_bytes.startswith(b'res/') or target_len < 10:
        return None
    ext = b''
    if old_bytes.endswith(b'.9.png'):
        ext = b'.9.png'
    else:
        idx = old_bytes.rfind(b'.')
        if idx > 0 and idx > old_bytes.rfind(b'/'):
            ext = old_bytes[idx:]
    max_nf = (target_len - 6 - len(ext)) // 3
    max_nf = max(1, min(max_nf, 10))
    for nf in range(max_nf, 0, -1):
        fixed = 4 + nf + len(ext)
        remain = target_len - fixed
        if remain < 2 * nf:
            continue
        try:
            if remain % 2 == 0:
                total_u = remain // 2
                if total_u < nf + 1:
                    continue
                chunks = [1] * (nf + 1)
                for _ in range(total_u - (nf + 1)):
                    chunks[random.randint(0, nf)] += 1
                folders = [''.join(random.choice(UNI_CHARS) for _ in range(chunks[i])) for i in range(nf)]
                name = ''.join(random.choice(UNI_CHARS) for _ in range(chunks[nf]))
                name_bytes = name.encode('utf-8')
            else:
                total_u = (remain - 1) // 2
                if total_u < nf:
                    continue
                folder_sizes = [1] * nf
                extra = total_u - nf
                filename_u_size = 0
                for _ in range(extra):
                    slot = random.randint(0, nf)
                    if slot == 0:
                        filename_u_size += 1
                    else:
                        folder_sizes[slot - 1] += 1
                folders = [''.join(random.choice(UNI_CHARS) for _ in range(s)) for s in folder_sizes]
                name_u = ''.join(random.choice(UNI_CHARS) for _ in range(filename_u_size))
                ascii_c = random.choice(ASCII_LOW)
                pos = random.randint(0, len(name_u))
                name = name_u[:pos] + ascii_c + name_u[pos:]
                name_bytes = name.encode('utf-8')
            path = b'res'
            for f in folders:
                path += b'/' + f.encode('utf-8')
            path += b'/' + name_bytes + ext
            if len(path) == target_len:
                return path
        except (UnicodeEncodeError, ValueError):
            continue
    return None

def patch_arsc_inplace(arsc, replacements):
    if not replacements:
        return arsc, 0
    result = bytearray(arsc)
    count = 0
    for old, new in replacements.items():
        if len(old) != len(new):
            continue
        idx = 0
        while True:
            pos = result.find(old, idx)
            if pos == -1:
                break
            result[pos:pos+len(old)] = new
            idx = pos + 1
            count += 1
    return bytes(result), count

def decode(apk, out):
    log("Decoding APK...", "load")
    safe_remove(out)
    try:
        r = subprocess.run(["apktool", "d", "-f", "-o", out, apk],
                           capture_output=True, text=True, timeout=1200)
    except subprocess.TimeoutExpired:
        return False, "decode timeout"
    if r.returncode != 0:
        return False, (r.stderr or "")[-400:]
    return True, "ok"

def build(decoded, out):
    log("Rebuilding APK...", "load")
    safe_remove(out)
    try:
        r = subprocess.run(["apktool", "b", decoded, "-o", out],
                           capture_output=True, text=True, timeout=1800)
    except subprocess.TimeoutExpired:
        return False, "build timeout"
    if r.returncode != 0:
        return False, (r.stderr or "")[-400:]
    if not os.path.isfile(out):
        return False, "no output apk"
    return True, "ok"

def get_manifest_icon(decoded):
    mf = os.path.join(decoded, "AndroidManifest.xml")
    if not os.path.isfile(mf):
        return None
    try:
        with open(mf, "r", encoding="utf-8") as fp:
            txt = fp.read()
    except Exception:
        return None
    m = re.search(r'android:icon\s*=\s*"@(drawable|mipmap)/([^"]+)"', txt)
    return (m.group(1), m.group(2)) if m else None

_used = set()
def rand_ascii(min_l=8, max_l=12):
    for _ in range(10000):
        n = random.randint(min_l, max_l)
        s = random.choice(ASCII_LOW)
        s += "".join(random.choices(ASCII_LOW + string.digits, k=n - 1))
        if s not in _used:
            _used.add(s)
            return s
    return "r" + str(random.randint(1000000, 9999999))

def rename_ascii(decoded):
    res = os.path.join(decoded, "res")
    if not os.path.isdir(res):
        return {}
    icon = get_manifest_icon(decoded)
    rmap = {}
    for folder in sorted(os.listdir(res)):
        fpath = os.path.join(res, folder)
        if not os.path.isdir(fpath):
            continue
        rtype = folder.split("-")[0]
        if rtype in SKIP_TYPES or rtype not in PROCESS_TYPES:
            continue
        for fn in sorted(os.listdir(fpath)):
            old_path = os.path.join(fpath, fn)
            if not os.path.isfile(old_path):
                continue
            if fn.endswith(".9.png"):
                base, ext = fn[:-6], ".9.png"
            else:
                base, ext = os.path.splitext(fn)
            if not base or base[0].isdigit():
                continue
            if icon and rtype == icon[0] and base == icon[1]:
                continue
            new_base = rand_ascii()
            new_fn = new_base + ext
            new_path = os.path.join(fpath, new_fn)
            tries = 0
            while os.path.exists(new_path) and tries < 200:
                new_base = rand_ascii()
                new_fn = new_base + ext
                new_path = os.path.join(fpath, new_fn)
                tries += 1
            try:
                os.rename(old_path, new_path)
                rmap[f"{rtype}/{base}"] = {"new": new_base, "ext": ext}
            except OSError:
                pass
    log(f"Renamed {len(rmap)} files (ASCII stage)", "ok")
    return rmap

def update_xml_refs(decoded, rmap):
    if not rmap:
        return
    targets = []
    for f in os.listdir(decoded):
        if f.endswith(".xml"):
            targets.append(os.path.join(decoded, f))
    res_dir = os.path.join(decoded, "res")
    if os.path.isdir(res_dir):
        for root, _, files in os.walk(res_dir):
            for f in files:
                if f.endswith(".xml"):
                    targets.append(os.path.join(root, f))
    updated = 0
    for path in targets:
        try:
            with open(path, "r", encoding="utf-8") as fp:
                txt = fp.read()
        except (UnicodeDecodeError, OSError):
            continue
        orig = txt
        for key, info in rmap.items():
            rtype, old = key.split("/", 1)
            new = info["new"]
            for pfx in (f"@{rtype}/", f"@+{rtype}/"):
                pat = re.escape(pfx + old) + r'(?![A-Za-z0-9_])'
                txt = re.sub(pat, pfx + new, txt)
        if txt != orig:
            try:
                with open(path, "w", encoding="utf-8") as fp:
                    fp.write(txt)
                updated += 1
            except OSError:
                pass
    log(f"Updated {updated} XML files", "ok")

def update_public_xml(decoded, rmap):
    if not rmap:
        return
    px = os.path.join(decoded, "res", "values", "public.xml")
    if not os.path.exists(px):
        return
    try:
        with open(px, "r", encoding="utf-8") as fp:
            txt = fp.read()
    except OSError:
        return
    for key, info in rmap.items():
        rtype, old = key.split("/", 1)
        new = info["new"]
        pat = rf'(<public\s+type="{re.escape(rtype)}"\s+name="){re.escape(old)}(")'
        txt = re.sub(pat, rf'\g<1>{new}\g<2>', txt)
    try:
        with open(px, "w", encoding="utf-8") as fp:
            fp.write(txt)
    except OSError:
        pass

def apply_nested_unicode(apk_path):
    log("Applying nested unicode paths...", "load")
    tmp = apk_path + ".nx"
    safe_remove(tmp)
    ensure_dir(tmp)
    try:
        with zipfile.ZipFile(apk_path, 'r') as z:
            z.extractall(tmp)
    except Exception as e:
        log(f"Extract fail: {e}", "err")
        safe_remove(tmp)
        return False, 0, 0
    res_dir = os.path.join(tmp, "res")
    if not os.path.isdir(res_dir):
        safe_remove(tmp)
        return False, 0, 0
    replacements = {}
    move_plan = []
    skipped = 0
    for folder in list(os.listdir(res_dir)):
        folder_path = os.path.join(res_dir, folder)
        if not os.path.isdir(folder_path):
            continue
        rtype = folder.split("-")[0]
        if rtype == "values":
            continue
        for fn in list(os.listdir(folder_path)):
            fpath = os.path.join(folder_path, fn)
            if not os.path.isfile(fpath):
                continue
            old_rel = f"res/{folder}/{fn}".encode('utf-8')
            new_rel = build_same_length_path(old_rel)
            if new_rel is None:
                skipped += 1
                continue
            replacements[old_rel] = new_rel
            try:
                dst = os.path.join(tmp, *new_rel.decode('utf-8').split('/'))
                move_plan.append((fpath, dst))
            except Exception:
                skipped += 1
    moved = 0
    for src, dst in move_plan:
        try:
            ensure_dir(os.path.dirname(dst))
            shutil.move(src, dst)
            moved += 1
        except Exception:
            pass
    for folder in list(os.listdir(res_dir)):
        p = os.path.join(res_dir, folder)
        if os.path.isdir(p):
            try:
                if not os.listdir(p):
                    os.rmdir(p)
            except OSError:
                pass
    arsc_count = 0
    arsc_path = os.path.join(tmp, "resources.arsc")
    if os.path.exists(arsc_path) and replacements:
        try:
            with open(arsc_path, "rb") as fp:
                data = fp.read()
            patched, arsc_count = patch_arsc_inplace(data, replacements)
            with open(arsc_path, "wb") as fp:
                fp.write(patched)
            log(f"arsc: {arsc_count} string(s) patched", "ok")
        except Exception as e:
            log(f"arsc patch: {e}", "warn")
    log(f"Moved {moved} files, skipped {skipped}", "ok")
    new_apk = apk_path + ".new"
    safe_remove(new_apk)
    try:
        with zipfile.ZipFile(new_apk, 'w', zipfile.ZIP_DEFLATED) as z:
            for root, _, files in os.walk(tmp):
                for f in files:
                    full = os.path.join(root, f)
                    rel = os.path.relpath(full, tmp)
                    z.write(full, rel)
    except Exception as e:
        log(f"rezip fail: {e}", "err")
        safe_remove(tmp)
        safe_remove(new_apk)
        return False, arsc_count, moved
    shutil.move(new_apk, apk_path)
    safe_remove(tmp)
    return True, arsc_count, moved

def ensure_ks():
    if os.path.exists(KS_PATH):
        return True, "exists"
    log("Generating keystore...", "load")
    cmd = ["keytool", "-genkeypair", "-keystore", KS_PATH,
           "-alias", KS_ALIAS, "-keyalg", "RSA", "-keysize", "2048",
           "-validity", "10000",
           "-storepass", get_ks_pass(),
           "-keypass", get_ks_pass(),
           "-dname", "CN=APKSHIELD,OU=Dev,O=SRCTMH,C=IN"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except Exception as e:
        return False, str(e)
    if r.returncode != 0:
        return False, (r.stderr or "")[-200:]
    return True, "ok"

def try_zipalign(apk):
    if not shutil.which("zipalign"):
        return True, "skipped"
    tmp = apk + ".aligned"
    safe_remove(tmp)
    try:
        r = subprocess.run(["zipalign", "-f", "-p", "4", apk, tmp],
                           capture_output=True, text=True, timeout=180)
        if r.returncode == 0 and os.path.exists(tmp):
            shutil.move(tmp, apk)
            return True, "ok"
        safe_remove(tmp)
        return True, "skipped"
    except Exception:
        return True, "skipped"

def apksign(apk):
    ok, msg = ensure_ks()
    if not ok:
        return False, f"keystore: {msg}"
    try:
        r = subprocess.run([
            "apksigner", "sign",
            "--ks", KS_PATH,
            "--ks-pass", f"pass:{get_ks_pass()}",
            "--key-pass", f"pass:{get_ks_pass()}",
            "--ks-key-alias", KS_ALIAS,
            "--v1-signing-enabled", "true",
            "--v2-signing-enabled", "true",
            "--v3-signing-enabled", "true",
            apk
        ], capture_output=True, text=True, timeout=300)
        if r.returncode != 0:
            return False, (r.stderr or "")[-200:]
        return True, "ok"
    except Exception as e:
        return False, str(e)

def validate_zip(apk):
    try:
        with zipfile.ZipFile(apk, "r") as z:
            if z.testzip() is not None:
                return False, "corrupt"
        return True, "ok"
    except Exception as e:
        return False, str(e)

def process(input_apk, output_apk, no_sign=False):
    results = {"stages": {}, "renamed": 0, "arsc": 0, "moved": 0}
    ok, msg = validate_zip(input_apk)
    if not ok:
        log(f"Invalid input: {msg}", "err")
        return "FAILED", results
    work = tempfile.mkdtemp(prefix="apkshield_", dir=HOME)
    try:
        ok, msg = decode(input_apk, work)
        results["stages"]["decode"] = (ok, msg)
        if not ok:
            log(f"Decode: {msg}", "err")
            return "FAILED", results
        rmap = rename_ascii(work)
        results["renamed"] = len(rmap)
        update_xml_refs(work, rmap)
        update_public_xml(work, rmap)
        tmp_apk = output_apk + ".building"
        safe_remove(tmp_apk)
        ok, msg = build(work, tmp_apk)
        results["stages"]["build"] = (ok, msg)
        if not ok:
            log(f"Build: {msg}", "err")
            safe_remove(tmp_apk)
            return "FAILED", results
        ok, arsc_count, moved = apply_nested_unicode(tmp_apk)
        results["stages"]["nested"] = (ok, f"{moved} moved")
        results["arsc"] = arsc_count
        results["moved"] = moved
        if not ok:
            log("Nested unicode failed", "err")
            safe_remove(tmp_apk)
            return "FAILED", results
        ok, msg = validate_zip(tmp_apk)
        if not ok:
            log(f"ZIP invalid: {msg}", "err")
            safe_remove(tmp_apk)
            return "FAILED", results
        try_zipalign(tmp_apk)
        if not no_sign:
            ok, msg = apksign(tmp_apk)
            results["stages"]["sign"] = (ok, msg)
            if not ok:
                log(f"Sign: {msg}", "err")
                safe_remove(tmp_apk)
                return "FAILED", results
        safe_remove(output_apk)
        shutil.move(tmp_apk, output_apk)
        return "SUCCESS", results
    finally:
        safe_remove(work)

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    no_sign = "--no-sign" in flags
    if len(args) < 2:
        print("Usage: python apkshield.py <input.apk> <output.apk> [--no-sign]")
        return 1
    inp = os.path.abspath(args[0])
    out = os.path.abspath(args[1])
    if not os.path.isfile(inp):
        log(f"Not found: {inp}", "err")
        return 1
    status, _ = process(inp, out, no_sign=no_sign)
    return 0 if status == "SUCCESS" else 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nInterrupted")
        sys.exit(1)
