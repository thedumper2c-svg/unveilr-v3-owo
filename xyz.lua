local fs = require("@lune/fs")
local bytecode = fs.readFile("out.luac");
local loadstring = require("@lune/luau").load

print(loadstring(bytecode)())