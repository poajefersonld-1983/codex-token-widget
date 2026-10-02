#!/usr/bin/env python3
"""Native configuration dialog. Passwords are entered only on the official site."""
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import time
from urllib.parse import urlsplit
from PySide6.QtCore import QThread, Signal, Qt
from PySide6.QtWidgets import QApplication, QCheckBox, QDialog, QLabel, QPushButton, QVBoxLayout
from codex_client import CodexClient
from storage import atomic_write, codex_home, data_dir, settings, secure_files


def clear_local_auth():
    # This directory belongs exclusively to this widget, not ~/.codex.
    home = codex_home()
    for path in home.iterdir():
        if path.is_symlink() or path.is_file():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)
    (data_dir() / 'status.json').unlink(missing_ok=True)
    previous = settings()
    atomic_write(data_dir() / 'settings.json', {'configured': False, 'store': previous.get('store', 'keyring')})


class AuthWorker(QThread):
    message = Signal(str)
    completed = Signal(bool)

    def __init__(self, action, store):
        super().__init__()
        self.action, self.store = action, store

    def run(self):
        os.umask(0o077)
        client = CodexClient(timeout=10)
        login_id = None
        previous = {}
        success = False
        try:
            with (data_dir() / 'widget.lock').open('a') as lock:
                os.chmod(data_dir() / 'widget.lock', 0o600)
                fcntl.flock(lock, fcntl.LOCK_EX)
                previous = settings()
                # Logout uses the previous store. Never silently change credential stores.
                if self.action == 'logout':
                    if previous.get('configured') or previous.get('store'):
                        client.start()
                        client.request('account/logout')
                    client.close()
                    clear_local_auth()
                    self.message.emit('Credenciais não configuradas.')
                    success = True
                else:
                    if previous.get('configured'):
                        self.message.emit('Remova as credenciais atuais antes de alterar a conta.')
                        return
                    if previous.get('store') and previous['store'] != self.store:
                        # Remove residual expired credentials from their original store first.
                        client.start()
                        client.request('account/logout')
                        client.close()
                        clear_local_auth()
                    atomic_write(data_dir() / 'settings.json', {'configured': False, 'store': self.store})
                    client.start()
                    client.request('account/logout')
                    login = client.request('account/login/start', {'type': 'chatgpt'})
                    login_id = login.get('loginId')
                    url = login.get('authUrl', '')
                    parsed = urlsplit(url)
                    if parsed.scheme != 'https' or parsed.hostname not in {'auth.openai.com', 'chatgpt.com'} or parsed.username or parsed.password:
                        raise RuntimeError('Invalid authentication origin')
                    # URL remains ephemeral; not returned to Plasma, persisted, or logged.
                    subprocess.Popen(['xdg-open', url], stdin=subprocess.DEVNULL,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    self.message.emit('Conclua o login no navegador. Você pode cancelar aqui.')
                    deadline = time.monotonic() + 180
                    while time.monotonic() < deadline and not self.isInterruptionRequested():
                        account = client.request('account/read', {'refreshToken': False}).get('account')
                        if account and account.get('type') == 'chatgpt':
                            secure_files()
                            atomic_write(data_dir() / 'settings.json', {'configured': True, 'store': self.store})
                            (data_dir() / 'status.json').unlink(missing_ok=True)
                            success = True
                            self.message.emit('Authentication successful')
                            break
                        self.msleep(500)
                    if not success:
                        self.message.emit('Login cancelado ou expirado. Tente novamente.')
        except Exception:
            self.message.emit('Não foi possível autenticar ou acessar o cofre. Verifique o Codex CLI e o cofre do sistema. Nenhum segredo foi exibido.')
        finally:
            if self.action == 'login' and not success:
                try:
                    if login_id:
                        client.request('account/login/cancel', {'loginId': login_id})
                    if client.process:
                        client.request('account/logout')
                except Exception:
                    pass
                # A canceled browser callback must not become an active widget session.
                failed = {'configured': False}
                if login_id:
                    failed['store'] = self.store
                elif previous.get('store'):
                    failed['store'] = previous['store']
                atomic_write(data_dir() / 'settings.json', failed)
                (data_dir() / 'status.json').unlink(missing_ok=True)
            client.close()
            self.completed.emit(success)


class Configuration(QDialog):
    def __init__(self):
        super().__init__()
        self.worker = None
        self.setWindowTitle('Codex Token Monitor — Configuração')
        self.resize(480, 300)
        layout = QVBoxLayout(self)
        explanation = QLabel('Entre com sua própria conta ChatGPT no navegador oficial.\n'
                             'Usuário e senha são informados somente nesse site.\n'
                             'O widget não recebe nem salva sua senha.\n'
                             'A sessão deste widget é separada do Codex CLI pessoal.')
        explanation.setWordWrap(True)
        layout.addWidget(explanation)
        self.status = QLabel()
        self.status.setWordWrap(True)
        self.status.setTextFormat(Qt.PlainText)
        layout.addWidget(self.status)
        self.file_store = QCheckBox('Usar arquivo privado (600) em vez do cofre do sistema')
        self.file_store.setChecked(settings().get('store') == 'file')
        layout.addWidget(self.file_store)
        warning = QLabel('Arquivo privado é uma alternativa temporária: não é criptografado.\n'
                         'Local: ' + str(data_dir()) + '\n'
                         'Nunca envie arquivos de autenticação em relatórios de bugs.')
        warning.setWordWrap(True)
        warning.setTextFormat(Qt.PlainText)
        layout.addWidget(warning)
        self.login = QPushButton('Entrar com ChatGPT')
        self.login.clicked.connect(lambda: self.start('login'))
        layout.addWidget(self.login)
        self.logout = QPushButton('Remover credenciais')
        self.logout.clicked.connect(lambda: self.start('logout'))
        layout.addWidget(self.logout)
        self.close_button = QPushButton('Fechar')
        self.close_button.clicked.connect(self.close)
        layout.addWidget(self.close_button)
        self.update_controls()

    def update_controls(self):
        configured = bool(settings().get('configured'))
        self.login.setEnabled(not configured)
        self.logout.setEnabled(bool(settings().get('store')))
        self.file_store.setEnabled(not configured)
        self.close_button.setText('Fechar')
        self.status.setText('Conta configurada.' if configured else 'Credenciais não configuradas.')

    def start(self, action):
        self.login.setEnabled(False)
        self.logout.setEnabled(False)
        self.file_store.setEnabled(False)
        self.close_button.setText('Cancelar')
        self.worker = AuthWorker(action, 'file' if self.file_store.isChecked() else 'keyring')
        self.worker.message.connect(self.status.setText)
        self.worker.completed.connect(self.finished_auth)
        self.worker.start()

    def finished_auth(self, success):
        text = self.status.text()
        self.worker.wait()
        self.worker = None
        self.update_controls()
        self.status.setText(text)

    def closeEvent(self, event):
        if self.worker and self.worker.isRunning():
            self.worker.requestInterruption()
            self.status.setText('Cancelando o login com segurança…')
            event.ignore()
        else:
            event.accept()


def main():
    os.umask(0o077)
    with (data_dir() / 'configure.lock').open('a') as lock:
        os.chmod(data_dir() / 'configure.lock', 0o600)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        app = QApplication([])
        dialog = Configuration()
        dialog.show()
        app.exec()


if __name__ == '__main__':
    main()
