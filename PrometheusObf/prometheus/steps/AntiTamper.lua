-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- AntiTamper.lua
--
-- This Script provides an Obfuscation Step, that breaks the script, when someone tries to tamper with it.

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local RandomStrings = require("prometheus.randomStrings")
local Parser = require("prometheus.parser");
local Enums = require("prometheus.enums");
local logger = require("logger");

local AntiTamper = Step:extend();
AntiTamper.Description = "This Step Breaks your Script when it is modified. This is only effective when using the new VM.";
AntiTamper.Name = "Anti Tamper";

AntiTamper.SettingsDescriptor = {
    UseDebug = {
        type = "boolean",
        default = true,
        description = "Use debug library. (Recommended, however scripts will not work without debug library.)"
    }
}

function AntiTamper:init(settings)
	
end

function AntiTamper:apply(ast, pipeline)
    if pipeline.PrettyPrint then
        logger:warn(string.format("\"%s\" cannot be used with PrettyPrint, ignoring \"%s\"", self.Name, self.Name));
        return ast;
    end

    local cmd = package.config:sub(1,1) == "\\" and "cd" or "pwd"
    local sep = package.config:sub(1,1)
    local antitamperPath = io.popen(cmd):read("*l") .. sep .. "antitamper.lua"

    local file = io.open(antitamperPath,"r")

    local content = file:read("*a")

    file:close()

    local parsed = Parser:new({LuaVersion = Enums.LuaVersion.LuaU}):parse(content);
    local doExpr = parsed.body.statements[1]; -- do NOT put anything before do, it'll break ts bad boii

    doExpr.body.scope:setParent(
        ast.body.scope
    );
    table.insert(ast.body.statements, 1, doExpr);

    return ast;
end

return AntiTamper;