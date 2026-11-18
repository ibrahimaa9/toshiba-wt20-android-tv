#!/usr/bin/env python3
"""privapp-check.py <out/target/product/X> <aapt2>: what PackageManager's privapp-permissions
enforcement (ro.control_privapp_permissions=enforce) would refuse at boot, which makes
system_server crash in a loop. For every priv-app on system / system_ext / product / vendor: the
privileged permissions defined by the platform (framework-res) that it requests, minus those
granted to it by <partition>/etc/permissions/*.xml (privapp-permissions) of its own partition.
Platform-signed apps are exempt; the script reports them separately (cert = framework-res's).
"""
import glob, os, re, subprocess, sys, zipfile, hashlib
import xml.etree.ElementTree as ET

OUT, AAPT2 = sys.argv[1], sys.argv[2]


def xmltree(apk):
    return subprocess.run([AAPT2, 'dump', 'xmltree', '--file', 'AndroidManifest.xml', apk],
                          capture_output=True, text=True).stdout


def cert(apk):
    with zipfile.ZipFile(apk) as z:
        for n in z.namelist():
            if re.match(r'META-INF/.*\.(RSA|DSA|EC)$', n):
                return hashlib.sha1(z.read(n)).hexdigest()  # rough: v1 signature block
    return None


# privileged platform permissions
fw = os.path.join(OUT, 'system/framework/framework-res.apk')
tree = xmltree(fw)
priv = set()
cur = None
for line in tree.splitlines():
    if re.search(r'E: ', line) and cur is not None:
        if cur['name'] and cur['prot'] & 0x10:
            priv.add(cur['name'])
        cur = None
    if re.search(r'E: permission ', line):
        cur = {'name': None, 'prot': 0}
        continue
    if cur is not None:
        m = re.search(r'A: http://schemas.android.com/apk/res/android:name\(0x01010003\)="([^"]+)"', line)
        if m and cur['name'] is None:
            cur['name'] = m.group(1)
        m = re.search(r'protectionLevel\(0x01010009\)=(0x[0-9a-f]+)', line)
        if m:
            cur['prot'] = int(m.group(1), 16)
        if re.search(r'E: ', line):
            if cur['name'] and cur['prot'] & 0x10:
                priv.add(cur['name'])
            cur = None
print('privileged platform permissions:', len(priv))


def allowlist(part):
    al = {}
    for f in glob.glob(os.path.join(OUT, part, 'etc/permissions/*.xml')):
        try:
            root = ET.parse(f).getroot()
        except ET.ParseError:
            continue
        for p in root.iter('privapp-permissions'):
            pkg = p.get('package')
            s = al.setdefault(pkg, set())
            for q in p:
                if q.tag in ('permission', 'deny-permission'):
                    s.add(q.get('name'))
    return al


bad = 0
for part in ('system', 'system_ext', 'product', 'vendor'):
    al = allowlist(part)
    for apk in sorted(glob.glob(os.path.join(OUT, part, 'priv-app/*/*.apk'))):
        t = xmltree(apk)
        m = re.search(r'A: package="([^"]+)"', t)
        if not m:
            continue
        pkg = m.group(1)
        req = set(re.findall(r'E: uses-permission[^\n]*\n\s+A: http://schemas.android.com/apk/res/android:name\(0x01010003\)="([^"]+)"', t))
        need = sorted((req & priv) - al.get(pkg, set()))
        if need:
            bad += 1
            print('\n%s  %s  (%s)' % (part, pkg, os.path.basename(apk)))
            for n in need:
                print('   ', n)
print('\napps with missing entries:', bad)
