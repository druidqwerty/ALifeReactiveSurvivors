"""Run tools/test_alr.lua against the addon with lupa. Exit 1 on any failure."""
import os
import sys

import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
MOD_ROOT = os.path.dirname(HERE).replace("\\", "/")

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.globals().MOD_ROOT = MOD_ROOT
with open(os.path.join(HERE, "test_alr.lua"), encoding="utf-8") as handle:
    source = handle.read()
failed = lua.execute(source)
sys.exit(1 if failed else 0)
