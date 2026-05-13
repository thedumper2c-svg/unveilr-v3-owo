const fs = require("fs");
const path = require("path");
const { Client, GatewayIntentBits, Partials } = require("discord.js");
const axios = require("axios");
const luaparse = require("luaparse");
require("dotenv").config();

const CEREBRAS_KEY = process.env.CEREBRAS_API_KEY || "csk-rwr2dm33jnxt38d4wmmd9ypr5vkh98e93f28t44tfkd984jw ";
const DISCORD_TOKEN = process.env.DISCORD_TOKEN || "MTQ0ODQ1NTEwMzUzNDMzODE2OA.GWNDFO.Gu7lc-moJRrlSTFD_W0iwJadPhkMjBUPzNwax4";

async function cerebras(prompt) {
  try {
    const res = await axios.post(
      "https://api.cerebras.ai/v1/chat/completions",
      {
        model: "llama-3.3-70b",
        messages: [{ role: "user", content: prompt }],
        max_tokens: 50000,
        temperature: 0.1,
      },
      {
        headers: {
          Authorization: `Bearer ${CEREBRAS_KEY}`,
          "Content-Type": "application/json",
        },
      }
    );
    return res.data.choices[0].message.content;
  } catch (err) {
    console.error("Cerebras API Error:", err.response?.data || err.message);
    throw err;
  }
}

function extractLocalVariablesWithContext(ast, code) {
  const vars = new Map();
  function walk(node, fn) {
    if (!node || typeof node !== "object") return;
    fn(node);
    for (const key of Object.keys(node)) {
      const child = node[key];
      if (Array.isArray(child)) child.forEach(c => walk(c, fn));
      else if (child && typeof child === "object") walk(child, fn);
    }
  }

  walk(ast, node => {
    if (node.type === "LocalStatement") {
      node.variables.forEach(v => {
        if (v.type === "Identifier" && !vars.has(v.name)) {
          let usage = "";
          if (node.init && node.init.length > 0) {
            const start = node.init[0].range?.[0];
            const end = node.init.at(-1).range?.[1];
            if (start != null && end != null) {
              usage = code.substring(start, end);
              if (usage.length > 100) usage = usage.substring(0, 100) + "...";
            }
          }
          vars.set(v.name, usage);
        }
      });
    }
    if (node.type === "ForNumericStatement" && !vars.has(node.variable.name)) {
      vars.set(node.variable.name, "for loop counter");
    }
    if (node.type === "ForGenericStatement") {
      node.variables.forEach(v => {
        if (!vars.has(v.name)) vars.set(v.name, "for loop variable");
      });
    }
    if (node.type === "FunctionDeclaration") {
      if (node.isLocal && node.identifier) vars.set(node.identifier.name, "local function");
      if (node.parameters) {
        node.parameters.forEach(param => {
          if (param.type === "Identifier" && !vars.has(param.name)) {
            vars.set(param.name, "function parameter");
          }
        });
      }
    }
  });

  return Array.from(vars.entries()).map(([name, usage]) => ({ name, usage }));
}

function chunkArray(arr, chunkSize) {
  const chunks = [];
  for (let i = 0; i < arr.length; i += chunkSize) chunks.push(arr.slice(i, i + chunkSize));
  return chunks;
}

function buildPrompt(vars, context) {
  const varDescriptions = vars.map(v => `- ${v.name}${v.usage ? ` (used in: ${v.usage})` : ""}`).join("\n");

  return `
You are a Lua/Luau variable renamer. Rename ONLY local variables given.

Rules:
1. Do NOT rename string literals
2. Do NOT rename Roblox API objects
3. Do NOT rename globals
4. ONLY rename the variables listed
5. Use PascalCase
6. Local functions & parameters also renamed
7. Do NOT duplicate names
8. Make renames extremely accurate based on usage
9. Focus on bad variable names
10. do not name multiple functions the same name change it up or if does same thing do for example orbfarm orbfarm1 etc
11.

Local variables to rename:
${varDescriptions}

Code context:
${context.substring(0, 4000)}

Respond ONLY with:
{
  "renames": [
    {"old": "x", "new": "PlayerName"},
    {"old": "tmp", "new": "TempValue"}
  ]
}
`;
}

function applyRenamesToCode(code, renameMap) {
  const sorted = [...renameMap].sort((a, b) => b.old.length - a.old.length);
  return code.replace(
    /(--.*$|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\[\[[\s\S]*?\]\]|[A-Za-z_][A-Za-z0-9_]*)/gm,
    token => {
      if (token.startsWith("--") || token.startsWith('"') || token.startsWith("'") || token.startsWith("[[")) return token;
      for (const { old, new: newName } of sorted) if (token === old) return newName;
      return token;
    }
  );
}

async function renameLuaFile(code) {
  let ast;
  try {
    ast = luaparse.parse(code, { luaVersion: "5.1", ranges: true });
  } catch (parseErr) {
    console.error("Lua parse error:", parseErr);
    throw new Error("invalid lua code (parse failed)");
  }

  const vars = extractLocalVariablesWithContext(ast, code);

  const CHUNK_SIZE = 400;
  const varChunks = chunkArray(vars, CHUNK_SIZE);
  let renameMap = [];

  for (let i = 0; i < varChunks.length; i++) {
    const prompt = buildPrompt(varChunks[i], code.slice(0, 2000));
    const output = await cerebras(prompt);
    let json = output.match(/\{[\s\S]*\}/)?.[0];
    if (!json) continue;
    try {
      const parsed = JSON.parse(json);
      if (parsed.renames) renameMap.push(...parsed.renames);
    } catch {}
  }

  if (renameMap.length === 0) return null;
  return applyRenamesToCode(code, renameMap);
}

const client = new Client({ 
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages, GatewayIntentBits.MessageContent],
  partials: [Partials.Channel]
});

client.on("messageCreate", async (message) => {
  if (!message.content.trim().startsWith(".rename") || message.author.bot) return;

  const startTime = Date.now();

  let codeToProcess = null;
  let sourceName = "renamed_code.lua";

  const codeBlockMatch = message.content.match(/```(?:lua)?\n?([\s\S]*?)```/i);
  if (codeBlockMatch) {
    codeToProcess = codeBlockMatch[1];
    sourceName = "inline_code_renamed.lua";
  } 
  else if (message.attachments.size > 0) {
    const attachment = message.attachments.first();
    const ext = path.extname(attachment.name).toLowerCase();
    if (![".lua", ".luau", ".txt"].includes(ext)) {
      return message.reply("attach a file to rename");
    }
    sourceName = attachment.name.replace(/\.(lua|luau|txt)$/, "_renamed.lua");
    try {
      const response = await axios.get(attachment.url);
      codeToProcess = response.data;
    } catch (err) {
      console.error(err);
      return message.reply("failed to download attachment");
    }
  } else {
    return message.reply("attach a file to rename");
  }

  if (!codeToProcess || codeToProcess.trim() === "") {
    return message.reply("no code found to process");
  }

  try {
    const renamedCode = await renameLuaFile(codeToProcess);

    const endTime = Date.now();
    const timeTaken = endTime - startTime;

    if (!renamedCode) {
      return message.reply(`no variables were renamed (took ${timeTaken}ms)`);
    }

    const outputPath = path.join(__dirname, sourceName);
    fs.writeFileSync(outputPath, renamedCode);

    await message.reply({
      content: `here is ur renamed code: (took ${timeTaken}ms)`,
      files: [outputPath]
    });

    fs.unlinkSync(outputPath);
  } catch (err) {
    const endTime = Date.now();
    const timeTaken = endTime - startTime;
    console.error("proccessing error:", err);
    message.reply(`error occured while renaming file (took ${timeTaken}ms)`);
  }
});

client.login(DISCORD_TOKEN);