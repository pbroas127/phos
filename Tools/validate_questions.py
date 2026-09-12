# Validates question bank files in App/Resources/questions against bible.json.
# Usage: python validate_questions.py [file ...]   (no args = every file)
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).parent.parent
bible = json.loads((ROOT / "App/Resources/bible.json").read_text(encoding="utf-8"))
verse_counts = {b["id"]: [len(c["verses"]) for c in b["chapters"]] for b in bible["books"]}
files = [pathlib.Path(a) for a in sys.argv[1:]] or sorted((ROOT / "App/Resources/questions").glob("*.json"))
errors, totals = [], {"chapters": 0, "questions": 0}

def err(where, msg):
    errors.append(f"{where}: {msg}")

def words(s):
    return len(s.split())

for f in files:
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except Exception as e:
        err(f.name, f"invalid JSON {e}"); continue
    book = data.get("book")
    if book not in verse_counts:
        err(f.name, f"unknown book {book}"); continue
    for ch_s, ch in data.get("chapters", {}).items():
        ch_n = int(ch_s)
        where = f"{book} {ch_n}"
        if not 1 <= ch_n <= len(verse_counts[book]):
            err(where, "chapter out of range"); continue
        nv = verse_counts[book][ch_n - 1]
        totals["chapters"] += 1
        kv = ch.get("keyVerse")
        if not isinstance(kv, int) or not 1 <= kv <= nv:
            err(where, f"keyVerse {kv} out of range 1..{nv}")
        qs = ch.get("questions", [])
        minimum = 5 if nv <= 6 else 8
        if len(qs) < minimum:
            err(where, f"only {len(qs)} questions, need {minimum}")
        diffs = {q.get("d") for q in qs}
        if nv > 6 and not {1, 2, 3} <= diffs:
            err(where, f"difficulty mix missing levels, has {sorted(d for d in diffs if d)}")
        seen = set()
        for i, q in enumerate(qs):
            w = f"{where} q{i + 1}"
            t = q.get("t")
            totals["questions"] += 1
            if q.get("d") not in (1, 2, 3):
                err(w, "d must be 1, 2, or 3")
            v = q.get("v")
            if not isinstance(v, int) or not 1 <= v <= nv:
                err(w, f"v {v} out of range 1..{nv}")
            text = json.dumps(q, ensure_ascii=False)
            if "—" in text or "–" in text:
                err(w, "contains an em or en dash")
            key = (q.get("q") or "") + "|".join(q.get("items", []))
            if key in seen:
                err(w, "duplicate question")
            seen.add(key)
            if t == "choice":
                o = q.get("options", [])
                if len(o) != 4 or len(set(x.strip().lower() for x in o)) != 4 or not all(isinstance(x, str) and x.strip() for x in o):
                    err(w, "choice needs 4 distinct non empty options, correct first")
                if not q.get("q", "").strip():
                    err(w, "missing q")
            elif t == "blank":
                s = q.get("q", "")
                if s.count("____") != 1:
                    err(w, "blank q must contain ____ exactly once")
                a = q.get("answer", "")
                if not 2 <= words(a) <= 6:
                    err(w, f"blank answer must be 2 to 6 words, got '{a}'")
                wr = q.get("wrong", [])
                if len(wr) != 3 or len({x.strip().lower() for x in wr + [a]}) != 4:
                    err(w, "blank needs 3 distinct wrong phrases different from answer")
                if any(not 1 <= words(x) <= 7 for x in wr):
                    err(w, "wrong phrases must be 1 to 7 words")
            elif t == "order":
                it = q.get("items", [])
                if len(it) != 4 or len(set(it)) != 4:
                    err(w, "order needs 4 distinct items in correct order")
                if any(words(x) > 10 for x in it):
                    err(w, "order items must be 10 words or fewer")
            elif t == "tf":
                if not isinstance(q.get("answer"), bool) or not q.get("q", "").strip():
                    err(w, "tf needs q and boolean answer")
            else:
                err(w, f"unknown type {t}")

for e in errors[:200]:
    print(e)
print(f"{len(files)} files, {totals['chapters']} chapters, {totals['questions']} questions, {len(errors)} errors")
sys.exit(1 if errors else 0)
