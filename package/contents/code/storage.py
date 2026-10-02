"""Private, isolated storage. Never uses the user's default Codex profile."""
import json
import os
from pathlib import Path
import tempfile


def private_dir(path):
    path = Path(path)
    if path.is_symlink():
        raise OSError('Unsafe storage path')
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.stat().st_uid != os.getuid():
        raise OSError('Unsafe storage owner')
    path.chmod(0o700)
    return path


def data_dir():
    return private_dir(Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'codex-token-widget-public')


def codex_home():
    return private_dir(data_dir() / 'codex')


def read_json(path):
    try:
        if path.is_symlink():
            return {}
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def atomic_write(path, value):
    fd, temporary = tempfile.mkstemp(prefix='.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, ensure_ascii=False)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def settings():
    return read_json(data_dir() / 'settings.json')


def environment():
    # Explicit allowlist: inherited API keys, access tokens and CODEX_HOME are excluded.
    names = ['HOME', 'PATH', 'LANG', 'LC_ALL', 'DISPLAY', 'WAYLAND_DISPLAY',
             'DBUS_SESSION_BUS_ADDRESS', 'XDG_RUNTIME_DIR', 'XDG_CONFIG_HOME',
             'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_CURRENT_DESKTOP']
    result = {key: os.environ[key] for key in names if key in os.environ}
    result.update(CODEX_HOME=str(codex_home()), RUST_LOG='off', OTEL_SDK_DISABLED='true')
    return result


def secure_files():
    for path in codex_home().rglob('*'):
        if not path.is_symlink():
            path.chmod(0o700 if path.is_dir() else 0o600)
