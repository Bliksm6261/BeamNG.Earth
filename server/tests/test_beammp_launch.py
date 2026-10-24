"""beammp_launch.py (the app starts BeamMP's launcher: found, else downloaded and checked against its SHA-256)."""
import hashlib
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import beammp_launch as bl  # noqa: E402

BODY = b"MZ fake BeamMP launcher"
SHA = hashlib.sha256(BODY).hexdigest()


def fake_get(sha_text, body=BODY, fail=None):
    calls = []

    def get(url):
        calls.append(url)
        if fail:
            raise OSError(fail)
        return sha_text if url == bl.SHA_URL else body
    get.calls = calls
    return get


class BeamMPLaunchTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.data = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def test_sha_files(self):
        self.assertEqual(bl.parse_sha(SHA.upper().encode()), SHA)
        self.assertEqual(bl.parse_sha((SHA + "  BeamMP-Launcher.exe\n").encode()), SHA)
        self.assertIsNone(bl.parse_sha(b"<html>not found</html>"))
        self.assertIsNone(bl.parse_sha(b""))

    def test_downloaded_once_and_checked(self):
        get = fake_get((SHA + "  BeamMP-Launcher.exe").encode())
        path = bl.ensure(self.data, lambda m: None, env={}, get=get)
        self.assertEqual(path, os.path.join(self.data, "beammp", bl.EXE))
        with open(path, "rb") as fh:
            self.assertEqual(fh.read(), BODY)
        self.assertFalse(os.path.exists(path + ".part"))
        again = fake_get(SHA.encode())
        self.assertEqual(bl.ensure(self.data, lambda m: None, env={}, get=again), path)
        self.assertEqual(again.calls, [], "already here: not downloaded again")

    def test_a_mismatch_is_not_kept(self):
        said = []
        path = bl.ensure(self.data, said.append, env={}, get=fake_get(("0" * 64).encode()))
        self.assertIsNone(path)
        self.assertFalse(os.path.exists(os.path.join(self.data, "beammp", bl.EXE)))
        self.assertTrue(any("without multiplayer" in m for m in said))

    def test_offline_starts_without_multiplayer(self):
        self.assertIsNone(bl.ensure(self.data, lambda m: None, env={}, get=fake_get(b"", fail="offline")))

    def test_a_beammp_install_is_used(self):
        appdata = os.path.join(self.data, "Roaming")
        exe = os.path.join(appdata, "BeamMP-Launcher", bl.EXE)
        os.makedirs(os.path.dirname(exe))
        Path(exe).write_bytes(b"x")
        get = fake_get(SHA.encode())
        self.assertEqual(bl.ensure(self.data, lambda m: None, env={"APPDATA": appdata}, get=get), exe)
        self.assertEqual(get.calls, [])


if __name__ == "__main__":
    unittest.main()


class Clock:
    def __init__(self):
        self.t = 0.0

    def now(self):
        return self.t

    def sleep(self, s):
        self.t += s


class FakeProc:
    def __init__(self, ends_at=None):
        self.ends_at, self.clock = ends_at, None

    def poll(self):
        return 1 if self.ends_at is not None and self.clock.t >= self.ends_at else None


class GameStartedTest(unittest.TestCase):
    def run_case(self, proc, game_at=None, **kw):
        c = Clock()
        proc.clock = c
        pids = lambda: [1] if game_at is not None and c.t >= game_at else []  # noqa: E731
        return bl.game_started(proc, pids, sleep=c.sleep, now=c.now, **kw), c.t

    def test_game_appears(self):
        self.assertEqual(self.run_case(FakeProc(), game_at=20), (True, 20))

    def test_launcher_ends_without_game(self):
        ok, t = self.run_case(FakeProc(ends_at=10))
        self.assertFalse(ok)
        self.assertLess(t, 10 + bl.EXIT_GRACE_S + 2)

    def test_launcher_ends_just_before_the_game_is_listed(self):
        self.assertTrue(self.run_case(FakeProc(ends_at=10), game_at=12)[0])

    def test_still_running_after_the_wait(self):
        self.assertEqual(self.run_case(FakeProc(), wait_s=30), (True, 30))
