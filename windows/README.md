# Codex Token Monitor para Windows 11

Versão nativa da bandeja do sistema do monitor KDE, com PowerShell/Windows Forms e Node.js, sem Python ou KDE.

Requisitos: Windows 11, Node.js e Codex CLI (`npm install -g @openai/codex`).

Instale nesta pasta com `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`.
O instalador cria um atalho na área de trabalho e abre o monitor sem console.
Clique no ícone para abrir o painel, depois em **Entrar com ChatGPT** e conclua o login no navegador.
O menu do botão direito permite atualizar ou sair. Fechar o painel mantém o monitor na bandeja.

O texto `5H 82% | 7D 97%` aparece sobre a barra, à esquerda da área de ícones do sistema. Não há ícones do monitor na bandeja. Clique no texto para abrir os detalhes; botão direito para atualizar ou sair. O indicador acompanha a posição da barra e mantém o sombreamento ao passar o mouse. Não reserva espaço nativo no Explorer e pode disputar espaço com aplicativos se a barra estiver cheia.
Os valores completos, datas de renovação e tokens aparecem no painel. Métricas não fornecidas pelo plano/CLI aparecem indisponíveis.
As opções de fonte e cor se aplicam ao indicador e aos limites apresentados no painel.
Atualização automática 15 segundos após cada consulta concluída, sem sobrepor requisições. Uma consulta com falha limpa os valores anteriores.
O painel inclui três tamanhos de fonte (9, 10,8 e 12 pt) e nove cores prontas: verde, azul, branco, amarelo, laranja, vermelho, roxo, rosa e ciano. **Escolher outra cor** abre o seletor do Windows. As alterações aparecem imediatamente e são salvas em `profile/appearance.json`, sem alterar a autenticação.

Para deixar o ícone visível perto do relógio, arraste-o do menu de ícones ocultos para a bandeja.
Para iniciar com o Windows, copie o atalho para a pasta aberta por `shell:startup` (opcional).

O perfil fica em `%LOCALAPPDATA%\CodexTokenMonitor\profile`, com ACL privada, e usa exclusivamente o cofre de credenciais do Codex (`keyring`). Não importa a sessão pessoal de `%USERPROFILE%\.codex`. Nunca envie a pasta do perfil em relatórios.
Use **Remover credenciais** antes de desinstalar. Depois escolha **Sair**, remova o atalho e a pasta `%LOCALAPPDATA%\CodexTokenMonitor`.
O login real precisa ser concluído pelo titular da conta; testes offline não comprovam o acesso ao plano.

Validação: `node --test .\backend.test.cjs` e `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\monitor.ps1 -SmokeTest`.

Antes de publicar, na raiz do projeto execute `node tools/check_public_tree.cjs`. O verificador informa somente arquivos/linhas, sem imprimir valores suspeitos. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_windows_package.ps1` gera um ZIP com lista explícita de arquivos públicos; nunca copia o aplicativo instalado nem o perfil privado. O pacote fica em `dist` e não deve ser incluído no commit.

Protocolo: https://learn.chatgpt.com/docs/app-server
