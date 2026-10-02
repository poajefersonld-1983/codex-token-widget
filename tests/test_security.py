"""Offline tests: no account credentials, network or user's existing profile."""
import importlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

CODE = Path(__file__).resolve().parents[1] / 'package/contents/code'
sys.path.insert(0, str(CODE))
import storage
import backend


class SecurityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = patch.dict(os.environ, {'XDG_CONFIG_HOME': self.temp.name,
            'CODEX_HOME': '/must-not-use', 'OPENAI_API_KEY': 'SYNTHETIC', 'CODEX_ACCESS_TOKEN': 'SYNTHETIC'})
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_fresh_run_never_starts_client(self):
        with patch.object(backend, 'CodexClient') as client:
            for _ in range(3):
                self.assertEqual(backend.read_status()['errors'], ['Credenciais não configuradas.'])
            client.assert_not_called()

    def test_environment_and_permissions(self):
        env = storage.environment()
        self.assertNotEqual(env['CODEX_HOME'], '/must-not-use')
        for key in ('OPENAI_API_KEY', 'CODEX_ACCESS_TOKEN'):
            self.assertNotIn(key, env)
        directory = storage.data_dir()
        storage.atomic_write(directory / 'settings.json', {'configured': False})
        self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual((directory / 'settings.json').stat().st_mode & 0o777, 0o600)

    def test_expired_session_blocks_retries_and_clears_metrics(self):
        storage.atomic_write(storage.data_dir() / 'settings.json', {'configured': True})
        with patch.object(backend, 'CodexClient') as factory:
            factory.return_value.snapshot.side_effect = backend.RpcError('Sessão expirada. Faça login novamente.')
            self.assertFalse(backend.read_status(True)['configured'])
            backend.read_status(True)
            self.assertEqual(factory.call_count, 1)
        self.assertNotIn('quotas', storage.read_json(storage.data_dir() / 'status.json'))

    def test_server_error_is_not_exposed(self):
        storage.atomic_write(storage.data_dir() / 'settings.json', {'configured': True})
        with patch.object(backend, 'CodexClient') as factory:
            factory.return_value.snapshot.side_effect = ValueError('SYNTHETIC-PRIVATE-RESPONSE')
            self.assertNotIn('SYNTHETIC-PRIVATE-RESPONSE', json.dumps(backend.read_status(True)))

    def test_old_profile_is_not_created_or_read(self):
        output = subprocess.check_output([sys.executable, str(CODE / 'backend.py'), '--read'], text=True)
        self.assertFalse(json.loads(output)['configured'])
        self.assertFalse((Path(self.temp.name) / 'codex-token-widget-public/codex').exists())

class AuthenticationLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        environment = patch.dict(os.environ, {'XDG_CONFIG_HOME': self.temp.name})
        environment.start()
        self.addCleanup(environment.stop)
        import configure
        self.configure = configure

    def test_login_logout_and_no_authorization_url_persisted(self):
        with patch.object(self.configure, 'CodexClient') as factory, patch.object(self.configure.subprocess, 'Popen') as browser:
            client = factory.return_value
            def reply(method, params=None):
                if method == 'account/login/start':
                    return {'loginId': 'SYNTHETIC', 'authUrl': 'https://auth.openai.com/authorize?state=SYNTHETIC'}
                if method == 'account/read':
                    return {'account': {'type': 'chatgpt'}}
                return {}
            client.request.side_effect = reply
            self.configure.AuthWorker('login', 'file').run()
            self.assertTrue(storage.settings()['configured'])
            browser.assert_called_once()
            content = ''.join(p.read_text() for p in storage.data_dir().rglob('*.json'))
            self.assertNotIn('SYNTHETIC', content)
            self.assertNotIn('authUrl', content)
            # Synthetic private session to verify cleanup, never a real credential.
            storage.atomic_write(storage.codex_home() / 'auth.json', {'test': 'SYNTHETIC'})
            self.configure.AuthWorker('logout', 'file').run()
            self.assertFalse(storage.settings()['configured'])
            self.assertFalse((storage.codex_home() / 'auth.json').exists())
            self.assertFalse(backend.read_status()['configured'])

    def test_login_failure_has_fixed_message_and_no_active_session(self):
        messages = []
        with patch.object(self.configure, 'CodexClient') as factory:
            factory.return_value.start.side_effect = RuntimeError('SYNTHETIC-PRIVATE-ERROR')
            worker = self.configure.AuthWorker('login', 'keyring')
            worker.message.connect(messages.append)
            worker.run()
        self.assertFalse(storage.settings()['configured'])
        self.assertNotIn('SYNTHETIC-PRIVATE-ERROR', ''.join(messages))
        self.assertNotIn('store', storage.settings())


if __name__ == '__main__':
    unittest.main()
