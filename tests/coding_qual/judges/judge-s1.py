"""DRA-184 hidden judge for scenario S1 (cross-file rename). Never shown to the agent.
Run from the task's repo root inside bwrap --unshare-all: python3 -B judge-s1.py NONCE.
Prints NONCE and exits 0 only when every check holds."""
import sys
import traceback
import unittest

sys.path.insert(0, ".")
ok = True
try:
    import textkit.norm as n
    import textkit.words as w
    assert hasattr(n, "ensure_text"), "norm.ensure_text missing"
    assert not hasattr(n, "require_text"), "norm.require_text still defined"
    assert n.ensure_text("x", "a") == "a"
    try:
        n.ensure_text("x", 1)
        raise AssertionError("ensure_text accepted an int")
    except TypeError as e:
        assert "x must be a str" in str(e)
    src = open("textkit/words.py").read()
    assert "require_text" not in src and "ensure_text" in src, "caller not updated"
    assert w.count_words("a b") == 2
    assert w.title_case("aB cD") == "Ab Cd"
    assert w.truncate_words("a b c", 2) == "a b"
    try:
        w.count_words(3)
        raise AssertionError("count_words accepted an int")
    except TypeError:
        pass
    r = unittest.TextTestRunner(verbosity=0).run(unittest.defaultTestLoader.discover("tests"))
    assert r.wasSuccessful(), "visible tests fail"
except BaseException:
    traceback.print_exc()
    ok = False
if ok:
    print(sys.argv[1])
sys.exit(0 if ok else 1)
