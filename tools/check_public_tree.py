#!/usr/bin/env python3
"""Static publication gate. Reports locations, NEVER matched secret values."""
import argparse
import ast
from pathlib import Path
import re
import zipfile

KEYWORDS = re.compile(r'login|username|\buser\b|email|e-mail|password|passwd|senha|secret|client_secret|token|access_token|refresh_token|session|cookie|authorization|bearer|OPENAI_API_KEY|sk-|api_key|apikey', re.I)
PATTERNS = [re.compile(r'sk-[A-Za-z0-9_-]{16,}'),
            re.compile(r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'),
            re.compile(r'https?://[^\s/:]+:[^\s/@]+@'),
            re.compile(r'https?://[^\s]+[?&](?:password|access_token|refresh_token|api_key|session|cookie)=[^\s&]+', re.I)]
FORBIDDEN = {'auth.json', 'credentials.json', 'cookies.json', 'session.json', 'token.json',
             'settings.json', 'status.json', 'widget.lock', 'configure.lock'}
SECRET_NAMES = re.compile(r'^(?:password|passwd|senha|username|email|access_token|refresh_token|session_token|api_key|apikey|client_secret|cookie|authorization)$', re.I)


def inspect(name, content):
    text = content.decode('utf-8', errors='replace')
    problems = []
    hits = [str(n) for n, line in enumerate(text.splitlines(), 1) if KEYWORDS.search(line)]
    if hits:
        print(f'REVIEW {name}: keyword lines {",".join(hits)}')
    for n, line in enumerate(text.splitlines(), 1):
        if any(pattern.search(line) for pattern in PATTERNS):
            problems.append(f'{name}:{n}: potential secret [MASKED]')
    if name.endswith('.py'):
        try:
            for node in ast.walk(ast.parse(text)):
                if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str) and node.value.value:
                    if any(isinstance(target, ast.Name) and SECRET_NAMES.match(target.id) for target in node.targets):
                        problems.append(f'{name}:{node.lineno}: authentication literal [MASKED]')
        except SyntaxError:
            problems.append(f'{name}: invalid Python')
    return problems


def check(root):
    problems = []
    for path in sorted(root.rglob('*')):
        name = str(path.relative_to(root))
        if '.git' in path.relative_to(root).parts:
            continue
        if path.is_symlink():
            problems.append(f'{name}: symlink cannot be included')
        elif path.is_file():
            if path.name in FORBIDDEN or path.suffix in {'.log', '.db', '.sqlite', '.sqlite3', '.key', '.pem', '.pyc'} or path.name.startswith('.env'):
                problems.append(f'{name}: private/generated file cannot be included')
            if zipfile.is_zipfile(path):
                with zipfile.ZipFile(path) as archive:
                    for member in archive.namelist():
                        if not member.endswith('/'):
                            if Path(member).name in FORBIDDEN:
                                problems.append(f'{name}!{member}: private file in archive')
                            problems.extend(inspect(name + '!' + member, archive.read(member)))
            else:
                problems.extend(inspect(name, path.read_bytes()))
    for problem in problems:
        print('FAIL ' + problem)
    print(f'{"FAIL" if problems else "PASS"}: {len(problems)} prohibited files/potential secrets. Keyword hits require human review.')
    return bool(problems)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path, nargs='?', default=Path(__file__).resolve().parents[1])
    raise SystemExit(check(parser.parse_args().root))
