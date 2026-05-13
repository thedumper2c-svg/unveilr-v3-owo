// @ts-check
/**
 * Sandbox module — isolates spawned processes using Docker containers.
 *
 * Why Docker instead of bwrap?
 *  - bwrap is Linux-only; on Windows it silently fell back to plain spawn (NO isolation)
 *  - Docker works on Windows (Docker Desktop / WSL2) and Linux
 *  - Docker provides filesystem, network, PID, IPC isolation out of the box
 *
 * Security layers applied per container:
 *  1. --network none       → NO network at all (kills @lune/net exfiltration)
 *  2. --read-only          → read-only root filesystem
 *  3. Volume mounts        → only specific files/dirs visible to the process
 *  4. --cap-drop ALL       → no Linux capabilities
 *  5. --security-opt no-new-privileges
 *  6. --memory / --cpus / --pids-limit → resource limits (prevents DoS)
 *  7. --user 65534         → runs as unprivileged nobody
 *  8. --tmpfs /tmp         → isolated temp space, destroyed with container
 *
 * Fallback chain: Docker → bwrap (Linux) → REFUSE (no silent unsandboxed spawn)
 */

const { spawn, execSync } = require('child_process');
const path = require('path');
const os = require('os');
const fsSync = require('fs');

const isLinux = os.platform() === 'linux';
const isWindows = os.platform() === 'win32';

// Base image — built from sandbox/Dockerfile
const IMAGES = {
	base: 'unveilr-sandbox:latest',
};

// ====================== Backend Detection (cached) ======================

/** @type {'docker'|'bwrap'|'none'|null} */
let _backend = null;

function getBackend() {
	if (_backend !== null) return _backend;

	// --- Try Docker ---
	try {
		execSync('docker info', { stdio: 'ignore', timeout: 10_000 });
		_backend = 'docker';

		console.log('[sandbox] Docker backend');
		return _backend;
	} catch {
		/* Docker not available */
	}

	// --- Try bwrap (Linux only) ---
	if (isLinux) {
		try {
			execSync('bwrap --version', { stdio: 'ignore', timeout: 5000 });
			_backend = 'bwrap';
			console.log('[sandbox] bwrap backend (Docker not available)');
			return _backend;
		} catch {
			/* bwrap not available */
		}
	}

	_backend = 'none';
	console.error(
		'[sandbox] ⚠️  NO SANDBOX BACKEND! Install Docker. Untrusted code will be REFUSED.',
	);
	return _backend;
}

/**
 * Pre-pull required Docker images. Call once at startup.
 */
async function init() {
	const backend = getBackend();
	if (backend !== 'docker') return;

	for (const image of Object.values(IMAGES)) {
		try {
			execSync(`docker image inspect ${image}`, {
				stdio: 'ignore',
				timeout: 5000,
			});
			console.log(`[sandbox] Image ${image} ready`);
		} catch {
			console.log(`[sandbox] Building ${image}...`);
			try {
				execSync(`docker build -t ${image} -f sandbox/Dockerfile sandbox`, {
					stdio: 'inherit',
					timeout: 120_000,
				});
			} catch (err) {
				console.error(
					`[sandbox] Failed to build ${image}:`,
					/** @type {Error} */ (err).message,
				);
			}
		}
	}
}

// ====================== Helpers ======================

/** @param {string} p  @param {string} [relativeTo] @returns {string} */
function abs(p, relativeTo) {
	if (path.isAbsolute(p)) return p;
	return path.resolve(relativeTo || process.cwd(), p);
}

/**
 * @typedef {Object} Mount
 * @property {string} host      - Absolute path on the host
 * @property {string} container - Path inside the container
 * @property {'ro'|'rw'} [mode] - Mount mode (default: 'ro')
 */

/**
 * @typedef {Object} DockerSpawnOptions
 * @property {string}   [image]     - Docker image to use
 * @property {Mount[]}  [mounts]    - Volume mounts
 * @property {string}   [workdir]   - Working directory inside container
 * @property {string}   [entrypoint] - Container entrypoint override
 * @property {Object.<string,string>} [env] - Environment variables for container
 * @property {string}   [memory]    - Memory limit (e.g. '512m')
 * @property {number}   [cpus]      - CPU limit
 * @property {number}   [pidsLimit] - PID limit
 * @property {boolean}  [allowNet]  - Allow network (default: false)
 * @property {import('child_process').SpawnOptions} [spawnOptions]
 */

// ====================== Docker Spawn ======================

/**
 * Spawns a process inside a Docker container with strict isolation.
 *
 * @param {string[]}           cmdArgs - Command + args to run inside container
 * @param {DockerSpawnOptions} options - Docker/sandbox configuration
 * @returns {import('child_process').ChildProcess}
 */
function dockerSpawn(cmdArgs, options) {
	const {
		image = IMAGES.base,
		mounts = [],
		workdir = '/sandbox',
		entrypoint,
		env = {},
		memory = '512m',
		cpus = 1,
		pidsLimit = 100,
		allowNet = false,
		spawnOptions = {},
	} = options;

	/** @type {string[]} */
	const dockerArgs = [
		'run',
		'--rm',

		// ---- Network ----
		'--network',
		allowNet ? 'bridge' : 'none',

		// ---- Filesystem ----
		'--read-only',

		// ---- Security ----
		'--security-opt',
		'no-new-privileges',
		'--cap-drop',
		'ALL',

		// ---- Resource limits ----
		'--memory',
		memory,
		'--cpus',
		String(cpus),
		'--pids-limit',
		String(pidsLimit),

		// ---- Temp filesystem ----
		'--tmpfs',
		'/tmp:size=64m',

		// ---- Run as unprivileged ----
		'--user',
		'65534:65534',
	];

	// ---- Volume mounts ----
	for (const m of mounts) {
		const hostPath = abs(m.host);
		dockerArgs.push('-v', `${hostPath}:${m.container}:${m.mode || 'ro'}`);
	}

	// ---- Entrypoint override ----
	if (entrypoint) {
		dockerArgs.push('--entrypoint', entrypoint);
	}

	// ---- Working directory ----
	dockerArgs.push('-w', workdir);

	// ---- Environment variables ----
	for (const [key, value] of Object.entries(env)) {
		dockerArgs.push('-e', `${key}=${value}`);
	}

	// ---- Image + command ----
	dockerArgs.push(image, ...cmdArgs);

	return spawn('docker', dockerArgs, spawnOptions);
}

// ====================== bwrap Spawn (Linux fallback) ======================

/**
 * @typedef {Object} BwrapOptions
 * @property {string}   [cwd]
 * @property {string[]} [readOnly]
 * @property {string[]} [readWrite]
 * @property {boolean}  [allowNet]
 * @property {import('child_process').SpawnOptions} [spawnOptions]
 */

/**
 * @param {string}       command
 * @param {string[]}     args
 * @param {BwrapOptions} options
 * @returns {import('child_process').ChildProcess}
 */
function bwrapSpawn(command, args, options = {}) {
	const {
		cwd = process.cwd(),
		readOnly = [],
		readWrite = [],
		allowNet = false,
		spawnOptions = {},
	} = options;

	const resolvedCwd = abs(cwd);
	const resolvedCommand = abs(command, resolvedCwd);

	/** @type {string[]} */
	const bwrapArgs = [];

	// Minimal read-only system paths
	for (const p of [
		'/usr',
		'/lib',
		'/lib64',
		'/bin',
		'/sbin',
		'/etc/alternatives',
		'/etc/ld.so.cache',
		'/etc/ld.so.conf',
		'/etc/ld.so.conf.d',
		'/etc/ssl',
		'/etc/ca-certificates',
	]) {
		try {
			fsSync.statSync(p);
			bwrapArgs.push('--ro-bind', p, p);
		} catch {
			/* skip */
		}
	}

	bwrapArgs.push('--proc', '/proc');
	bwrapArgs.push('--dev', '/dev');
	bwrapArgs.push('--tmpfs', '/tmp');

	for (const ro of readOnly) {
		const r = abs(ro, resolvedCwd);
		bwrapArgs.push('--ro-bind', r, r);
	}
	for (const rw of readWrite) {
		const r = abs(rw, resolvedCwd);
		bwrapArgs.push('--bind', r, r);
	}

	if (!allowNet) bwrapArgs.push('--unshare-net');
	bwrapArgs.push(
		'--unshare-pid',
		'--unshare-ipc',
		'--new-session',
		'--die-with-parent',
		'--chdir',
		resolvedCwd,
		'--',
		resolvedCommand,
		...args,
	);

	return spawn('bwrap', bwrapArgs, { ...spawnOptions, cwd: resolvedCwd });
}

// ====================== Refuse helper ======================

/**
 * Returns a ChildProcess that immediately exits with code 1 and an error message.
 * Used when no sandbox backend is available — we REFUSE to run unsandboxed.
 * @param {string} reason
 * @returns {import('child_process').ChildProcess}
 */
function refuseToRun(reason) {
	const proc = spawn(
		isWindows ? 'cmd' : 'sh',
		isWindows
			? ['/c', `echo ${reason} 1>&2 & exit 1`]
			: ['-c', `echo "${reason}" >&2; exit 1`],
	);
	return proc;
}

// ====================== Sandbox Profiles ======================

const profiles = {
	/**
	 * Main unveilr deobfuscation — runs main.luau which processes user script.
	 *
	 * Docker: mounts unveilr dir (ro), inputs/ and dumps/ (rw). No network.
	 *         Source code IS readable inside the container, but network is blocked
	 *         so nothing can be exfiltrated. Host files (.env, bot.db) are NOT mounted.
	 *
	 * @param {string}   luneBinary - Host path to the lune binary
	 * @param {string[]} args       - ['run', 'main.luau', ...params]
	 * @param {string}   unveilrDir - The unveilr working directory
	 * @returns {import('child_process').ChildProcess}
	 */
	lune(luneBinary, args, unveilrDir) {
		const resolved = abs(unveilrDir);
		const backend = getBackend();

		if (backend === 'docker') {
			return dockerSpawn(['lune', ...args], {
				image: IMAGES.base,
				entrypoint: '/usr/bin/env',
				env: {
					HOME: '/opt',
					LUTE_BIN: '/usr/local/bin/lute',
					PATH: '/opt/.rokit/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
				},
				mounts: [
					// Unveilr source code (read-only)
					{ host: resolved, container: '/unveilr', mode: 'ro' },
					// Override inputs/ and dumps/ with write access
					{
						host: path.join(resolved, 'inputs'),
						container: '/unveilr/inputs',
						mode: 'rw',
					},
					{
						host: path.join(resolved, 'dumps'),
						container: '/unveilr/dumps',
						mode: 'rw',
					},
				],
				workdir: '/unveilr',
				memory: '512m',
				cpus: 1,
				pidsLimit: 100,
				allowNet: false,
			});
		}

		if (backend === 'bwrap') {
			return bwrapSpawn(luneBinary, args, {
				cwd: resolved,
				readOnly: [abs(luneBinary, resolved), resolved],
				readWrite: [
					path.join(resolved, 'inputs'),
					path.join(resolved, 'dumps'),
				],
				allowNet: false,
			});
		}

		return refuseToRun(
			'SANDBOX_ERROR: No sandbox backend available. Refusing to execute.',
		);
	},

	/**
	 * Direct user Luau code execution (.luau command).
	 * MOST DANGEROUS profile — arbitrary user code runs directly.
	 *
	 * Docker: mounts ONLY the single input script file. Nothing else.
	 *         No unveilr source, no other files, no network.
	 *         @lune/fs sees only /sandbox/<script> — the container is otherwise empty.
	 *         @lune/net gets connection refused (--network none).
	 *         getfenv/metatable tricks are irrelevant — the modules work but can't
	 *         reach the host filesystem or network.
	 *
	 * @param {string}   luneBinary - Host path to the lune binary
	 * @param {string[]} args       - ['run', 'inputs/<file>']
	 * @param {string}   unveilrDir - The unveilr working directory
	 * @returns {import('child_process').ChildProcess}
	 */
	luau(luneBinary, args, unveilrDir) {
		const resolved = abs(unveilrDir);
		const backend = getBackend();

		// Extract the input file path: args = ['run', 'inputs/<file>']
		const inputRelPath = args[1]; // 'inputs/<file>'
		const inputHostPath = path.join(resolved, inputRelPath);
		const inputFileName = path.basename(inputRelPath);
		const containerScript = `/sandbox/${inputFileName}`;

		if (backend === 'docker') {
			return dockerSpawn(['lune', 'run', containerScript], {
				image: IMAGES.base,
				entrypoint: '/usr/bin/env',
				env: {
					HOME: '/opt',
					PATH: '/opt/.rokit/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
				},
				mounts: [
					// ONLY the user's script — nothing else visible
					{
						host: inputHostPath,
						container: containerScript,
						mode: 'ro',
					},
				],
				workdir: '/sandbox',
				memory: '128m',
				cpus: 0.5,
				pidsLimit: 50,
				allowNet: false,
				spawnOptions: { stdio: ['ignore', 'pipe', 'pipe'] },
			});
		}

		if (backend === 'bwrap') {
			return bwrapSpawn(luneBinary, args, {
				cwd: resolved,
				readOnly: [abs(luneBinary, resolved), inputHostPath],
				readWrite: [],
				allowNet: false,
				spawnOptions: { stdio: ['ignore', 'pipe', 'pipe'] },
			});
		}

		return refuseToRun(
			'SANDBOX_ERROR: No sandbox backend available. Refusing to execute user code.',
		);
	},

	/**
	 * Node.js luamin/luathing.js — minification tool.
	 * @param {string[]} args    - ['luathing.js', inputFile, outputFile, type]
	 * @param {string}   [workDir]
	 * @returns {import('child_process').ChildProcess}
	 */
	node(args, workDir) {
		const cwd = abs(workDir || process.cwd());
		const backend = getBackend();

		if (backend === 'docker') {
			return dockerSpawn(['node', ...args], {
				image: IMAGES.base,
				entrypoint: '/usr/bin/env',
				env: {
					HOME: '/opt',
					PATH: '/opt/.rokit/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
				},
				mounts: [
					{
						host: path.join(cwd, 'luathing.js'),
						container: '/app/luathing.js',
						mode: 'ro',
					},
					{
						host: path.join(cwd, 'node_modules'),
						container: '/app/node_modules',
						mode: 'ro',
					},
					{
						host: path.join(cwd, 'package.json'),
						container: '/app/package.json',
						mode: 'ro',
					},
					{
						host: path.join(cwd, 'cache'),
						container: '/app/cache',
						mode: 'rw',
					},
				],
				workdir: '/app',
				memory: '256m',
				cpus: 0.5,
				pidsLimit: 50,
				allowNet: false,
			});
		}

		if (backend === 'bwrap') {
			return bwrapSpawn('/usr/bin/node', args, {
				cwd,
				readOnly: [
					path.join(cwd, 'luathing.js'),
					path.join(cwd, 'node_modules'),
					path.join(cwd, 'package.json'),
				],
				readWrite: [path.join(cwd, 'cache')],
				allowNet: false,
			});
		}

		return refuseToRun('SANDBOX_ERROR: No sandbox backend available.');
	},

	/**
	 * MoonsecDeobfuscator binary.
	 * @param {string}   binary  - Path to the deobfuscator binary
	 * @param {string[]} args    - Deobfuscator arguments
	 * @param {string}   msecDir - The msec working directory
	 * @returns {import('child_process').ChildProcess}
	 */
	moonsec(binary, args, msecDir) {
		const resolved = abs(msecDir);
		const backend = getBackend();

		if (backend === 'docker') {
			const binaryHost = abs(binary, resolved);
			const binaryName = path.basename(binary);

			return dockerSpawn([`/sandbox/${binaryName}`, ...args], {
				image: IMAGES.base,
				entrypoint: '/usr/bin/env',
				env: {
					HOME: '/opt',
					PATH: '/opt/.rokit/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
				},
				mounts: [
					{
						host: binaryHost,
						container: `/sandbox/${binaryName}`,
						mode: 'ro',
					},
					// msec directory for input/output
					{ host: resolved, container: '/sandbox', mode: 'rw' },
				],
				workdir: '/sandbox',
				memory: '512m',
				cpus: 1,
				pidsLimit: 100,
				allowNet: false,
			});
		}

		if (backend === 'bwrap') {
			return bwrapSpawn(binary, args, {
				cwd: resolved,
				readOnly: [abs(binary, resolved)],
				readWrite: [resolved],
				allowNet: false,
			});
		}

		return refuseToRun('SANDBOX_ERROR: No sandbox backend available.');
	},

	/**
	 * Lua Prometheus obfuscator.
	 * @param {string[]} args    - lua arguments
	 * @param {string}   [workDir]
	 * @returns {import('child_process').ChildProcess}
	 */
	lua(args, workDir) {
		const cwd = abs(workDir || process.cwd());
		const backend = getBackend();

		if (backend === 'docker') {
			return dockerSpawn(['lua', ...args], {
				image: IMAGES.base,
				entrypoint: '/usr/bin/env',
				env: {
					HOME: '/opt',
					PATH: '/opt/.rokit/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
				},
				mounts: [
					{
						host: path.join(cwd, 'PrometheusObf'),
						container: '/app/PrometheusObf',
						mode: 'ro',
					},
					{
						host: path.join(cwd, 'cache'),
						container: '/app/cache',
						mode: 'rw',
					},
				],
				workdir: '/app',
				memory: '256m',
				cpus: 1,
				pidsLimit: 100,
				allowNet: false,
				spawnOptions: { stdio: ['pipe', 'pipe', 'pipe'] },
			});
		}

		if (backend === 'bwrap') {
			return bwrapSpawn('/usr/bin/lua', args, {
				cwd,
				readOnly: [path.join(cwd, 'PrometheusObf')],
				readWrite: [path.join(cwd, 'cache')],
				allowNet: false,
				spawnOptions: { stdio: ['pipe', 'pipe', 'pipe'] },
			});
		}

		return refuseToRun('SANDBOX_ERROR: No sandbox backend available.');
	},
};

module.exports = { profiles, init, getBackend };
