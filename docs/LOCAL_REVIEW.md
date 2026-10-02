# Relatório local de preparação — 2026-10-02

**Resultado: candidato preparado e revisado localmente; não publicado.** Não foi feito push, upload, release, commit ou configuração de remoto Git.

## Preservação

Foi criado backup privado completo do código revisado, instalação funcional original, instalador/pacote original e estado local. O backup fica fora desta árvore, com diretórios `700` e arquivos `600`, e não deve ser publicado.

Os arquivos originais não foram alterados pelo desenvolvimento. O identificador público `io.github.poajefersonld1983.codex-token-monitor` foi instalado separadamente de `local.codex.tokenmonitor`. Nenhum conteúdo do estado antigo foi importado. O instalador público não altera painéis ou configurações pessoais.

## Arquivos criados e adaptados

Adaptados das fontes revisadas: `package/metadata.json`, `package/contents/ui/main.qml`, `package/contents/code/codex_client.py`. O backend foi reescrito em `package/contents/code/backend.py` para bloquear consultas sem conta e evitar reutilização de métricas de outra sessão.

Criados: `storage.py`, `configure.py`, `contents/config/config.qml`, `contents/ui/configAccount.qml`, `.gitignore`, `install.sh`, `uninstall.sh`, README, licença MIT, documentação, screenshots sem informações pessoais, testes offline e ferramentas de auditoria/build. Tudo se encontra na árvore pública nova; as fontes pessoais permanecem separadas.

## Autenticação e armazenamento

O protocolo real do Codex usa OAuth, não recebe usuário/senha via RPC. Foi preparada a interface **Entrar com ChatGPT** e **Remover credenciais**, acessível por **Configurar** e pela configuração nativa do applet. Login/senha são informados somente no site oficial. Não há senha a mascarar dentro do widget nem campos artificiais de usuário/senha.

O mantenedor concluiu login na interface nova e informou sucesso. O padrão efetivamente testado foi `keyring`, o cofre do sistema delegado pelo Codex; não foi criado `auth.json` em texto puro. O perfil exclusivo utiliza `CODEX_HOME=${XDG_CONFIG_HOME:-~/.config}/codex-token-widget-public/codex`, separado de `~/.codex` e do widget antigo. A localização interna exata da entrada depende do backend do cofre.

A alternativa explícita de arquivo usa `codex/auth.json` nesse perfil privado. Arquivos usam `600`, diretórios `700`; não há fallback automático. Configurações não secretas e cache de métricas ficam em `settings.json` e `status.json` na pasta privada principal. Nenhum desses arquivos é distribuído ou versionado.

Mensagens de erro não mostram respostas, headers, URLs temporárias de login ou valores de segredos. A saída de diagnóstico do app-server é descartada, logging Rust e telemetria desativados; não há chamadas de inferência ou envio de prompts.

## Busca por segredos e revisão de Git

- Busca recursiva inicial: 22 arquivos/membros de arquivos ZIP nos caminhos fornecidos. Não foram encontrados valores literais de credenciais nos arquivos do projeto original. O risco identificado era uso implícito da sessão externa do Codex.
- Foram procuradas as palavras indicadas, chaves de autenticação, formatos de API keys/JWT, URLs com credenciais e parâmetros de autenticação.
- Hits de palavras como token, senha e session no código público correspondem a nomes de APIs, funcionalidades, testes sintéticos e documentação. Foram revisados sem imprimir valores privados.
- A árvore nova e os membros do `.plasmoid` passam no scanner: zero arquivos privados proibidos e zero padrões de possíveis segredos encontrados. Isso é uma revisão local, não uma garantia matemática de ausência de todo formato possível de segredo.
- Um cache Python gerado durante os testes foi detectado e removido antes de empacotar. Os comandos do widget agora usam `python3 -B` para não gerar bytecode na pasta do applet.
- Git inicializado do zero em `main`, sem histórico anterior, commits ou remotos. Somente arquivos sanitizados preparados no índice. `dist/` e autenticação ficam ignorados. O diff preparado foi verificado; nenhum conteúdo de autenticação foi copiado para ele.

## Testes executados

| Verificação | Resultado |
| --- | --- |
| Sintaxe Python e Shell | Aprovada |
| Sete testes offline de isolamento, permissões, sessão expirada, erros e logout | Aprovados |
| Instalação, atualização e desinstalação com kpackagetool6 | Aprovadas; widget original preservado |
| Configuração gráfica e categorias QML | Renderizadas sem credenciais |
| Primeira execução no host real `plasmawindowed`, com configuração temporária | Aprovada: mensagem inicial e Configurar; sem autenticação automática |
| Reabertura do host sem conta | Aprovada: permanece no estado vazio |
| Login real pela interface nova | Concluído pelo mantenedor; backend confirmou conta configurada |
| Atualização real de limites e tokens acumulados | Aprovada, sem erros |
| Reinício real de `plasma-plasmashell.service` | Serviço ativo após reinício |
| Persistência da sessão e atualização depois do reinício | Aprovada com keyring |
| Remover credenciais pela ação do botão da interface | Aprovada; sessão exclusiva removida |
| Verificação posterior com account/read | Conta ausente no cofre do perfil exclusivo |
| Estado final | Credenciais não configuradas; sem auth.json e sem cache da conta removida |
| Pacote e árvore pública | Scanner aprovado; nenhum estado pessoal distribuído |

A validação do botão de logout usou o diálogo Qt renderizado em offscreen e sua ação real, não uma sessão mock. Uma tentativa inicial de observar seu sinal no harness perdeu a notificação após descarte do objeto Qt; a remoção ocorreu. A repetição mantendo a referência do worker confirmou sinal de sucesso, mensagem inicial e ausência da conta. Não foi tratado como falha de autenticação nem se expuseram respostas privadas.

O widget público permanece instalado separadamente, sem conta configurada ao fim dos testes. Para utilizá-lo, adicione-o pelo seletor de widgets e conecte novamente sua própria conta.

## Licença e limitações

A metadata original declara MIT, e não foram encontrados avisos ou trechos identificáveis que exigissem GPL. As dependências não são incorporadas ao pacote. A licença MIT foi mantida; a procedência anterior não pode ser comprovada apenas por inspeção. Veja `LICENSING.md`.

O requisito literal de campos de usuário/senha/Mostrar senha foi adaptado para OAuth oficial, pois não existe autenticação correspondente na RPC usada pelo widget. O login funcional pela interface foi validado pelo mantenedor.

O app-server é dependente da versão do Codex e do plano. Foram testados Fedora 44, Plasma 6.7.5 e Codex CLI 0.160.0. Outros ambientes e autenticação real na alternativa de arquivo ainda não foram testados. Testes de revogação remota, cofre bloqueado e indisponibilidade de rede são recomendações adicionais, não resultados executados. Contas do navegador não são encerradas pelo logout do widget.

## Estrutura final

```text
codex-token-widget/
├── .gitignore
├── README.md
├── LICENSE
├── install.sh
├── uninstall.sh
├── package/
│   ├── metadata.json
│   └── contents/
│       ├── code/{backend,codex_client,configure,storage}.py
│       ├── config/config.qml
│       └── ui/{main,configAccount}.qml
├── screenshots/{first-run,configuration}.png
├── docs/{LOCAL_REVIEW,LICENSING,TESTING}.md
├── tests/test_security.py
├── tools/{check_public_tree,build_package}.py
└── dist/Codex-Token-Monitor-1.0.0.plasmoid (ignorado pelo Git)
```

A listagem integral `find … -maxdepth 5 -type f | sort`, incluindo os arquivos internos do Git recém-criado, e `git status --short` constam em `FINAL_COMMANDS.txt`. Relatórios também são públicos e não contêm autenticação.
