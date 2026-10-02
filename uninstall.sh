#!/usr/bin/env bash
set -euo pipefail
command -v kpackagetool6 >/dev/null || { echo 'kpackagetool6 não encontrado.' >&2; exit 1; }
kpackagetool6 --type Plasma/Applet --remove io.github.poajefersonld1983.codex-token-monitor
printf '%s\n' 'Widget removido. Seus dados pessoais foram preservados.' 'Use Remover credenciais antes de desinstalar para limpar a autenticação do widget.' 'Configuração privada: ${XDG_CONFIG_HOME:-~/.config}/codex-token-widget-public/' 'O cofre do sistema também pode conter a sessão, conforme a opção de armazenamento escolhida.'
