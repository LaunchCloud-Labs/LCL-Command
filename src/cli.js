#!/usr/bin/env node
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const https = require('https');
const { spawn } = require('child_process');
const readline = require('readline');

const DEFAULT_ENDPOINT = process.env.LCL_COMMAND_ENDPOINT || 'https://www.launchcloudlabs.com/employment/portal/Employee_Portal/lcl_command_bridge.php';
const CONFIG_DIR = path.join(os.homedir(), '.config', 'lcl-command');
const SESSION_FILE = path.join(CONFIG_DIR, 'session.json');
const PACKAGE_FILE = path.join(__dirname, '..', 'package.json');
const REQUEST_TIMEOUT_MS = 15000;

function ensureConfigDir() {
  fs.mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });
  try {
    fs.chmodSync(CONFIG_DIR, 0o700);
  } catch (_error) {}
}

function loadSession() {
  try {
    return JSON.parse(fs.readFileSync(SESSION_FILE, 'utf8'));
  } catch (_error) {
    return null;
  }
}

function saveSession(data) {
  ensureConfigDir();
  fs.writeFileSync(SESSION_FILE, JSON.stringify(data, null, 2), { mode: 0o600 });
  try {
    fs.chmodSync(SESSION_FILE, 0o600);
  } catch (_error) {}
}

function clearSession() {
  try {
    fs.unlinkSync(SESSION_FILE);
  } catch (_error) {}
}

function getVersion() {
  if (process.env.LCL_COMMAND_VERSION) {
    return process.env.LCL_COMMAND_VERSION;
  }
  try {
    return JSON.parse(fs.readFileSync(PACKAGE_FILE, 'utf8')).version || '0.0.0';
  } catch (_error) {
    return '0.0.0';
  }
}

function parseArgs(argv) {
  const args = argv.slice(2);
  if (args[0] === '--help' || args[0] === '-h') {
    return { command: 'help', flags: {} };
  }
  if (args[0] === '--version' || args[0] === '-v') {
    return { command: 'version', flags: {} };
  }
  const command = args[0] && !args[0].startsWith('-') ? args.shift() : 'help';
  const flags = {};
  for (let i = 0; i < args.length; i += 1) {
    const part = args[i];
    if (part.startsWith('--')) {
      const key = part.slice(2);
      const next = args[i + 1];
      if (!next || next.startsWith('--')) {
        flags[key] = true;
      } else {
        flags[key] = next;
        i += 1;
      }
    }
  }
  return { command, flags };
}

function isAllowedEndpoint(endpoint) {
  const url = new URL(endpoint);
  if (url.protocol === 'https:') {
    return true;
  }
  return url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname);
}

function sanitizeSshValue(value, pattern, label) {
  if (typeof value !== 'string' || !pattern.test(value)) {
    throw new Error(`Bridge returned an invalid SSH ${label}.`);
  }
  return value;
}

function commandExists(command) {
  const pathValue = process.env.PATH || '';
  for (const entry of pathValue.split(path.delimiter)) {
    if (!entry) {
      continue;
    }
    const candidate = path.join(entry, command);
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return candidate;
    } catch (_error) {}
  }
  return null;
}

function spawnPythonSshHelper({ user, host, password }) {
  const pythonBin = commandExists('python3');
  if (!pythonBin) {
    throw new Error('Autonomous SSH login requires a built-in helper runtime that is not available on this machine.');
  }
  const helperPath = path.join(__dirname, 'ssh_password_helper.py');
  return spawn(pythonBin, [helperPath, `${user}@${host}`], {
    stdio: 'inherit',
    env: {
      ...process.env,
      LCL_COMMAND_SSH_PASSWORD: password
    }
  });
}

function spawnExpectSsh({ user, host, password }) {
  const expectBin = commandExists('expect');
  if (!expectBin) {
    return spawnPythonSshHelper({ user, host, password });
  }
  const expectScript = `
set timeout -1
log_user 1
match_max 100000
set password $env(LCL_COMMAND_SSH_PASSWORD)
set target $env(LCL_COMMAND_SSH_TARGET)
spawn ssh -o StrictHostKeyChecking=accept-new -- $target
expect {
  -re "(?i)are you sure you want to continue connecting" {
    send -- "yes\\r"
    exp_continue
  }
  -re "(?i)password:" {
    send -- [format "%s\\r" $password]
    interact
  }
  eof {
    catch wait result
    if {[llength $result] >= 4} {
      exit [lindex $result 3]
    }
    exit 0
  }
}
`;
  return spawn(expectBin, ['-c', expectScript], {
    stdio: 'inherit',
    env: {
      ...process.env,
      LCL_COMMAND_SSH_PASSWORD: password,
      LCL_COMMAND_SSH_TARGET: `${user}@${host}`
    }
  });
}

function requestJson(endpoint, payload, token = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(endpoint);
    if (!isAllowedEndpoint(endpoint)) {
      reject(new Error('Endpoint must use HTTPS unless it targets localhost.'));
      return;
    }
    const body = JSON.stringify(payload);
    const transport = url.protocol === 'https:' ? https : http;
    const req = transport.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port || (url.protocol === 'https:' ? 443 : 80),
        path: `${url.pathname}${url.search}`,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
          ...(token ? { Authorization: `Bearer ${token}` } : {})
        }
      },
      (res) => {
        let chunks = '';
        res.setEncoding('utf8');
        res.on('data', (chunk) => {
          chunks += chunk;
        });
        res.on('end', () => {
          try {
            const parsed = chunks ? JSON.parse(chunks) : {};
            if (res.statusCode >= 200 && res.statusCode < 300) {
              resolve(parsed);
            } else {
              const message = parsed && parsed.error ? parsed.error : `Request failed (${res.statusCode})`;
              reject(new Error(message));
            }
          } catch (error) {
            reject(new Error(`Invalid JSON response from bridge: ${error.message}`));
          }
        });
      }
    );
    req.setTimeout(REQUEST_TIMEOUT_MS, () => {
      req.destroy(new Error(`Request timed out after ${REQUEST_TIMEOUT_MS}ms.`));
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function prompt(question, { silent = false } = {}) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    if (silent && process.stdin.isTTY) {
      const onData = (char) => {
        const text = String(char);
        switch (text) {
          case '\n':
          case '\r':
          case '\u0004':
            process.stdout.write('\n');
            break;
          default:
            process.stdout.write('*');
            break;
        }
      };
      process.stdin.on('data', onData);
      rl.question(question, (answer) => {
        process.stdin.removeListener('data', onData);
        rl.close();
        resolve(answer);
      });
      return;
    }
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

function printHelp() {
  console.log('LCL Command :: installable Mission Control client');
  console.log('');
  console.log('Commands:');
  console.log('  lcl-command login [--email <email>] [--pin <pin>] [--endpoint <url>]');
  console.log('  lcl-command status');
  console.log('  lcl-command shell');
  console.log('  lcl-command console');
  console.log('  lcl-command logout');
  console.log('  lcl-command version');
  console.log('  lcl-command help');
  console.log('');
  console.log(`Version: ${getVersion()}`);
  console.log(`Default endpoint: ${DEFAULT_ENDPOINT}`);
  console.log(`Session file: ${SESSION_FILE}`);
}

function printSession(session) {
  console.log(`Signed in as: ${session.email}`);
  console.log(`Mission Control: ${session.mission_control_url}`);
  console.log(`Expires at: ${session.expires_at}`);
  console.log(`SSH ready: ${session.features && session.features.ssh_ready ? 'yes' : 'not yet'}`);
  if (session.shell && session.shell.command) {
    console.log(`SSH command: ${session.shell.command}`);
  }
  if (session.arbiter && session.arbiter.message) {
    console.log(`Arbiter: ${session.arbiter.message}`);
  }
}

async function resolveLiveSession(stored) {
  if (!stored || !stored.token || !stored.endpoint) {
    throw new Error('Not logged in. Run `lcl-command login` first.');
  }
  const response = await requestJson(stored.endpoint, { action: 'session' }, stored.token);
  return response.session;
}

async function cmdLogin(flags) {
  const endpoint = flags.endpoint || DEFAULT_ENDPOINT;
  const email = flags.email || await prompt('Company email: ');
  const pin = flags.pin || await prompt('PIN: ', { silent: true });
  const deviceName = `${os.userInfo().username}@${os.hostname()}`;
  const response = await requestJson(endpoint, { action: 'login', email, pin, device_name: deviceName });
  saveSession({ endpoint, token: response.token, email: response.session.email, expires_at: response.session.expires_at });
  console.log('Login successful.');
  printSession(response.session);
}

async function cmdStatus() {
  const stored = loadSession();
  const session = await resolveLiveSession(stored);
  printSession(session);
}

async function cmdLogout() {
  const stored = loadSession();
  if (!stored) {
    console.log('No local session found.');
    return;
  }
  try {
    await requestJson(stored.endpoint, { action: 'logout' }, stored.token);
  } catch (_error) {}
  clearSession();
  console.log('Logged out.');
}

async function cmdShell() {
  const stored = loadSession();
  const session = await resolveLiveSession(stored);
  if (session.shell && session.shell.ready && session.shell.host && session.shell.user) {
    const sshUser = sanitizeSshValue(session.shell.user, /^[a-z_][a-z0-9_-]{0,31}$/i, 'user');
    const sshHost = sanitizeSshValue(session.shell.host, /^[a-z0-9][a-z0-9.-]{0,252}[a-z0-9]$/i, 'host');
    let child;
    if (session.shell.auth_method === 'password') {
      if (typeof session.shell.password !== 'string' || session.shell.password.length === 0) {
        throw new Error('Bridge did not provide the SSH password for autonomous login.');
      }
      child = spawnExpectSsh({ user: sshUser, host: sshHost, password: session.shell.password });
    } else {
      const sshArgs = Array.isArray(session.shell.args) && session.shell.args.length > 0
        ? session.shell.args
        : [`${sshUser}@${sshHost}`];
      child = spawn('ssh', sshArgs, { stdio: 'inherit', shell: false });
    }
    child.on('exit', (code) => process.exit(code || 0));
    return;
  }
  console.log(session.shell && session.shell.message ? session.shell.message : 'SSH handoff is not ready yet.');
  console.log(`Use Mission Control for now: ${session.mission_control_url}`);
}

async function cmdConsole() {
  const stored = loadSession();
  const session = await resolveLiveSession(stored);
  if (session.arbiter && session.arbiter.ready && session.arbiter.url) {
    console.log(`Project Arbiter URL: ${session.arbiter.url}`);
    return;
  }
  console.log('Project Arbiter is still a placeholder from the installable client.');
  console.log('Use the local `lcl-console` command on the host machine for now.');
}

function cmdVersion() {
  console.log(getVersion());
}

(async function main() {
  const { command, flags } = parseArgs(process.argv);
  try {
    switch (command) {
      case 'login':
        await cmdLogin(flags);
        break;
      case 'status':
        await cmdStatus();
        break;
      case 'shell':
        await cmdShell();
        break;
      case 'console':
        await cmdConsole();
        break;
      case 'logout':
        await cmdLogout();
        break;
      case 'version':
        cmdVersion();
        break;
      case 'help':
      default:
        printHelp();
        break;
    }
  } catch (error) {
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
})();
