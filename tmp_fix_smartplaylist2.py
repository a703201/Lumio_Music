import os, re

p = r"D:\Codes\Project\Lumio_Music\entry\src\main\ets\services\SmartPlaylistService.ets"

with open(p, 'r', encoding='utf-8') as f:
    s = f.read()

# 1) add the common import right after the existing MusicStore import
old_imp = "import { MusicStore } from './MusicStore';"
new_imp = ("import { MusicStore } from './MusicStore';\n"
           "import { common } from '@kit.AbilityKit';")
if s.count(old_imp) != 1:
    raise SystemExit("import anchor not found exactly once")
s = s.replace(old_imp, new_imp, 1)

# 2) replace every inline ESObject resolution with a typed-context helper call.
#    $r() needs a literal, so we pass the Resource object (not a string) into resolve().
pattern = r"\(AppStorage\.get<ESObject>\('context'\)\?\.resourceManager\.getStringSync\(\$r\('app\.string\.([a-zA-Z_]+)'\)\.id\) as string\) \?\? ''"
def repl(m):
    return "SmartPlaylistService.resolve($r('app.string.%s'))" % m.group(1)
count = len(re.findall(pattern, s))
if count != 9:
    raise SystemExit("expected 9 inline resolutions, found %d" % count)
s = re.sub(pattern, repl, s)

# 3) inject the static helper right before the first method
helper = """  private static resolve(res: Resource): string {
    const ctx: common.UIAbilityContext = AppStorage.get<common.UIAbilityContext>('context') as common.UIAbilityContext;
    if (!ctx) {
      return '';
    }
    return ctx.resourceManager.getStringSync(res.id);
  }

"""
anchor = "  static getFavoritesMix(): SmartPlaylist {"
if s.count(anchor) != 1:
    raise SystemExit("method anchor not found exactly once")
s = s.replace(anchor, helper + anchor, 1)

with open(p, 'w', encoding='utf-8') as f:
    f.write(s)
print("OK SmartPlaylistService.ets: added import + resolve helper, rewired", count, "call sites")
