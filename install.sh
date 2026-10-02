#!/usr/bin/env bash
set -euo pipefail
command -v kpackagetool6 >/dev/null || { echo 'KDE Plasma 6 e kpackagetool6 são necessários.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3 é necessário.' >&2; exit 1; }
python3 -c 'import PySide6' >/dev/null 2>&1 || { echo 'PySide6 é necessário (Fedora: python3-pyside6).' >&2; exit 1; }
command -v codex >/dev/null || { echo 'Instale o Codex CLI e adicione-o ao PATH.' >&2; exit 1; }
command -v xdg-open >/dev/null || { echo 'xdg-open é necessário para o login no navegador.' >&2; exit 1; }
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
widget_id=io.github.poajefersonld1983.codex-token-monitor
if kpackagetool6 --type Plasma/Applet --show "$widget_id" >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "$project_dir/package"
else
    kpackagetool6 --type Plasma/Applet --install "$project_dir/package"
fi
printf '%s\n' 'Adicione Codex Token Monitor ao painel ou desktop.' 'Configure suas próprias credenciais no botão Configurar do widget.'
