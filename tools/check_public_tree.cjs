// Publication gate for source trees, including Windows. Never prints secret values.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(process.argv[2] || path.join(__dirname, '..'));
const forbidden = /^(?:auth(?:\.json.*)?|credentials.*|secrets?.*|cookies?\.json.*|session\.json.*|token\.json.*|settings\.json.*|status\.json.*|appearance\.json.*|widget-settings\.json.*|language-bar-before\.json|\.env(?:\..*)?)$/i;
const privateFolders = new Set(['.codex','profile','profiles','codex','state','backups']);
const patterns = [
  /sk-[A-Za-z0-9_-]{16,}/,
  /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/,
  /(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})/,
  /https?:\/\/[^\s/:]+:[^\s/@]+@/,
  /https?:\/\/[^\s]+[?&](?:password|access_token|refresh_token|api_key|session|cookie)=[^\s&]+/i,
];
const issues = [];
let checked = 0;
function checkDirectory(directory) {
  for (const item of fs.readdirSync(directory, {withFileTypes:true})) {
    if (['.git','dist','build','node_modules'].includes(item.name)) continue;
    const full = path.join(directory,item.name), relative = path.relative(root,full);
    if (item.isSymbolicLink()) { issues.push(`${relative}: symbolic link`); continue; }
    if (item.isDirectory()) {
      if (privateFolders.has(item.name)) issues.push(`${relative}: private profile directory`);
      else checkDirectory(full);
      continue;
    }
    checked++;
    if (forbidden.test(item.name) || /\.(?:log|sqlite3?|db|key|pem|token|credentials|cookie|session|pyc|tmp|bak)$/i.test(item.name)) issues.push(`${relative}: private/generated file`);
    const text = fs.readFileSync(full,'utf8');
    for (const [index,line] of text.split(/\r?\n/).entries()) {
      if (patterns.some(pattern=>pattern.test(line))) issues.push(`${relative}:${index+1}: potential secret [MASKED]`);
    }
  }
}
checkDirectory(root);
for (const issue of issues) console.error(`FAIL ${issue}`);
console.log(`${issues.length ? 'FAIL' : 'PASS'}: ${checked} source files checked; ${issues.length} private files or potential secrets.`);
process.exitCode=issues.length ? 1 : 0;
