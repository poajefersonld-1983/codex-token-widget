# Testes antes da publicação

## Verificações automatizadas

Execute os comandos de desenvolvimento do README. Eles não usam conta real. O teste de logout usa somente sessão sintética e verifica que estado e arquivos de autenticação do widget são removidos. O scanner mostra caminhos e números de linha, nunca valores de possíveis segredos.

## Validação manual obrigatória

Use uma conta de teste própria, exclusivamente pelo diálogo novo. Não envie credenciais ao assistente nem salve capturas contendo login, códigos de autorização ou dados pessoais.

1. Em ambiente sem perfil público anterior, instale com `./install.sh` e abra o widget.
2. Confirme **Credenciais não configuradas.**, **Configurar** e ausência de tentativas de login.
3. Abra Configurar, mantenha o cofre padrão, clique Entrar com ChatGPT e conclua o login no site oficial.
4. Confirme sucesso, atualização dos limites e dados disponíveis. Token acumulado indisponível pode representar ausência da RPC na versão do Codex.
5. Feche e reabra o widget; confirme persistência e métricas sem exibir identificadores da conta.
6. Reinicie o Plasma em momento apropriado, preservando trabalhos abertos; confirme persistência da sessão e atualização.
7. Use Remover credenciais. Confirme ausência da sessão no cofre usado, limpeza do perfil exclusivo e retorno ao estado inicial.
8. Feche/reabra o widget e confirme que nenhuma autenticação ocorre automaticamente.
9. Em ambiente separado, repita com a alternativa de arquivo privado. Confirme `700` nos diretórios e `600` nos arquivos; após logout, `codex/auth.json` deve estar ausente.
10. Teste cancelamento, cofre bloqueado, ausência de internet e sessão revogada. Nenhuma mensagem pode expor respostas, cookies, headers ou segredos.
11. Execute desinstalação; confirme que só o identificador público é removido e os dados pessoais restantes são preservados.

Não marque etapas como aprovadas sem executá-las. Nenhuma conta ou credencial de desenvolvimento deve entrar no pacote, mesmo para teste. Não reinicie o Plasma apenas para substituir a instalação antiga: ambos os identificadores podem coexistir.
