// Windows adapter for the Linux monitor: JSON-RPC, isolated profile, keyring only.
const fs = require('node:fs');
const path = require('node:path');
const {spawn} = require('node:child_process');
const readline = require('node:readline');
const home = path.join(process.env.LOCALAPPDATA, 'CodexTokenMonitor', 'profile');
const settingsFile = path.join(home, 'widget-settings.json');
function settings() { try { return JSON.parse(fs.readFileSync(settingsFile, 'utf8')); } catch { return {}; } }
function save(configured) { fs.writeFileSync(settingsFile, JSON.stringify({configured}), 'utf8'); }
function executable() {
  const root = path.join(process.env.APPDATA, 'npm', 'node_modules', '@openai', 'codex');
  for (const arch of ['x64', 'arm64']) {
    const triple = arch === 'x64' ? 'x86_64-pc-windows-msvc' : 'aarch64-pc-windows-msvc';
    for (const p of [path.join(root, 'node_modules', '@openai', `codex-win32-${arch}`, 'vendor', triple, 'bin', 'codex.exe'), path.join(root, 'vendor', triple, 'codex', 'codex.exe')]) {
      if (fs.existsSync(p)) return p;
    }
  }
  for (const folder of (process.env.PATH || '').split(path.delimiter)) {
    const p = path.join(folder, 'codex.exe');
    if (fs.existsSync(p)) return p;
  }
  throw new Error('Codex CLI não encontrado. Instale com npm install -g @openai/codex.');
}
function environment() {
  const env = {};
  for (const key of ['PATH', 'SystemRoot', 'WINDIR', 'TEMP', 'TMP', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'HOMEDRIVE', 'HOMEPATH']) {
    if (process.env[key]) env[key] = process.env[key];
  }
  return {...env, CODEX_HOME: home, RUST_LOG: 'off', OTEL_SDK_DISABLED: 'true'};
}
class Client {
  constructor() { this.pending = new Map(); this.sequence = 0; }
  async start() {
    this.proc = spawn(executable(), ['app-server', '--listen', 'stdio://', '-c', 'cli_auth_credentials_store="keyring"', '-c', 'analytics.enabled=false'], {env: environment(), cwd: home, windowsHide: true, stdio: ['pipe', 'pipe', 'ignore']});
    this.proc.on('error', () => this.fail());
    this.proc.on('exit', () => this.fail());
    this.proc.stdin.on('error', () => this.fail());
    this.lines = readline.createInterface({input: this.proc.stdout});
    this.lines.on('line', line => {
      let msg; try { msg = JSON.parse(line); } catch { return; }
      if (msg.method) {
        if (msg.id !== undefined) this.send({id: msg.id, error: {code: -32601, message: 'Read-only monitor'}});
        return;
      }
      const call = this.pending.get(msg.id);
      if (!call) return;
      clearTimeout(call.timer); this.pending.delete(msg.id);
      if (msg.error) call.reject(new Error([401,403].includes(msg.error.code) ? 'Sessão expirada. Entre novamente.' : 'Consulta indisponível nesta versão ou plano.'));
      else call.resolve(msg.result || {});
    });
    await this.request('initialize', {clientInfo: {name: 'windows_token_monitor', title: 'Codex Token Monitor', version: '1.0.0'}});
    this.send({method: 'initialized', params: {}});
  }
  send(msg) { if (this.proc && !this.proc.stdin.destroyed) this.proc.stdin.write(JSON.stringify(msg) + '\n'); }
  request(method, params) {
    return new Promise((resolve, reject) => {
      const id = ++this.sequence;
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error('Tempo limite de consulta. Verifique a conexão.')); }, 15000);
      this.pending.set(id, {resolve, reject, timer});
      this.send({id, method, ...(params === undefined ? {} : {params})});
    });
  }
  fail() { for (const call of this.pending.values()) { clearTimeout(call.timer); call.reject(new Error('Conexão com o Codex encerrada.')); } this.pending.clear(); }
  close() { this.fail(); this.lines?.close(); this.proc?.kill(); }
}
async function openBrowser(authUrl, launch = spawn) {
  const url = new URL(authUrl);
  if (url.protocol !== 'https:' || !['auth.openai.com', 'chatgpt.com'].includes(url.hostname) || url.username || url.password) {
    throw new Error('Origem de autenticação inválida.');
  }
  // Use the Windows URL association. Pass the ephemeral URL through the child
  // environment, never shell code or command-line arguments (OAuth state).
  const script = "$ErrorActionPreference='Stop'; try { $info=New-Object Diagnostics.ProcessStartInfo; $info.FileName=$env:CODEX_WIDGET_LOGIN_URL; $info.UseShellExecute=$true; [void][Diagnostics.Process]::Start($info); exit 0 } catch { exit 1 }";
  await new Promise((resolve, reject) => {
    const child = launch(path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
      ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')],
      {windowsHide: true, stdio: 'ignore', env: {...environment(), CODEX_WIDGET_LOGIN_URL: url.href}});
    const fail = () => reject(new Error('Não foi possível abrir o navegador padrão. Verifique o aplicativo associado a HTTPS no Windows.'));
    child.once('error', fail);
    child.once('exit', code => code === 0 ? resolve() : fail());
  });
}
function metrics(limits, usage = {}) {
  const buckets = limits.rateLimitsByLimitId || {codex: limits.rateLimits || {}};
  const rows = [];
  for (const [id, bucket] of Object.entries(buckets)) {
    for (const slot of ['primary', 'secondary']) {
      const w = bucket?.[slot]; if (!w) continue;
      const minutes = w.windowDurationMins;
      const title = minutes === 10080 ? 'Semanal' : minutes ? `${minutes / 60}h` : slot;
      const remaining = typeof w.usedPercent === 'number' && Number.isFinite(w.usedPercent) ? Math.max(0, Math.min(100, 100 - w.usedPercent)) : null;
      rows.push({title: `${bucket.limitName || id} · ${title}`, bucket_id: id, slot, window_minutes: minutes, remaining, resets: w.resetsAt ? new Date(w.resetsAt * 1000).toLocaleString('pt-BR') : 'Indisponível'});
    }
  }
  const daily = [...(usage.dailyUsageBuckets || [])].sort((a,b) => a.startDate.localeCompare(b.startDate)).at(-1);
  const format = n => typeof n === 'number' ? n.toLocaleString('pt-BR') : 'Indisponível';
  return {quotas: rows, lifetime_tokens: format(usage.summary?.lifetimeTokens), daily_tokens: format(daily?.tokens), daily_date: daily?.startDate || 'Nenhum dia informado'};
}
async function run(action) {
  fs.mkdirSync(home, {recursive: true});
  if (action === 'read' && !settings().configured) return {configured: false, errors: ['Credenciais não configuradas. Clique em Entrar.']};
  const client = new Client();
  let loginId;
  try {
    await client.start();
    if (action === 'logout') {
      await client.request('account/logout'); save(false);
      return {configured: false, errors: ['Credenciais removidas.']};
    }
    if (action === 'login') {
      const login = await client.request('account/login/start', {type: 'chatgpt'});
      loginId = login.loginId;
      await openBrowser(login.authUrl);
      const deadline = Date.now() + 180000;
      let account;
      while (Date.now() < deadline) {
        account = (await client.request('account/read', {refreshToken: false})).account;
        if (account?.type === 'chatgpt') break;
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
      if (account?.type !== 'chatgpt') throw new Error('Login expirado. Tente novamente.');
      save(true); loginId = null;
    }
    const account = (await client.request('account/read', {refreshToken: false})).account;
    if (!account || account.type !== 'chatgpt') { save(false); return {configured: false, errors: ['Entre com sua conta ChatGPT.']}; }
    const errors = []; let limits = {}, usage = {};
    try { limits = await client.request('account/rateLimits/read'); } catch(e) { errors.push(e.message); }
    try { usage = await client.request('account/usage/read'); } catch(e) { errors.push(e.message); }
    return {configured: true, plan: account.planType || 'não informado', sampled_at: new Date().toLocaleString('pt-BR'), ...metrics(limits, usage), errors};
  } finally {
    if (loginId) { try { await client.request('account/login/cancel', {loginId}); await client.request('account/logout'); } catch {} save(false); }
    client.close();
  }
}
module.exports = {metrics, environment, Client, openBrowser};
if (require.main === module) {
  const action = process.argv[2] || 'read';
  if (!['read','login','logout'].includes(action)) process.exit(1);
  run(action).then(result => console.log(JSON.stringify(result))).catch(e => {
    // Only our fixed messages escape; never include subprocess responses or credentials.
    const known = /^(Codex CLI não encontrado|Sessão expirada|Consulta indisponível|Tempo limite|Conexão com o Codex|Origem de autenticação inválida|Login expirado|Não foi possível abrir o navegador padrão)/;
    console.log(JSON.stringify({configured: !!settings().configured, errors: [known.test(e.message) ? e.message : 'Não foi possível consultar o Codex ou acessar o cofre do Windows.']}));
  });
}
