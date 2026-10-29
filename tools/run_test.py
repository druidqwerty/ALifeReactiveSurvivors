"""Run the lupa simulation tests of the addon. Exit 1 on any failure.

tools/test_alr.lua        - 0.1.0: tuning, engagement, lease / ignore caps, draw, focus, boot order
tools/test_alr_react.lua  - 0.2.0: vehicles, crowds, lines, bites, vehicle hits
Also checks that every line of the catalog exists in EN and RU.
"""
import json
import os
import sys

import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
MOD_ROOT = os.path.dirname(HERE).replace("\\", "/")
TRANSLATE = os.path.join(MOD_ROOT, "42", "media", "lua", "shared", "Translate")


def load(lang):
    with open(os.path.join(TRANSLATE, lang, "IG_UI.json"), encoding="utf-8") as handle:
        return json.load(handle)


def run(name, translations):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().MOD_ROOT = MOD_ROOT
    table = lua.table()
    for key, value in translations.items():
        table[key] = value
    lua.globals().TRANSLATIONS = table
    with open(os.path.join(HERE, name), encoding="utf-8") as handle:
        source = handle.read()
    print("==", name)
    return lua.execute(source)


def main():
    en, ru = load("EN"), load("RU")
    failed = 0
    if set(en) != set(ru):
        print("FAIL translation keys differ:", sorted(set(en) ^ set(ru)))
        failed += 1
    for key, value in list(en.items()) + list(ru.items()):
        if not value.strip():
            print("FAIL empty translation", key)
            failed += 1
    failed += run("test_alr.lua", en) or 0
    failed += run("test_alr_react.lua", en) or 0
    # every catalog key has a translation
    lua = lupa.LuaRuntime()
    lua.globals().MOD_ROOT = MOD_ROOT
    lua.execute("""
        local loaded = {}
        function require(name)
            if loaded[name] then return loaded[name] end
            local chunk = assert(loadfile(MOD_ROOT .. "/42/media/lua/shared/" .. name .. ".lua"))
            loaded[name] = chunk() or true
            return loaded[name]
        end
        require "ALifeReactive/02_ALR_Lines"
        KEYS = ALifeReactive.Lines.keys()
    """)
    keys = [lua.globals().KEYS[i + 1] for i in range(len(lua.globals().KEYS))]
    missing = [k for k in keys if k not in en]
    if missing:
        print("FAIL catalog keys without translation:", missing)
        failed += 1
    extra = [k for k in en if k not in keys]
    if extra:
        print("FAIL translations without catalog entry:", extra)
        failed += 1
    print("catalog keys:", len(keys), "translations EN/RU:", len(en), len(ru))
    print("TOTAL failed =", failed)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
