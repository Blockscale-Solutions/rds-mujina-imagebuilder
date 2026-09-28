#!/usr/bin/env python3
"""Runs INSIDE the container (#45): manifest of one assembly's images.

    repro-manifest.py IMAGES_DIR UNSQUASHFS OUT.tsv

One row per image artifact (type i), then one per entry inside
rootfs.squashfs: type, path, mode, uid, gid, mtime, size, sha256 (symlinks
hash their target). Owners come from unsquashfs's numeric listing, since an
unprivileged extraction cannot keep them.
"""
import hashlib, os, re, stat, subprocess, sys, tempfile

img, unsq, out = sys.argv[1:4]
H = lambda b: hashlib.sha256(b).hexdigest()
rows = []
for n in sorted(os.listdir(img)):
    p = os.path.join(img, n)
    if os.path.isfile(p):
        rows.append(["i", "images/" + n, "", "", "", "", str(os.path.getsize(p)), H(open(p, "rb").read())])
sq = os.path.join(img, "rootfs.squashfs")
owners = {}
lst = subprocess.run([unsq, "-lln", "-d", "", sq], capture_output=True, text=True, check=True).stdout
for line in lst.splitlines():
    m = re.match(r"^\S+\s+(\d+)/(\d+)\s+.*?\s(/\S*)(?: -> .*)?$", line)
    if m:
        owners[m[3]] = (m[1], m[2])
with tempfile.TemporaryDirectory() as t:
    root = os.path.join(t, "r")
    subprocess.run([unsq, "-no-xattrs", "-d", root, sq], capture_output=True, check=True)
    for dp, dns, fns in os.walk(root):
        for n in sorted(dns) + sorted(fns):
            p = os.path.join(dp, n); rel = "/" + os.path.relpath(p, root); st = os.lstat(p)
            uid, gid = owners.get(rel, ("?", "?"))
            if stat.S_ISLNK(st.st_mode):
                kind, digest = "l", H(os.readlink(p).encode())
            elif stat.S_ISDIR(st.st_mode):
                kind, digest = "d", ""
            else:
                kind, digest = "f", H(open(p, "rb").read())
            rows.append([kind, rel, oct(stat.S_IMODE(st.st_mode)), uid, gid, str(int(st.st_mtime)), str(st.st_size if kind == "f" else 0), digest])
with open(out, "w") as f:
    for r in sorted(rows, key=lambda r: r[1]):
        f.write("\t".join(r) + "\n")
print(f"repro-manifest: {len(rows)} entries -> {out}")
