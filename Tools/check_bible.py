import json, pathlib
d = json.loads((pathlib.Path(__file__).parent.parent / "App/Resources/bible.json").read_text(encoding="utf-8"))
b = {x["id"]: x for x in d["books"]}
for v in b["JHN"]["chapters"][2]["verses"][:5]:
    print(repr(v))
print(b["JHN"]["chapters"][2]["verses"][15])
print(b["PSA"]["chapters"][2])
print(b["PSA"]["chapters"][116])
allv = [v for bb in d["books"] for c in bb["chapters"] for v in c["verses"]]
print("verses", len(allv))
print("brace imbalance", sum(v.count("{") != v.count("}") for v in allv))
print("backslash or marker", sum(("\x01" in v) or (chr(92) in v) for v in allv))
print("empty", sum(v == "" for v in allv))
print([x["id"] for x in d["books"]])
