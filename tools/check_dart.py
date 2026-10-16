import glob, os, re, sys, collections

ROOT = sys.argv[1]
files = sorted(glob.glob(f'{ROOT}/lib/**/*.dart', recursive=True) + glob.glob(f'{ROOT}/test/*.dart'))

def strip(src):
    out=[];i=0;n=len(src)
    while i<n:
        c=src[i]
        if src.startswith('//',i):
            j=src.find('\n',i); i=n if j<0 else j; continue
        if src.startswith('/*',i):
            j=src.find('*/',i); i=n if j<0 else j+2; continue
        raw = c=='r' and i+1<n and src[i+1] in "'\""
        if raw: i+=1; c=src[i]
        if c in "'\"":
            q=src[i:i+3] if src[i:i+3] in ("'''",'"""') else c
            j=i+len(q)
            while j<n:
                if not raw and src[j]=='\\': j+=2; continue
                if not raw and src.startswith('${',j):
                    d=1;j+=2
                    while j<n and d:
                        if src[j]=='{': d+=1
                        elif src[j]=='}': d-=1
                        j+=1
                    continue
                if src.startswith(q,j): j+=len(q); break
                j+=1
            out.append('""'); i=j; continue
        out.append(c); i+=1
    return ''.join(out)

problems=[]
decl_of={}   # public symbol -> first file that declares it
decl_all=collections.defaultdict(set)   # symbol -> every file that declares it
code={}

DECL = re.compile(r'^(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+|mixin\s+)*'
                  r'(?:class|enum|mixin|extension|typedef)\s+([A-Za-z_][A-Za-z0-9_]*)', re.M)
# Top-level function: allows named parameters '{...}' in the list, and both '{' and '=>' bodies.
TOPFUNC = re.compile(r'^(?:[A-Za-z_][\w<>,\s\?\[\]]*\s+)?([a-z_][A-Za-z0-9_]*)\s*'
                     r'\((?:[^()]|\([^()]*\))*\)\s*(?:async\s*)?(?:\{|=>)', re.M)
TOPVAR = re.compile(r'^(?:const|final)\s+(?:[\w<>,\s\?\[\]]+\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=', re.M)

for f in files:
    src = open(f, encoding='utf-8').read()
    s = strip(src)
    code[f] = (src, s)
    for rx in (DECL, TOPVAR, TOPFUNC):
        for m in rx.finditer(s):
            decl_of.setdefault(m.group(1), f)
            decl_all[m.group(1)].add(os.path.normpath(f))

# 1. brackets
for f,(src,s) in code.items():
    st=[];pairs={')':'(',']':'[','}':'{'};line=1;ok=True
    for ch in s:
        if ch=='\n': line+=1
        if ch in '([{': st.append((ch,line))
        elif ch in ')]}':
            if not st or st[-1][0]!=pairs[ch]:
                problems.append(f'{f}: unbalanced {ch!r} at line {line}'); ok=False; break
            st.pop()
    if ok and st: problems.append(f'{f}: unclosed {st[-1][0]!r} opened at line {st[-1][1]}')

# 2. imports resolve + build import graph
imports = collections.defaultdict(set)
for f,(src,s) in code.items():
    d = os.path.dirname(f)
    for m in re.finditer(r"""import\s+'([^']+)'""", src):
        p = m.group(1)
        if p.startswith('package:') or p.startswith('dart:'):
            if p.startswith('package:lead_desk/'):
                t = os.path.join(ROOT,'lib',p[len('package:lead_desk/'):])
                if not os.path.isfile(t): problems.append(f'{f}: missing import {p}')
                imports[f].add(os.path.normpath(t))
            continue
        t = os.path.normpath(os.path.join(d,p))
        if not os.path.isfile(t):
            problems.append(f'{f}: import not found -> {p}')
        else:
            imports[f].add(t)

# 2b. an imported file may re-export others (conditional exports for web vs mobile)
EXPORT = re.compile(r"""export\s+'([^']+)'(?:[^;]*?'([^']+)')?""")
for f in list(imports):
    for t in list(imports[f]):
        src_t = code.get(t, (None, None))[0]
        if not src_t: continue
        for m in EXPORT.finditer(src_t):
            for p in (m.group(1), m.group(2)):
                if not p or p.startswith('package:') or p.startswith('dart:'): continue
                e = os.path.normpath(os.path.join(os.path.dirname(t), p))
                if os.path.isfile(e): imports[f].add(e)

# 3. project symbols used without importing their file
IDENT = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)\b')
for f,(src,s) in code.items():
    used = set(IDENT.findall(s))
    here = os.path.normpath(f)
    for name in used:
        owners = decl_all.get(name)
        if not owners or here in owners: continue
        if name.startswith('_'): continue
        if not (owners & imports[f]):
            where = ', '.join(sorted(os.path.relpath(o, ROOT) for o in owners))
            problems.append(f'{f}: uses {name} (declared in {where}) but does not import it')

# 4. unused project imports (warning only)
# Uses the source with comments removed but STRINGS KEPT, because a symbol used only
# inside '${...}' interpolation is still a real use.
NOCOMMENT = lambda t: re.sub(r'//[^\n]*', '', re.sub(r'/\*.*?\*/', '', t, flags=re.S))
warn=[]
for f,(src,s) in code.items():
    used = set(IDENT.findall(NOCOMMENT(src)))
    for t in imports[f]:
        owned = [n for n,o in decl_all.items() if t in o]
        if owned and not (used & set(owned)):
            warn.append(f'{f}: import {os.path.relpath(t, ROOT)} may be unused')


# 5. escaped interpolation -- the heredoc bug: a literal \$ that should have been $
BADDOLLAR = re.compile(r'\\\$(\{|[A-Za-z_])')
for f,(src,s_) in code.items():
    for i,line in enumerate(src.splitlines(), 1):
        if BADDOLLAR.search(line):
            problems.append(f'{f}:{i}: literal \\$ in Dart source -- interpolation was escaped')

print(f'files checked: {len(files)}   project symbols: {len(decl_of)}')
if problems:
    print('\n--- PROBLEMS ---')
    for p in sorted(set(problems)): print(' ', p)
else:
    print('no structural problems')
if warn:
    print('\n--- possibly unused imports ---')
    for w in sorted(set(warn)): print(' ', w)
