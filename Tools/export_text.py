# Writes plain chapter text per book to Tools/text/BOOK.txt for question writers.
import json, pathlib
ROOT = pathlib.Path(__file__).parent.parent
bible = json.loads((ROOT / "App/Resources/bible.json").read_text(encoding="utf-8"))
out = ROOT / "Tools/text"
out.mkdir(exist_ok=True)
for b in bible["books"]:
    lines = [f"# {b['name']} ({b['id']})"]
    for ci, ch in enumerate(b["chapters"], 1):
        lines.append(f"\n## Chapter {ci}  ({len(ch['verses'])} verses)")
        if ch.get("title"):
            lines.append(f"[Title: {ch['title']}]")
        for vi, v in enumerate(ch["verses"], 1):
            lines.append(f"{vi}. {v.replace('{', '').replace('}', '')}")
    (out / f"{b['id']}.txt").write_text("\n".join(lines), encoding="utf-8")
print("done")
