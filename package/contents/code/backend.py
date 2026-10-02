#!/usr/bin/env python3
"""Returns only usage metrics and fixed, safe errors to Plasma."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from codex_client import CodexClient, RpcError, number, quota_rows
from storage import data_dir, settings, read_json, atomic_write

INTERVAL = 30
EMPTY = {'configured': False, 'loading': False, 'errors': ['Credenciais não configuradas.']}


def merge_snapshot(snapshot):
    now = time.time()
    plan = snapshot['account'].get('planType')
    known_plans = {'free', 'plus', 'pro', 'team', 'business', 'enterprise', 'edu'}
    result = {'configured': True, 'loading': False, 'sampled_at': now,
              'plan': plan if plan in known_plans else 'não informado', 'errors': snapshot['errors']}
    if 'limits' in snapshot:
        limits = snapshot['limits']
        result['quotas'] = quota_rows(limits)
        result['limits_checked_at'] = now
        bucket = limits.get('rateLimits') or {}
        buckets = limits.get('rateLimitsByLimitId') or {'codex': bucket}
        selected = buckets.get('codex') or next(iter(buckets.values()), {})
        for slot in ('primary', 'secondary'):
            window = selected.get(slot) or {}
            used, minutes = window.get('usedPercent'), window.get('windowDurationMins')
            remaining = None if used is None else max(0, min(100, 100 - float(used)))
            if minutes == 10080:
                result['weekly_remaining'] = remaining
            elif slot == 'primary':
                result['short_remaining'] = remaining
                result['short_label'] = f'{minutes // 60}h' if minutes and minutes % 60 == 0 else 'Uso'
    if 'usage' in snapshot:
        usage = snapshot['usage']
        summary = usage.get('summary') or {}
        daily = usage.get('dailyUsageBuckets') or []
        latest = max(daily, key=lambda item: item['startDate']) if daily else {}
        result.update(lifetime_tokens=number(summary.get('lifetimeTokens')),
                      daily_tokens=number(latest.get('tokens')),
                      daily_date=latest.get('startDate') or 'Nenhum dia informado')
    return result


def read_status(force=False):
    directory = data_dir()
    if not settings().get('configured'):
        return dict(EMPTY)
    with (directory / 'widget.lock').open('a') as lock:
        os.chmod(directory / 'widget.lock', 0o600)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {'configured': True, 'loading': True, 'errors': []}
        if not settings().get('configured'):
            return dict(EMPTY)
        cached = read_json(directory / 'status.json')
        if not force and time.time() - cached.get('sampled_at', 0) < INTERVAL:
            return cached
        client = CodexClient()
        try:
            result = merge_snapshot(client.snapshot())
        except RpcError as error:
            # RpcError messages are constants; no raw server responses are exposed.
            message = str(error)
            if message in ('Credenciais não configuradas.', 'Sessão expirada. Faça login novamente.'):
                config = settings()
                config['configured'] = False
                atomic_write(directory / 'settings.json', config)
                result = dict(EMPTY, errors=[message])
            else:
                result = {'configured': True, 'loading': False, 'errors': [message]}
        except Exception:
            result = {'configured': True, 'loading': False, 'errors': ['Não foi possível atualizar os dados.']}
        finally:
            client.close()
        result['sampled_at'] = time.time()
        atomic_write(directory / 'status.json', result)
        return result


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--read', action='store_true')
    parser.add_argument('--refresh', action='store_true')
    parser.add_argument('--configure', action='store_true')
    args = parser.parse_args()
    if args.configure:
        subprocess.Popen([sys.executable, "-B", str(Path(__file__).with_name('configure.py'))],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    else:
        try:
            result = read_status(args.refresh)
        except Exception:
            result = dict(EMPTY, errors=['Não foi possível acessar a configuração privada.'])
        print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
