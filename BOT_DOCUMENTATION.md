**Overview**
- **File:** This document lives at [BOT_DOCUMENTATION.md](BOT_DOCUMENTATION.md)
- **Purpose:** Summarizes the bot's commands, how premium (tier 1/2) and persistence work, how ScamBlox detection works, and where the main source-exposure vulnerabilities are.

**Commands (high level)**
- **Slash (registered globally/guild):** `/vouch`, `/ticket`, `/close`, `/unveilr`, `/beautify`, `/minify`, `/credits`, `/config`, `/claim`, `/stats`, `/help` — these map to core bot features.
- **Prefix commands (default prefix `.`):** the bot defines many commands in `db.js` under the `commands` object. Important ones include:
  - **help:** lists commands and command info, including premium-only commands.
  - **l / dump / log / envlog / unveilr / d:** the main UnveilR processor command. This reads the provided script, queues it, checks credits/premium, runs the `dump()` function on `./unveilr/main.luau`, and returns a processed `.lua` file. It also logs scripts to `storage/{userId}` and handles captchas every 20 uses.
  - **beautify / bf / coolify:** beautifies a Lua script and returns it as `beautified.lua`.
  - **minify / mf / uncoolify:** minifies a Lua script and returns it as `minified.lua`.
  - **decompile:** sends attached files to `OracleClient.decompile()` and returns decompiled output.
  - **deobfuscate / deobf:** premium tier 2 only, deobfuscates MoonSec V3 files and decompiles the result.
  - **decompress / ld:** premium tier 2 only, logs loadstrings in a file and returns the output.
  - **detect / whatobfisthis / detectobf:** detects the obfuscator used for a file.
  - **rename / renamer / renameittakeit:** premium tier 2 only, renames a script using an external renamer API.
  - **luau:** premium tier 2 only, runs Lua code in a normal Luau process with a timeout and returns console output.
  - **config / cfg / settings:** opens an interactive settings panel for UnveilR options.
  - **bestcfg:** premium tier 2 only, applies a recommended setting profile for speed, accuracy, or tamper handling.
  - **credits / cred / creds:** shows current credit balance or premium status.
  - **claim / collect / redeem:** redeem premium keys to get premium status.
  - **claimcredits / claimcreds:** redeem credit codes for non-premium users.
  - **recover / userecovery / userecoverycode:** transfer premium to another account using a recovery code.
  - **gift / support / helpout:** premium users can gift credits to freemium users.
  - **boost / redeemboost / imabooster:** claim booster rewards and receive credits.
  - **verify / vf:** verify in the official server to gain +1 daily credit.
  - **wl / whitelist / revoke / unwl / blacklist / unblacklist:** moderator-only user management for premium access and blocking.
  - **webhook / wb / webhookinfo / wbinfo:** fetch webhook info and metadata.
  - **stats / statistics / data:** show bot/server usage statistics.
  - **view:** owner/admin command that zips and sends contents of `storage/{id}`.
  - **upload:** owner-only command that uploads an attached script to the external `vercelUrl` upload API.
  - **generatecredits / give:** admin utilities for generating credit codes and handing out credits.
  - **wrd / wearedevs:** send code to the WeAreDevs obfuscator API and return the obfuscated script.
  - **isup / test / uptime:** check bot uptime and status.
  - **hug:** sends a friendly message.

- **Note:** `.l` is the actual core dump command, and many other commands are built around file handling and premium features. `commands.help` can display all available commands and tier requirements in Discord.

**How premium (tier 1 / tier 2) is stored and enforced**
- **Storage:** user records are persisted in SQLite `bot.db` — table `users (userId TEXT PRIMARY KEY, data TEXT)` where `data` is JSON.
- **User record fields:** e.g. `premium` (boolean), optional `tier` (number), `credits`, `settings`, `cooldowns`, etc. (see `getUserData()` and `setUserData()` in `db.js`).
- **Tier logic:** `isPremium(userId)` reads `getUserData(userId).premium`. `getPremiumTier(userId)` returns `data.tier` or sets it to `1` when `premium` is true.
- **Enforcement:** many commands check `isPremium()` or `getPremiumTier()` to allow higher limits (longer timeouts, more concurrent uses, additional commands like `.bestcfg`) or bypass credit costs.

**Persistence / surviving restarts**
- **Primary persistence:** `bot.db` (SQLite file) stores user JSON; changes are made with `setUserData()` which runs `INSERT OR REPLACE INTO users` — this persists across process restarts and machine reboots as long as `bot.db` file remains.
- **Other persisted files:** `codes.json`, `creditCodes.json`, `botStats.json`, `storage/` and `dumps/` folders; these files/folders are read/written from disk and survive restarts.
- **In-memory caches:** some values are cached in memory (e.g., `botStats`), but `saveData()` writes these periodically to disk.

**ScamBlox detection and response**
- **Detection:** output from processing (the `dump()` result) is scanned for URLs and webhooks via `getLinks()` / `validateWebhook()` in `db.js`.
- **Automatic actions:** when webhooks are found, `postWebhook()` will:
  - POST to detected webhooks a public exposure message (this calls the webhook directly with a message complaining about the leaked webhook).
  - Post an embed containing the webhook(s), author, and the code to a configured server channel named `scam-blox` (if available among `authorized.servers`) — done via `channels.scamBlox.send()` and attaching the code file.
- **Special user:** the code treats the internal user id/name `'scamblox'` specially (sometimes considered premium but still triggers reporting).

**Where the full source (or sensitive data) can be leaked — vuln summary**
- **1) Hardcoded secrets in repository files:** some files contain hardcoded Discord tokens or API keys (search for `Authorization` and `DISCORD_TOKEN` in `guild.js`, `rename.js`, etc.). Anyone with repository access or filesystem access to these files can obtain bot credentials.
- **2) Commands that send local files or zips:** commands like `.view` (zips `storage/{id}`) and other admin commands use `zipFolder()`/`createAttachment()` to send local files to Discord. If misused or permitted to non-trusted users, these commands can leak stored data and code.
- **3) Decompile / deobfuscate results are returned:** the `decompile` command and `OracleClient.decompile()` return decompiled outputs back to the caller — if someone uploads compiled/obfuscated code, the bot returns human-readable source via attachments.
- **4) Direct reads of source and attachments:** code reads `./unveilr/main.luau` (for reporting line counts) and uses `createAttachment()` to attach files from disk. Combined with commands that allow attaching arbitrary local files (owner/admin commands), this enables exposing the `./unveilr` folder contents.
- **5) `view` and `storage` directories:** zipping and returning `storage/{id}` or `dumps/` can reveal a user's logged scripts and any files stored on disk.
- **6) Owner-only vs public:** some risky actions are owner-only (e.g., `upload`). But review permission checks: misconfigured checks or leaked owner credentials allow full abuse.

**Practical ways an attacker could get full source (high level)**
- Obtain repository or filesystem access — straightforward way to get every file.
- If attacker can run commands as an authorized user (get owner token, or hit an exposed admin bot endpoint), they can call `.view` / `decompile` / other commands to get zips or decompiled sources.
- If a malicious script is processed by the bot and exposes webhooks, `postWebhook()` will call that webhook — an attacker controlling that webhook could receive the posted message (but that is more about exposed webhooks than bot source).

**Recommendations to mitigate leaks**
- Move secrets out of source: use environment variables and do NOT commit them. Remove any hardcoded tokens from `guild.js`, `rename.js`, etc.
- Restrict dangerous commands: ensure `.view`, `.upload`, `.generate*`, `.decompile` and other file-returning commands are owner-only or require strict permissions/roles.
- Audit and rotate tokens: rotate any tokens that may have been committed.
- Limit `createAttachment()` and file-send paths — sanitize and restrict which local folders may be zipped/attached.
- Log and alert owner when file-returning commands are used and require confirmation for high-risk actions.

**Files referenced**
- Main bot code: [db.js](db.js#L70)
- Helper/Client: [OracleClient.js](OracleClient.js)
- Token example / quick fetch: [guild.js](guild.js)
- Other client: [rename.js](rename.js#L170-L237)

If you want, I can:
- Add this file to the repo (already done) and run a quick grep to list obvious hardcoded secrets.
- Create a locked checklist for remediations (rotate tokens, restrict commands).
