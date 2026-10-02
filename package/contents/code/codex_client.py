#!/usr/bin/python3
"""Monitor de uso da conta Codex/ChatGPT. Consultas somente de leitura."""
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import time
from datetime import datetime
from storage import environment, codex_home, settings, secure_files

INTERVAL = 5
DOCS = "https://learn.chatgpt.com/docs/app-server"


class RpcError(RuntimeError):
    pass


class CodexClient:
    def __init__(self, executable=None, timeout=15):
        self.executable = executable or shutil.which("codex") or str(Path.home() / ".local/bin/codex")
        self.timeout = timeout
        self.process = None
        self.buffer = b""
        self.sequence = 0

    def start(self):
        self.close()
        if not Path(self.executable).is_file():
            raise RpcError("Codex não encontrado. Instale o Codex CLI para configurar sua conta.")
        self.buffer = b""
        self.process = subprocess.Popen(
            [self.executable, "app-server", "--stdio", "-c",
             'cli_auth_credentials_store="' + ("file" if settings().get("store") == "file" else "keyring") + '"',
             "-c", "analytics.enabled=false"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, bufsize=0, cwd=codex_home(), env=environment(),
        )
        self.request("initialize", {"clientInfo": {
            "name": "plasma_token_monitor", "title": "Codex Token Monitor", "version": "1.0.0",
        }})
        self.send({"method": "initialized", "params": {}})

    def send(self, message):
        if not self.process or self.process.poll() is not None:
            raise RpcError("Conexão com o Codex encerrada.")
        try:
            self.process.stdin.write((json.dumps(message) + "\n").encode())
            self.process.stdin.flush()
        except (OSError, ValueError) as exc:
            raise RpcError("Não foi possível consultar o Codex.") from exc

    def request(self, method, params=None):
        self.sequence += 1
        request_id = self.sequence
        message = {"id": request_id, "method": method}
        if params is not None:
            message["params"] = params
        self.send(message)
        deadline = time.monotonic() + self.timeout
        process = self.process
        while time.monotonic() < deadline:
            if b"\n" not in self.buffer:
                ready, _, _ = select.select([process.stdout], [], [], max(0, deadline - time.monotonic()))
                if not ready:
                    break
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    raise RpcError("Conexão com o Codex encerrada.")
                self.buffer += chunk
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                try:
                    reply = json.loads(line)
                except (ValueError, UnicodeDecodeError):
                    continue
                if not isinstance(reply, dict):
                    continue
                if "method" in reply:
                    if "id" in reply:
                        self.send({"id": reply["id"], "error": {
                            "code": -32601, "message": "Read-only monitor: method not supported",
                        }})
                    continue
                if reply.get("id") != request_id:
                    continue
                if "error" in reply:
                    code = reply["error"].get("code", "desconhecido")
                    raise RpcError("Sessão expirada. Faça login novamente." if code in (401, 403)
                                   else "Consulta indisponível nesta versão do Codex ou neste plano.")
                return reply.get("result", {})
        self.close()
        raise RpcError("Tempo limite de consulta. Verifique a conexão com a internet.")

    def snapshot(self):
        if not self.process or self.process.poll() is not None:
            self.start()
        account = self.request("account/read", {"refreshToken": False}).get("account")
        if not account:
            raise RpcError("Credenciais não configuradas.")
        if account.get("type") == "apiKey":
            raise RpcError("Este painel precisa de uma conta ChatGPT. Configure pelo widget.")
        result = {"account": account, "errors": []}
        for name, method in [("limits", "account/rateLimits/read"), ("usage", "account/usage/read")]:
            try:
                result[name] = self.request(method)
            except RpcError as exc:
                result["errors"].append(str(exc))
        result["checked_at"] = datetime.now().astimezone().isoformat()
        return result

    def close(self):
        process, self.process = self.process, None
        if process:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            secure_files()
            for stream in [process.stdin, process.stdout]:
                if stream:
                    stream.close()


def number(value):
    return "Indisponível" if value is None else f"{int(value):,}".replace(",", ".")


def quota_rows(result):
    buckets = result.get("rateLimitsByLimitId") or {}
    if not buckets and result.get("rateLimits"):
        bucket = result["rateLimits"]
        buckets = {bucket.get("limitId") or "codex": bucket}
    rows = []
    for key, bucket in buckets.items():
        name = bucket.get("limitName") or key
        for slot, fallback in [("primary", "Principal"), ("secondary", "Secundário")]:
            window = bucket.get(slot)
            if not window:
                continue
            minutes = window.get("windowDurationMins")
            duration = "Semanal" if minutes == 10080 else (
                f"{minutes // 60} horas" if minutes and minutes % 60 == 0 else
                f"{minutes} minutos" if minutes else fallback
            )
            used = window.get("usedPercent")
            remaining = None if used is None else max(0, min(100, 100 - float(used)))
            reset = window.get("resetsAt")
            resets = datetime.fromtimestamp(reset).astimezone().strftime("%d/%m/%Y às %H:%M:%S") if reset else "Indisponível"
            rows.append({"title": f"{name} · {duration}", "remaining": remaining,
                         "used": used, "resets": resets})
    return rows
