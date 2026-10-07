const {test} = require('node:test');
const assert = require('node:assert/strict');
const {metrics, environment, openBrowser} = require('./backend.cjs');
const {EventEmitter} = require('node:events');
test('browser launch uses HTTPS association without embedding OAuth URL in shell code', async () => {
  const url = 'https://auth.openai.com/authorize?state=synthetic&client_id=example';
  await openBrowser(url, (exe, args, opts) => {
    assert.match(exe, /powershell.exe$/);
    assert.equal(opts.env.CODEX_WIDGET_LOGIN_URL, url);
    assert.equal(args.join(' ').includes(url), false);
    const script = Buffer.from(args.at(-1), 'base64').toString('utf16le');
    assert.match(script, /UseShellExecute=\$true/);
    assert.equal(script.includes(url), false);
    const child = new EventEmitter();
    process.nextTick(() => child.emit('exit', 0));
    return child;
  });
});
test('browser launch failure is surfaced and untrusted origins cannot launch', async () => {
  await assert.rejects(openBrowser('https://auth.openai.com/authorize', () => {
    const child = new EventEmitter(); process.nextTick(() => child.emit('exit', 1)); return child;
  }), /Não foi possível abrir o navegador/);
  await assert.rejects(openBrowser('https://example.com/authorize', () => { throw new Error('must not execute'); }), /Origem de autenticação inválida/);
});
test('quota clamp, unknown percent, weekly window and latest token date', () => {
  const m = metrics({rateLimitsByLimitId: {codex: {primary: {usedPercent: 125, windowDurationMins: 300}, secondary: {usedPercent: null, windowDurationMins: 10080}}}}, {summary: {lifetimeTokens: null}, dailyUsageBuckets: [{startDate:'2026-01-02', tokens:1234},{startDate:'2026-01-01',tokens:99}]});
  assert.equal(m.quotas[0].remaining, 0);
  assert.equal(m.quotas[0].bucket_id, 'codex');
  assert.equal(m.quotas[0].slot, 'primary');
  assert.equal(m.quotas[0].window_minutes, 300);
  assert.equal(m.quotas[1].window_minutes, 10080);
  assert.equal(m.quotas[1].remaining, null);
  assert.match(m.quotas[1].title, /Semanal/);
  assert.equal(m.lifetime_tokens, 'Indisponível');
  assert.equal(m.daily_date, '2026-01-02');
  assert.equal(m.daily_tokens, '1.234');
});
test('single-bucket response and missing usage remain usable', () => {
  const m = metrics({rateLimits:{primary:{usedPercent:20}}});
  assert.equal(m.quotas[0].remaining, 80);
  assert.equal(m.daily_tokens, 'Indisponível');
});
test('environment excludes inherited secrets and personal Codex profile', () => {
  process.env.OPENAI_API_KEY = 'synthetic';
  process.env.CODEX_HOME = 'synthetic-personal-profile';
  const env = environment();
  assert.equal(env.OPENAI_API_KEY, undefined);
  assert.notEqual(env.CODEX_HOME, process.env.CODEX_HOME);
  assert.match(env.CODEX_HOME, /CodexTokenMonitor/);
});
