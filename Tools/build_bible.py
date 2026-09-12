# Converts the World English Bible (public domain, ebible.org engwebp) USFM into compact JSON.
# Words of Jesus are wrapped in { } for red letter rendering.
import zipfile, re, json, pathlib

BS = chr(92)  # backslash, kept out of literals so shells never mangle it
z = zipfile.ZipFile(pathlib.Path(__file__).parent / "src/web.zip")
books = []

def key(n):
    return int(n.split("-")[0]) if n[0].isdigit() else 999

for name in sorted(z.namelist(), key=key):
    if not name.endswith(".usfm") or name.startswith(("00-", "106-")):
        continue
    t = z.read(name).decode("utf-8").replace(BS, "\x01")
    bid = re.search(r"\x01id (\w+)", t).group(1)
    m = re.search(r"\x01toc2 (.+)", t) or re.search(r"\x01h (.+)", t)
    bname = m.group(1).strip()
    t = re.sub(r"\x01(f|fe|x) .*?\x01\1\*", "", t, flags=re.S)
    t = re.sub(r"\x01\+?w ([^|\x01]*?)(\|[^\x01]*?)?\x01\+?w\*", r"\1", t)
    t = re.sub(r"\x01\+?wh ([^\x01]*?)\x01\+?wh\*", r"\1", t)
    t = t.replace("\x01wj*", "}").replace("\x01wj ", "{")
    t = re.sub(r"\x01(s\d?|ms\d?|mr|r|sp|cl|toc\d|h|mt\d?|ide|rem|sr|id)\b[^\n]*", "", t)
    chapters = []
    state = {"cur": None, "verses": {}, "title": None}

    def flush():
        if state["cur"] is not None:
            vs = state["verses"]
            n = max(vs) if vs else 0
            chapters.append({"title": state["title"], "verses": [vs.get(i, "") for i in range(1, n + 1)]})

    tokens = re.split(r"(\x01c \d+|\x01v \d+(?:-\d+)?|\x01d )", t)
    mode, vnum = None, None
    for tok in tokens:
        m = re.match(r"\x01c (\d+)", tok)
        if m:
            flush()
            state.update(cur=int(m.group(1)), verses={}, title=None)
            mode, vnum = None, None
            continue
        m = re.match(r"\x01v (\d+)", tok)
        if m:
            vnum = int(m.group(1)); mode = "v"
            state["verses"].setdefault(vnum, "")
            continue
        if tok == "\x01d ":
            mode = "d"; continue
        txt = re.sub(r"\x01\+?[a-z]+\d*\*?", " ", tok)
        txt = re.sub(r"\s+", " ", txt)
        if mode == "d":
            state["title"] = txt.strip(); mode = None
        elif mode == "v" and vnum:
            state["verses"][vnum] += txt
    flush()
    for ch in chapters:
        clean = []
        for v in ch["verses"]:
            v = re.sub(r"\s+", " ", v)
            v = re.sub(r"\{\s*\}", "", v)
            v = v.replace("{ ", "{").replace(" }", "} ")
            v = re.sub(r"\s+([,.;:!?’”])", r"\1", v)
            v = re.sub(r"\}([,.;:!?’”])", r"\1}", v)
            clean.append(re.sub(r"\s+", " ", v).strip())
        ch["verses"] = clean
        if not ch["title"]:
            del ch["title"]
    books.append({"id": bid, "name": bname, "chapters": chapters})

out = pathlib.Path(__file__).parent.parent / "App/Resources/bible.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({"translation": "World English Bible", "books": books}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(len(books), "books", sum(len(b["chapters"]) for b in books), "chapters", out.stat().st_size // 1024, "KB")
