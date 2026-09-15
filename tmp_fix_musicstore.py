import os

ms = r"D:\Codes\Project\Lumio_Music\entry\src\main\ets\services\MusicStore.ets"

def patch(path, repls):
    with open(path, 'r', encoding='utf-8') as f:
        s = f.read()
    for i, (old, new) in enumerate(repls):
        c = s.count(old)
        if c != 1:
            raise SystemExit(f"[repl #{i}] expected 1 match, got {c}\n--- old ---\n{old!r}")
        s = s.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(s)
    print("OK", path, "applied", len(repls), "replacements")

patch(ms, [
    # 1) getRdbStore: StoreConfig has no 'version' field in this SDK; drop it (2-arg Promise form)
    ("      this.rdbStore = await relationalStore.getRdbStore(context, {\n"
     "        name: DB_NAME,\n"
     "        securityLevel: relationalStore.SecurityLevel.S1,\n"
     "        version: DB_VERSION\n"
     "      });",
     "      this.rdbStore = await relationalStore.getRdbStore(context, {\n"
     "        name: DB_NAME,\n"
     "        securityLevel: relationalStore.SecurityLevel.S1\n"
     "      });"),
    # 2) untyped object literal -> annotate map callback return type as Playlist
    ("          .filter((p: Playlist) => p !== null && p !== undefined && typeof p.id === 'string')\n"
     "          .map((p: Playlist) => {\n",
     "          .filter((p: Playlist) => p !== null && p !== undefined && typeof p.id === 'string')\n"
     "          .map((p: Playlist): Playlist => {\n"),
    # 3) computed property name forbidden -> indexed assignment
    ("        bucket.push({ [COL_ID]: id } as relationalStore.ValuesBucket);",
     "        const favRow: relationalStore.ValuesBucket = {};\n"
     "          favRow[COL_ID] = id;\n"
     "          bucket.push(favRow);"),
    # 4) computed property name forbidden -> indexed assignment
    ("        bucket.push({ [COL_ID]: k, [COL_VAL]: v } as relationalStore.ValuesBucket);",
     "        const numRow: relationalStore.ValuesBucket = {};\n"
     "          numRow[COL_ID] = k;\n"
     "          numRow[COL_VAL] = v;\n"
     "          bucket.push(numRow);"),
])
