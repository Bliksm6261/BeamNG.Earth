"""BeamMP from the app (the Off the Beaten Track edition; the owner, 2026-10-24: "our app does everything itself"): the
launcher (launcher.py) starts BeamMP's own launcher instead of the game, BeamMP's launcher starts the game with its
multiplayer mod, and the mod's autojoin.lua joins the edition's server. The player never installs or opens BeamMP.

    find()            -> path of a BeamMP-Launcher.exe already here (ours, else a BeamMP install), or None
    ensure(say)       -> find(), else BeamMP's latest release downloaded into our folder and checked against its
                         published SHA-256; None when that fails (the app then starts the game without multiplayer)
    start(exe)        -> Popen of BeamMP's launcher, in its own folder (it keeps its settings and updates there)

Windows only: BeamMP publishes its launcher for Windows (on Linux players install it themselves). Downloaded from
BeamMP's GitHub releases, unchanged; BeamMP's launcher then updates itself from BeamMP (it checks its own updates'
signatures). BeamMP is free software (AGPL-3.0, github.com/BeamMP/BeamMP-Launcher); credited in CREDITS.md.
"""
import hashlib
import os
import subprocess
import urllib.request

EXE = "BeamMP-Launcher.exe"
RELEASE = "https://github.com/BeamMP/BeamMP-Launcher/releases/latest/download/"
URL, SHA_URL = RELEASE + EXE, RELEASE + EXE + ".sha256"
TIMEOUT_S = 60


def own_dir(data_dir):
    """Our copy's folder: beside the app's logs (launcher.data_dir())."""
    return os.path.join(data_dir, "beammp")


def installed_paths(env=None):
    """Where BeamMP's own installer puts its launcher (the per-user and the machine-wide choice)."""
    env = os.environ if env is None else env
    out = []
    for var, sub in (("APPDATA", "BeamMP-Launcher"), ("LOCALAPPDATA", "BeamMP-Launcher"),
                     ("ProgramFiles", "BeamMP-Launcher"), ("ProgramFiles(x86)", "BeamMP-Launcher")):
        if env.get(var):
            out.append(os.path.join(env[var], sub, EXE))
    return out


def find(data_dir, env=None):
    for p in [os.path.join(own_dir(data_dir), EXE)] + installed_paths(env):
        if os.path.isfile(p):
            return p
    return None


def _get(url, timeout=TIMEOUT_S):
    req = urllib.request.Request(url, headers={"User-Agent": "BeamNG.Earth app"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def parse_sha(text):
    """The hex SHA-256 of a .sha256 file ("<hex>" or "<hex>  <name>"), lower case, or None."""
    words = text.decode("ascii", "replace").split() if isinstance(text, bytes) else str(text).split()
    if words and len(words[0]) == 64 and all(c in "0123456789abcdefABCDEF" for c in words[0]):
        return words[0].lower()
    return None


def download(data_dir, get=_get):
    """BeamMP's launcher into own_dir, checked against the release's SHA-256 (written atomically). Returns its path.
    Raises OSError / ValueError when it cannot be fetched or does not match."""
    want = parse_sha(get(SHA_URL))
    if not want:
        raise ValueError("BeamMP's release has no valid SHA-256")
    body = get(URL)
    got = hashlib.sha256(body).hexdigest()
    if got != want:
        raise ValueError(f"BeamMP's launcher does not match its SHA-256 ({got[:12]}... != {want[:12]}...)")
    d = own_dir(data_dir)
    os.makedirs(d, exist_ok=True)
    path, tmp = os.path.join(d, EXE), os.path.join(d, EXE + ".part")
    with open(tmp, "wb") as fh:
        fh.write(body)
    os.replace(tmp, path)
    return path


def ensure(data_dir, say, env=None, get=_get):
    path = find(data_dir, env)
    if path:
        return path
    say("Multiplayer: getting BeamMP (once)...")
    try:
        return download(data_dir, get)
    except (OSError, ValueError) as e:
        say(f"Multiplayer: could not get BeamMP ({e}); starting without multiplayer")
        return None


def start(exe, game_args=()):
    """BeamMP's launcher, which starts the game (anything in game_args goes to the game, after its "--")."""
    cmd = [exe] + (["--"] + list(game_args) if game_args else [])
    return subprocess.Popen(cmd, cwd=os.path.dirname(exe))
