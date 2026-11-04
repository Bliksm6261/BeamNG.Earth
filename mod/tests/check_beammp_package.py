"""Build a real BeamMP archive using a fixture with ledger data present."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import zipfile
root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('packager', root / 'tools/package.py')
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)
with tempfile.TemporaryDirectory() as tmp:
    fixture = Path(tmp)
    shutil.copytree(root / 'beammp/Server', fixture / 'beammp/Server')
    plugin = fixture / 'beammp/Server/BeamNGEarth'
    data = plugin / 'data'
    data.mkdir(exist_ok=True)
    for suffix in ('', '.tmp', '.bad'):
        (data / ('otbt_ledger.json' + suffix)).write_text('private')
    (fixture / 'mod/beamng_earth').mkdir(parents=True)
    (fixture / 'beammp/README.md').write_text('fixture')
    pkg.ROOT = tmp
    pkg.beammp_zip(tmp, 'test')
    with zipfile.ZipFile(fixture / 'BeamNG.Earth-BeamMP-Server-test.zip') as z:
        names = set(z.namelist())
        base = 'Resources/Server/BeamNGEarth/'
        assert base + 'main.lua' in names
        for module in ('economy', 'ledger', 'json'):
            assert base + 'lib/otbt_' + module + '.lua' in names
        assert not any('/data/' in n or 'otbt_ledger.json' in n for n in names)
        assert [n for n in names if n.startswith(base) and '/' not in n[len(base):]] == [base + 'main.lua']
setup = (root / 'beammp/setup_otbt_server.sh').read_text()
assert 'unzip -o -q "$ZIP" -d "$DIR"' in setup
assert 'lib/otbt_ledger.lua' in setup
print('BeamMP package layout and data exclusion verified')
