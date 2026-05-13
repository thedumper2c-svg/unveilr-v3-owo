local DONT_DELETE_FILES = true;
local API_URL = "https://unveilr.xyz/api/hello"

local Folders = {
    temp = "temp",
    logs = "logs",
    minified = "minified"
}

local top_level = {}
local ignored_urls = {"https://sirius.menu/rayfield","https://raw.githubusercontent.com/infyiff","https://raw.githubusercontent.com/EdgeIY"}

local loadstring = require("@lune/luau").load
local fs = require("@lune/fs")
local task = require("@lune/task")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local net = require("@lune/net")

local WAIT_PER_FRAME = task.wait() -- Game running at 60 fps, task.wait(1) will be WAIT_PER_FRAME * 60

local Instance = roblox.Instance
local Vector2, Vector3 = roblox.Vector2, roblox.Vector3
local UDim, UDim2 = roblox.UDim, roblox.UDim2

local rep, match, gsub, sub, split, format, lower, upper = string.rep, string.match, string.gsub, string.sub, string.split, string.format, string.lower, string.upper
local insert, concat, pack, find, move = table.insert, table.concat, table.pack, table.find, table.move
local min, max, floor = math.min, math.max, math.floor
local debuginfo = debug.info
local clock = os.clock
local typeof = typeof
local utf8len = utf8.len

local function Require(Path)
    local s, c = pcall(require, Path)

    if s then return c end

    return loadstring(fs.readFile(Path))()
end

local ExecutorEnvironment = Require("./env/Exec.lua")
local EnumLibrary = Require("./env/Enum.lua")
local Services = Require("./env/Services.lua")
local InstanceClass = Require("./env/Instance.lua")
local InstanceFunctions = Require("./env/Functions.lua")
local Classes = Require("./env/Classes.lua")

local IsTesting = true

for _, folder in next, Folders do
    if not fs.isDir(folder) then
        fs.writeDir(folder)
    end
end

local function join(folder, ...) -- joins a folder with the args
    local out = folder
    if sub(out, #out) ~= "/" then out ..= "/" end

    for _, v in next, {...} do
        out ..= v .. "/"
    end

    return sub(out, 1, -2)
end

local Variables = {}
local Counts = {}
local Values = {}
local Internal = {}
local Hooks = {}
local ParamVars = {}
local Tables = {}
local Addresses = {}
local PotentialTypes = {}
local Functions = {}
local Metadata = {}
local MetaTables = {}
local FuncHooks = {}
local Instances = {}

type Variables = { string: table }
type Counts = { string: number }
type Values = { string: table }
type Internal = { string: any }
type Hooks = { string: boolean }
type ParamVars = { table: boolean }
type Addresses = { string: string } -- string: table: 0x...
type PotentialTypes = { string: string } -- var1: "string"
type Tables = { table: boolean } -- Hm
type Functions = { string: boolean }
type Metadata = { table: table } -- metatable: { is_important = boolean }
type MetaTables = { table: table }

local Settings = {
    hookOp = true,
    spyexeconly = false,
    explore_funcs = true,
    minifier = false,
    renameVars = true,
    max_ops = 5_500,
    func_ops = 1_000,
    no_string_limit = false,
    checkIndex = true
}

local function StrToValue(Str)
    if Str == "false" then return false
    elseif Str == "true" then return true
    elseif Str == "nil" then return nil
    elseif tonumber(Str) then return tonumber(Str)
    else return Str end
end

for index, arg in process.args do
    local k, v = match(arg, "--([%w_]+)=(.+)")

    local Arg = sub(arg, 3) -- remove --

    if Arg == "prod" then
        IsTesting = false
        continue
    end

    if v then -- version=, outfile =
        Settings[k] = StrToValue(v)
    else
        Settings[Arg] = true
    end
end

local FILE_SIZE = 0
local FILE_SIZE_LIMIT = 1024 * 1024 * 10 -- 10 megabytes
local SENT;
local DIDNT_PARSE;

local function WhiteSpaceIfNeeded(Word)
    return match(sub(Word, #Word), "[%w_]") ~= nil and " " or ""
end

local function IsExecutor(Key: string)
    for _, v in ExecutorEnvironment do
        if find(v, Key) then return true end
    end
end

local function islclosure(x) if typeof(x) ~= "function" then return false end local s = debuginfo(x, "s") return s ~= 'C' and s ~= '[C]' end
local function iscclosure(x) if typeof(x) ~= "function" then return true end local s = debuginfo(x, "s") return s == 'C' or s == '[C]' end

local Alphabet = split("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "")
local Numbers = split("0123456789", "")

local function GenerateId(len)
    local txt = ''
    for i = 1,len or 6 do
        txt ..= Alphabet[math.random(1, #Alphabet)]
    end
    return txt
end

local TraceId = GenerateId(6)

local HardwareId = (function()
    local out = ""
    for i = 1, 4 do
        out ..= GenerateId() .. "-"
    end

    return sub(out, 1, -2)
end)()

local function Load(Source)
    local s, f = pcall(loadstring, Source)

    return s and f or function()getfenv()[GenerateId(12)]=("unable to load file, message: " .. tostring(f))DIDNT_PARSE=true;end
end

local function GetCount(x) : string
    local Count = (Counts[x] or 0) + 1
    Counts[x] = Count

    if Count == 1 then return x end
    return `{x}_{Count}`
end

local function GetType(Name)
    local OldType = typeof(Name)
    if OldType ~= "string" then
        return OldType
    end

    for Type, List in next, ExecutorEnvironment do
        if find(List, Name) then return Type end
    end
end

local function GetAddress(P, T)
    local Address = Addresses[P] or format('%s0x%s', ((T == 'function' or T == 'table') and `{T}: ` or ''), match(tostring(function()end), "0x([A-Fa-f0-9]+)"))

    Addresses[P] = Address
    return Address
end

local OutputLine, Id, ExprId = 0, 0, 0
local Params = {}

local LOGS = {}

local _print = print
local ADD = function(x) -- SaveFails thing
    if Settings.nologs then return end

    _print("--dbg" .. x)
end
print = function(...) -- change later
    local function Color(txt, code)
        return `\27[{code}m{txt}\27[0m`
    end

    local Line, Name = debuginfo(2, "ln")
    local ColoredName = Color(Name == "" and "???" or Name, 32)
    local ColorLine = Color(`line {Line}`, 35)

    local FinalText = `[ {ColoredName} @ {ColorLine} ]:`

    local Beautified = {};
    for _, v in next, {...} do
        local x = (typeof(v) == "table" or typeof(v) == "function") and "\"ignored data type\"" or tostring(v)

        insert(Beautified, x)
    end

    _print(FinalText, ...)
    insert(LOGS, concat(Beautified, " "))
end

local _tab = rep(" ", 4)

local Threads = {
	None = 0,
    PluginSecurity = 1,
    LocalUserSecurity = 3,
    WritePlayerSecurity = 4,
    RobloxScriptSecurity = 5,
    RobloxSecurity = 6,
	NotAccessibleSecurity = 7
}

local ThreadLevel = 3;
local CreateSignal;
local ValueTypes = {}

local function GenerateProperty(ValueType)
    --[[
        Generates random values based on ValueType,
        for example, a string
        a random string from 3 characters to 20,
        a number, 3 to 7 digits.
    ]]

    local Value = ValueTypes[ValueType]

    if Value then return Value end

    local Category = ValueType.Category

    if not find({"Primitive", "DataType"}, Category) then return nil end

    local Name = ValueType.Name
    local Type = ({bool = "boolean", float = "number", int = "number", int64 = "number"})[Name] or Name

    if Type == "number" then
        local Number = "";
        local Digits = math.random(10, 11)

        for i = 1, Digits do
            Number ..= Numbers[math.random(1, #Numbers)]
        end

        Value = tonumber(Number)
    elseif Type == "string" then
        Value = GenerateId(math.random(3, 20))
    elseif Type == "boolean" then
        Value = math.random(1,2)==2
    elseif Type == "Vector2" then
        Value = Vector2.new(1920, 1080)
    end

    ValueTypes[ValueType] = Value
    return Value
end

local function Dump(Source, Nest, Original)
    if typeof(Source) == "string" and sub(Source, 1, 5) == "--err" then
        DIDNT_PARSE = true
        return Source
    end

    Nest = Nest or 0

    local Tab = rep(_tab, Nest)
    local Suffix

    local OpCount = 0
    local MAX_OPS = Original and Settings.max_ops or Settings.func_ops

    local Output = {}
    local WhileCount = 0

    local ParamCount = 10
    local SpiedParams

    local function OpCountCheck()
        OpCount += 1
        
        if OpCount >= MAX_OPS then print("too much, quit it") error("too many operations", 3) end
    end

    local WaitingEnds = {
        ifs = 0,
        whiles = 0,
        forloops = 0
    }

    local function AddNest(n)
        n = n or 1

        Nest += n
        Suffix = Nest == 0 and "" or `_{Nest}`
        
        if n > 0 then
            Tab ..= _tab
        elseif n < 0 then
            Tab = sub(Tab, 1, #Tab - #_tab)
        end
    end

    AddNest(0)

    local function IsWeird(Key) : boolean
        if Key == "" or typeof(Key) ~= "string" or tonumber(sub(Key, 1, 1)) then return true end -- If key == "" or the key isnt a string or the first byte is a number

        return match(Key, "[^%w_]") ~= nil
    end

    local function GetHex(Data)
        return match(tostring(Data), "0x[a-fA-F0-9]+")
    end

    local function Beautify(Data, Indent, Args) : string
        Indent = Indent or Nest + 1

        local tab = rep(_tab, Indent)

        Args = Args or {}

        local funcName = Args.funcName

        local function IsRecursive(t)
            if typeof(t) ~= "table" then return false end
            
            local visited = {}

            local function check(tbl)
                if visited[tbl] then
                    return true
                end

                visited[tbl] = true

                for _, v in next, tbl do
                    if typeof(v) == "table" then
                        if check(v) then
                            return true
                        end
                    end
                end

                visited[tbl] = nil
                return false
            end

            return check(t)
        end

        local Beautifiers = {
            ["string"] = function()
                local replaced = gsub(Data, "\\", "\\\\")

                replaced = gsub(replaced, "[\n\b\t\v\f\"\r]", {
                    ["\n"] = "\\n", ["\b"] = "\\b", ["\t"] = "\\t", ["\v"] = "\\v", ["\f"] = "\\f", ["\""] = "\\\"", ["\r"] = "\\r"
                })

                if not Settings.no_string_limit then
                    local len = utf8len(replaced)
                    local maxBytes = 1000

                    if len and len > maxBytes then
                        replaced = sub(replaced, 1, maxBytes) .. `..( {len - maxBytes} bytes left)` --> heh
                    end
                end

                replaced = gsub(replaced, "[\0-\31\127\129\157\141\143\144]", function(a) return "\\" .. string.byte(a) end)

                return ('"' .. replaced .. '"')
            end,
            ["table"] = function()
                local Internal = Variables[Data]

                if Internal then
                    return ParamVars[Data] and tostring(Data) or Internal
                end

                if IsRecursive(Data) then return '{ "recursive table" }' end

                local out, isArray, count = "{", true, 0;

                for k, v in next, Data do
                    count += 1

                    if count ~= k then isArray = false end

                    local baseKey = (IsWeird(k) and `[{Beautify(k)}]` or k) .. " = "
                    local Key = isArray and "" or baseKey

                    out ..= `\n{tab}{Key}{Beautify(v, Indent + 1, Args)},`
                end

                out = #out == 1 and "{}" or (sub(out, 1, -2) .. `\n{rep(_tab, Indent - 1)}}`)

                local mt = getmetatable(Data)

                if mt and not Args.ignore_mt then
                    if typeof(mt) ~= "table" then
                        local Beautified = Beautify(mt, Indent, {ignore_funcs=true})

                        out = format("setmetatable(%s, { __metatable = %s })", out, Beautified)
                    else
                        local hasAntitamper = mt.__tostring

                        mt.__tostring = hasAntitamper and function()return("this is not the actual __tostring, this is just an internal feature to prevent detections")end or nil

                        out = `setmetatable({out}, {Beautify(mt, Indent)})`

                        mt.__tostring = hasAntitamper
                    end
                end

                return out
            end,
            ["function"] = function() --! probably merge output?
                local S, Name = debuginfo(Data, "sn");

                if S == "[C]" then return Name == "" and `GET_C_CLOSURE({GetHex(Data)})` or Name end
                if not Settings.explore_funcs then return "function()--[[enable explore funcs to view this function]]end" end
                if Args.ignore_funcs then return "function()--[[function ignored]]end" end

                local Old, OldParams, OldNest, OldOps = Output, Params, Nest, OpCount
                Output, Params, Nest, OpCount = {}, {}, Indent, 0

                ADD("cls")

                local NextTab = rep(_tab, Indent)

                local Dumped = Dump(Data, Indent, false)

                local Out = (not Args.dont_wrap and (funcName and `function {funcName}` or "function") .. "(...)\n" or "")

                if not Args.ignore_args then Out = Out .. NextTab .. GetParamStr() end

                if #Output > 0 then
                    for _, v in next, Output do
                        Out ..= `{NextTab}{v}\n`
                    end
                end

                Out ..= Dumped .. (Args.dont_wrap and "" or "\n" .. rep(_tab, Indent - 1) .. "end")

                Output, Params, Nest, OpCount = Old, OldParams, OldNest, OldOps

                return Out
            end,
            ["number"] = function()
                if tonumber(format("%.4f", Data)) ~= Data then Data = math.ceil(Data) end --> weird floats

                local str = tostring(Data)
                return str == "-inf" and "-math.huge" or str == "inf" and "math.huge" or str
            end,
            ["userdata"] = function()
                local mt = getmetatable(Data)
                if mt then --> newproxy()
                    return `get_user_data({Beautify(mt, Indent + 1, {ignore_funcs = true})})`
                end

                return Beautify(tostring(Data))
            end,
            ["thread"] = function()
                return `get_thread({GetHex(Data)})`
            end,
            ["UDim2"] = function()
                local X, Y = Data.X, Data.Y

                return `UDim2.new({X.Scale}, {X.Offset}, {Y.Scale}, {Y.Offset})`
            end,
            ["UDim"] = function()
                return `UDim.new({Data.Scale}, {Data.Offset})`
            end,
            ["Vector2"] = function()
                return `Vector2.new({Data.X}, {Data.Y})`
            end,
            ["Vector3"] = function()
                return `Vector3.new({Data.X}, {Data.Y}, {Data.Z})`
            end,
            ["Color3"] = function()
                return `Color3.fromRGB({floor(Data.R * 255)}, {floor(Data.G * 255)}, {floor(Data.B * 255)})`
            end
        }

        return (Beautifiers[typeof(Data)] or function() return tostring(Data) end)()
    end

    local function BeautifyTuple(...)
        local Out = ""
        local Packed = pack(...)

        for i = 1, Packed.n do
            Out ..= Beautify(Packed[i]) .. ", "
        end

        return sub(Out, 1, -3)
    end

    function Index(Key, Path) : string
        if Path == "..." then
            Path = "(...)"
        end

        if not IsWeird(Key) then
            return Path --[[and Path ~= "getfenv()"]] and `{Path}.{Key}` or Key
        end

        Path = Path or "getfenv()"
        return `{Path}[{Beautify(Key)}]`
    end

    local function Append(Text)
        if (FILE_SIZE >= FILE_SIZE_LIMIT and not SENT) then
            SENT = true

            insert(Output, (`-- file too large ({FILE_SIZE / 1024 // 1024} mb)`))
            ADD(Output[#Output])
            return
        end

        local Content = Tab .. Text
        ADD(Content)

        FILE_SIZE += #Content
        Output[#Output+1] = Content
    end

    local function GetVar()
        Id += 1

        return `var{Id}{Suffix}`
    end

    local function GetActualPath(Path)
        local Result = Path;

        while true do
            local Value = Values[Result]
            if not Value then break end
            Result = Value.Value
        end

        return Result
    end

    local function SplitIDX(str) : string --> Returns the indexes of a string (a['b'], a.b, ...)
        str = tostring(str)

        local Result = {}
        for Part in str:gmatch("[^%.%[]+") do
            local Key = Part:match('^%s*(.-)%s*$')

            if sub(Key, -1) == ']' then
                Key = match(Key, '%[(.-)%]') or Key
                Key = gsub(Key, '^["\'](.-)["\']$', '%1') -- remove quotes
            end
            insert(Result, Key)
        end
        return Result
    end

    local function GetInternalValue(x)
        local Var = Variables[x]
        local Int = Internal[Var]

        if Int ~= nil then --! issue here (Int[1] ~= x?)
            return Int[1] 
        end

        return x
    end

    local function SetInternal(x, y)
        Internal[x] = {y}
        PotentialTypes[x] = PotentialTypes[x] or typeof(y)
    end

    local Typeof = function(x)
        local v = GetInternalValue(x)

        return PotentialTypes[v] or typeof(x)
    end

    local function Define(Var, Value, Tag)
        OutputLine += 1
        local Prefix = Tag ~= "__newindex" and "local " or ""

        Append(`{Prefix}{Var} = {Value}`)

        Values[Var] = { Value = Value, Tag = Tag }
    end

    local function DefineVar(Value, Int)
        local Var = GetVar()
        Define(Var, Value)
        if Int then SetInternal(Var, Int) end

        return Var
    end

    local function CloseStatement(Extra)
        AddNest(-1)
        Append("end" .. (Extra or ""))
    end

    local AlreadySpied = {}
    local Iterators = {}

    local function CreateFunction(Callback, Path)
        local f = setmetatable({}, {
            __call = function(_, ...)
                return Callback(...)
            end,
            __tostring = function() return Path end
        })

        PotentialTypes[f] = "function"
        Variables[f] = Path
        Functions[f] = true

        return f
    end

    local function Spy(Path, Flags)
        assert(typeof(Path) == "string", `invalid argument #1 to 'Spy', string expected got {typeof(Path)}, line {debuginfo(2, "l")}`)

        local s = AlreadySpied[Path]
        if s then return s end

        local function Arth(Symbol)
            return function(x, y)
                local Var = DefineVar(`{Beautify(x)} {Symbol} {Beautify(y)}`)

                if Symbol == ".." then
                    PotentialTypes[Var] = "string"
                else
                    PotentialTypes[Var] = "number"
                end

                local X, Y = GetInternalValue(x), GetInternalValue(y)
                local Value;

                if typeof(X) == "number" and typeof(Y) == "number" then
                    if Symbol == "+" then Value = X + Y
                    elseif Symbol == "-" then Value = X - Y
                    elseif Symbol == "*" then Value = X * Y
                    elseif Symbol == "/" then Value = X / Y
                    elseif Symbol == "//" then Value = X // Y
                    elseif Symbol == "%" then Value = X % Y
                    end
                elseif Symbol == ".." then
                    if typeof(X) == "string" and typeof(Y) == "string" then
                        SetInternal(Var, X .. Y)
                        PotentialTypes[Var] = "string"
                    end

                    if Settings.hookOp then
                        return Spy(Var)
                    else return Value end
                end

                if Value then
                    Append("--" .. Value)
                    SetInternal(Var, Value)
                    PotentialTypes[Var] = "number"

                    return Settings.hookOp and Spy(Var) or Value
                end

                return Spy(Var)
            end
        end

        Flags = Flags or {}

        local IsParam = Flags.Param or Flags.OriginalIsParam
        local Math = {
            __add = "+",
            __sub = "-",
            __mul = "*",
            __mod = "%",
            __div = "/",
            __idiv = "//",
            __pow = "^",
            __concat = ".."
        }

        local Updated = {}

        local Meta
        Meta = { --! the internal checks pmo, check them out twinzo
            __index = function(Var, Key)
                local function def()
                    Define(Var, `{Index(Key, Path)}`, "__index")
                end

                local Int = Internal[Path]
                if Int then
                    if (Metadata[Path] or {}).custom_var then Id += 1 def() end -- Color3, Vector3, ...
                    if Int[1] == nil then
                        def()

                        return FallbackValue(Var, nil)
                    end

                    Id -= 1
                    local Value = Int[1][Key]

                    if typeof(Value) == "function" then -- x.match
                        return CreateFunction(function(x, ...)
                            local IsNamecall = Variables[x] == Path
                            if IsNamecall then
                                x = Int[1]
                            end

                            local val = pack(Value(x, ...))

                            if IsNamecall then
                                local Needed = {}

                                for _ = 1, val.n do
                                    insert(Needed, GetVar())
                                end

                                Append(`local {concat(Needed, ", ")} = {Path}:{Key}({BeautifyTuple(...)})`)

                                local Fallbacks = {}
                                for _, v in next, Needed do
                                    insert(Fallbacks, FallbackValue(v, val[v]))
                                end

                                return unpack(Fallbacks)
                            end

                            return unpack(val)
                        end, Index(Key, Path))
                    end

                    return Int[1][Key]
                end
                
                def()

                local New = Updated[Key]

                if New then
                    local x = New[1]

                    SetInternal(Var, x) -- support for things like: UI.Visible = false
                end

                Flags.OriginalIsParam = nil

                return Spy(Var, Flags)
            end,
            __newindex = function(_, Key, Value)
                Id -= 1 -- since Var adds one
                --print("metatable newindex",Key,Value)

                Updated[Key] = {Value}

                local Int = Internal[Path]

                if Int then
                    Int[1][Key] = Value
                else -- idk why i do this tbh (its to prevent stuff like getgenv().x = y from being logged twice)
                    local Indexed = Index(Key, Path)

                    Define(Indexed, Beautify(Value), "__newindex")
                end
            end,
            __call = function(Var, ...) -- add namecall support
                local Int = Internal[Path]

                if Int and not Variables[Int[1]] and Int[1] then -- so stuff like hookfunction(x, y) dont turn x into y
                    Id -= 1
                    return Int[1](...)
                end

                local Type = GetType(Path)

                if Type and Type ~= "function" then error(`attempt to call a non function ({Path}) (yo ts is lowkey an internal error don't tell em)`) end

                local ActualPath = GetActualPath(Path)
                local Arg1 = (...)

                local Value;
                local IntVar = Variables[Arg1]
                local Indexes = SplitIDX(ActualPath)
                local IndexVar = move(Indexes, 1, #Indexes - 1, 1, {})
                local Args = pack(...)

                local Arg2 = Args[2]

                --[[
                * Indexes[1] is the caller
                * Indexes[2] is the method (x:y, indexes[2] is y)
                ]]

                IndexVar = concat(IndexVar, ".")
                local IsNamecall = IndexVar == IntVar and #Indexes > 1;

                if IsNamecall then -- Namecall
                    local Beautified = BeautifyTuple(select(2, ...))

                    Value = `{IntVar}:{Indexes[#Indexes]}({Beautified})\n` -- i remove Index(IntVar) here i dont remember why
                end

                if not Value then
                    local Beautified = ""
                    for i = 1, Args.n do
                        local Arg = Args[i]
                        Beautified ..= Beautify(Arg, Nest + 1) .. ", "
                    end

                    Value = `{Path}({sub(Beautified, 1, -3)})\n`
                end

                if not Value and Args.n == 2 and GetInternalValue(Arg1) == nil then
                    if GetInternalValue(Arg2) == nil then -- started the iteration, when its not nil then its done
                        Iterators[Path] = true

                        -- its an iterator thing
                        local i, v = GetCount("i"), GetCount("v")

                        Append(`for {i}, {v} in {Path} do`)

                        WaitingEnds.forloops += 1 AddNest(1)

                        return Spy(i), Spy(v)
                    elseif Iterators[Path] then
                        CloseStatement()
                        WaitingEnds.forloops -= 1

                        return nil, nil
                    end
                end

                --Define(Var, Value, "__call")
                Tab = sub(Tab, -#_tab)
                Append(`local {Var} = {Value}`)
                --Output[#Output+1] = `local {Var} = {Value}`

                return Spy(Var)
            end,
            __tostring = function() return Path end,
            __unm = function(Var)
                Define(Var, `-{Path}`, "__arth")

                return Spy(Var)
            end,
            __iter = function(_, Func)
                local Called;

                local i, v = GetCount("i"), GetCount("v")
                local FixedPath = Path

                if Func then
                    FixedPath = Func == "next" and `next, {Path}` or `{Func}({Path})`
                end

                Append(`for {i}, {v} in {FixedPath} do`) --! add func

                return function()
                    if Called then WaitingEnds.forloops -= 1 CloseStatement() return nil, nil else WaitingEnds.forloops += 1 AddNest() Called = true end

                    return Spy(i), Spy(v)
                end
            end,
            __metatable = nil
        }

        for method, symbol in next, Math do
            Meta[method] = Arth(symbol) -- __add and stuff
        end

        for methodName, method in next, Meta do
            Meta[methodName] = function(_, ...)
                if Flags.OriginalIsParam and not find(Params, Path) then
                    insert(Params, Path)
                end

                OpCountCheck()

                if Math[methodName] then
                    return method(_,...)
                end

                return method(GetVar(), ...)
            end
        end

        Meta = setmetatable({}, Meta)

        Variables[Meta] = Path
        ParamVars[Meta] = IsParam

        AlreadySpied[Path] = Meta

        return Meta
    end

    function FallbackValue(Var, Value)
        if Settings.hookOp then
            SetInternal(Var, Value)

            return Spy(Var)
        end

        return Value
    end

    local Loaded = (typeof(Source) == "function" and Source) or Load(Source)
    
    local Env;
    local EnvValues = {io={},package={}}

    local function Obfuscate(Code)
        local File = join(Folders.temp, GenerateId(6))

        fs.writeFile(File, Code)
        local s, t = pcall(Obf, File)
        if sub(t, 1, 5) == "--err" then
            s = false
        end

        task.spawn(fs.removeFile, File)
        return s, t
    end

    local Luraph;
    local LoadCalls = 0

    local function CreateLoader(Path) --> CreateLoader("loadstring")
        --! add an offset when loading, so it adds the number of lines in the code to the error message (load("\nprint()")) if errors, should return [luau.load: 2] not : 1

        local f = CreateFunction(function(Data)
            if
                typeof(Data) == "number" or (typeof(Data) == "table" and not Variables[Data] and getmetatable(Data))-- or typeof(Data) ~= "string"
            then
                print('naughty boy:)') return error("naughty boy..")
            end

            if Data=="LuaP" then Luraph = true end
            LoadCalls += 1

            local data = Data

            local Var;
            local function def()
                Var = DefineVar(`{Path}({Beautify(data)})`)
            end

            Data = GetInternalValue(Data)

            def()

            if typeof(Data) == "string" and (not Luraph) and Settings.hookOp then --! this is a temp fix, do not release.
                local success, obf = Obfuscate(Data) --! DO NOT PCALL. IT IS ALREADY PCALLED.

                if success then
                    Data = obf
                end
            end

            if typeof(Data) == "string" then
                --[[return CreateFunction(function(...)
                    print("Load",Data,setfenv(Load(Data), Env)(...))
                    
                    Append(`{Var}({BeautifyTuple(...)})`)

                    return setfenv(Load(Data), Env)(...)
                end, Var)]]

                local LoadedFunc;

                local s, loaded = pcall(loadstring, Data)
                if s then
                    LoadedFunc = loaded
                else
                    Append(`-- unable to load content {sub(Beautify(Data), 1, 1000)}, returning a spied variable.`)
                    error(loaded)
                    return Spy(Var)
                end

                return CreateFunction(function(...)
                    local ReturnValues = pack(
                        pcall(setfenv(LoadedFunc, Env), ...)
                    )

                    if ReturnValues[1] then
                        return unpack(ReturnValues, 2)
                    end

                    --error(Values[2])

                    Append(`error({Beautify(ReturnValues[2])}) -- Loadstring error`)

                    if not Var then def() end

                    return Spy(Var)
                end, Var)
            else
                return CreateFunction(function(...)
                    local Line = {}

                    local Spied = {}
                    for i = 1, 30 do
                        local var = GetVar()
                        insert(Line, var)
                        insert(Spied, Spy(Var))
                    end

                    Append(`local {concat(Line, ", ")} = {Var}({BeautifyTuple(...)})`)

                    return unpack(Spied)
                end, Var)
            end
        end, Path)

        Variables[f] = Path
        SetInternal(Path, f)

        return f
    end

    local Calls = 0
    local Locals = {}

    local function SafeWrap(Func, Path)
        local Library = split(Path, ".")[1]

	    return CreateFunction(function(...)
            Calls += 1

		    local Args = pack(...)
            local Changed;

            --[[
                * for _, n in Args:
                * if Variables[n] then, check if it's a local, if yes then dont enable changed
                * Otherwise do change, also, for args make them all GetInternalValue
            ]]

            local function ScanForChanges(tbl) 
                for n = 1, #tbl do 
                    local Arg = tbl[n] 
                    local Variable = Variables[Arg]

                    if Variable and not Locals[Variable] then 
                        Changed = true 
                        return true
                    end
                end 
                return false
            end 

            Changed = ScanForChanges(Args)

            --[[if Library == "string" then
                if Path == "string.char" then
                    print(Func(unpack(Args))) -- this can probably detect constants
                else
                    --print(Path, Args)
                end
            end]]

            if Changed then
                if Library == "table" then
                    for n = 1, Args.n do
                        local a = Args[n]

                        if typeof(a) == "table" and not Variables[a] then
                            DefineTable(a, GetVar())
                        end
                    end
                end

                local Var = DefineVar(`{Path}({BeautifyTuple(unpack(Args))})`)

                return Spy(Var)
            end

            return Func(unpack(Args))
	    end, Path)
    end

    local Loadstring, load = CreateLoader("loadstring"), CreateLoader("load")
    local TimeOffset = 0
    local PossibleWhiles = {}

    local function Comp(Symbol)
        local function GetValue(x, y) -- raw value of lhs compared to rhs
            if Symbol == ">" then return x > y
            elseif Symbol == "<" then return x < y
            elseif Symbol == ">=" then return x >= y
            elseif Symbol == "<=" then return x <= y
            elseif Symbol == "or" then return x or y
            elseif Symbol == "and" then return x and y
            end
        end

        return function(x, y, z)
            local _x, _y = x, y;
            local zX, zY = z[1] == 1, z[2] == 1

            if PossibleWhiles[x] or PossibleWhiles[y] then
                print("hi",x,Symbol,y)
                --[[local Var = DefineVar(`{x} {Symbol} {y}`)
                SetInternal(Var, GetValue(x, y))

                return Spy(Var)]]
            end

            if zX or zY then
                if zX then _x = x() end

                local X = GetInternalValue(_x)

                if Symbol == "or" then
                    if X then return X end -- true or ...
                elseif Symbol == "and" then
                    if not X then return X end -- nil and ...
                end

                if zY then _y = y() end

                x, y = X, GetInternalValue(_y)
            else
                x, y = GetInternalValue(x), GetInternalValue(y)
            end

            local a, b = Variables[x], Variables[y]

            if (a or b) then -- if theres a spied variable, no need to think about it
                local s, Value = pcall(GetValue, x, y)

                if not s then Value = nil end

                local Var = DefineVar(`({a or Beautify(_x)} {Symbol} {b or Beautify(_y)})`)

                OpCountCheck()

                local isXn, isYn = typeof(x) == "number", typeof(y) == "number";

                if isXn then
                    if b ~= "table" then PossibleWhiles[x] = y end -- Prometheus silliness

                    return Value
                elseif isYn then
                    if a ~= "table" then PossibleWhiles[y] = x end -- Prometheus too

                    return Value
                end

                SetInternal(Var, Value)

                return Spy(Var)
            end

            return GetValue(x, y) -- x & y are already true values
        end
    end

    local function SingleComp(Symbol) -- wont have to use real value here
        local function GetValue(x)
            if Symbol == "not" then return not x
            elseif Symbol == "#" then return #x
            elseif Symbol == "-" then return -x
            end
        end
        
        return function(x)
            local a = Variables[x]

            if a then
                local s, Value = pcall(GetValue, GetInternalValue(x));

                if not s then Value = nil end

                OpCountCheck()

                return FallbackValue(DefineVar(`{Symbol}{WhiteSpaceIfNeeded(Symbol)}{a}`), Value)
            end

            return GetValue(x)
        end
    end

   local function Eq(Symbol)
        local function eq(a, b)
            if Symbol == "==" then return a == b else return a ~= b end
        end

        return function(x, y)
            local a, b = Variables[x], Variables[y]

            local v1, v2;

            local function Inner(X)
                local Value = (Values[X] or {}).Value

                if not Value then return end
                    
                if Value == "game.PlaceId" then
                    return "placeid"
                elseif match(Value, "typeo?f?%(") then
                    return "type"
                elseif sub(Value, 1, 1) == "#" then
                    return "len"
                end
            end

            if not a and not b then return eq(x, y) end

            local Forced; -- Force a certain value

            local Var = DefineVar(`({a or Beautify(x)} {Symbol} {b or Beautify(y)})`)

            v1 = GetInternalValue(x) -- defaults to x
            v2 = GetInternalValue(y) -- defaults to y

            local V1Empty, V2Empty = v1 == "", v2 == ""
            local V1String, V2String = typeof(v1) == "string", typeof(v2) == "string"

            local Mt1, Mt2 = a and getmetatable(x), b and getmetatable(y)

            local EQ, ARG1;

            if Mt1 then
                EQ, ARG1 = Mt1.__eq, y
            else
                EQ, ARG1 = Mt2.__eq, x
            end

            if EQ then
                return EQ(Var, ARG1)
            end

            if V1String and V2String then -- raw eq check
                Forced = eq(v1, v2)
            elseif V1String or V2String then
                Forced = Symbol == "=="

                if (V1Empty and not V2String) or (V2Empty and not V1String) then -- "" == not a string
                    Forced = Symbol ~= "==" -- x == "" = false, x ~= "" = true

                    PotentialTypes[Var] = "string"

                    if a then PotentialTypes[a] = "string" end
                    if b then PotentialTypes[b] = "string" end
                end
            end

            local Val = Forced;

            if Val == nil then -- still haven't picked a value yet
                local V1 = ParamVars[x] or v1
                local V2 = ParamVars[y] or v2

                if Symbol == "==" then
                    Val = V1 == V2
                else
                    Val = V1 ~= V2
                end

                if Symbol == "==" then
                    Val = ParamVars[x] or ParamVars[y] or v1 == v2 -- inputtype == x
                else
                    Val = v1 ~= v2
                end

                local IsInner = Inner(a) or Inner(b)

                if IsInner then
                    local Picked;

                    if IsInner == "type" then
                        local Value = a and y or x

                        PotentialTypes[a or b] = Value
                    end

                    if not Picked then Val = Symbol == "==" else Val = Picked end
                end
            end

            SetInternal(Var, Val)

            OpCountCheck()

            return Spy(Var)
        end
    end

    local function Wait(x)
        local rX = GetInternalValue(x)

        if typeof(rX) == "number" then TimeOffset += rX return rX + WAIT_PER_FRAME end
    end

    local TrueEnv = getfenv(Dump)

    local function GetMetatable(Path, Methods)
        local mt = table.clone(getmetatable(Spy(Path)))

        for i, v in next, Methods or {} do
            mt[i] = v
        end

        local ahh = setmetatable({}, mt)

        Variables[ahh] = Path
        
        return ahh
    end

    local function HookLib(Path, Extra)
        local Lib = table.clone(TrueEnv[Path])

        for i, v in next, Lib do
            Lib[i] = SafeWrap(v, Index(i, Path))
        end

        for i, v in next, Extra or {} do Lib[i] = v end

        Variables[Lib] = Path
        SetInternal(Path, Lib)

        setmetatable(Lib, {
            __tostring = function() return Path end --> readable code
        })

        PotentialTypes[Path] = "table"

        return table.freeze(Lib) --> so real?
    end

    local WHILE_LIMIT = 1_000_000

    function DefineTable(tbl, Var)
        if Tables[tbl] then return nil end

        Tables[tbl] = true

        local BlockDepth = 0
        local InsertPosition = #Output + 1
        local FunctionStart = nil

        for i = #Output, 1, -1 do
            local Line = Output[i]

            if match(Line, "%s*end%s*$") then
                BlockDepth = BlockDepth + 1
            elseif match(Line, ".*=%s*function%s*%(") or match(Line, "%s*function%s+") then
                if BlockDepth > 0 then
                    BlockDepth = BlockDepth - 1
                else
                    FunctionStart = i + 1
                    break
                end
            elseif match(Line, "%s*if%s+.-%s+then") or 
                match(Line, "%s*while%s+.-%s+do") or 
                match(Line, "%s*for%s+.-%s+do")
            then
                if BlockDepth > 0 then
                    BlockDepth -= 1
                else
                    InsertPosition = i
                end
            end
        end

        local IsEmpty = true
        for _, v in next, tbl do
            IsEmpty = false
            break
        end

        local TableDeclaration = `{Var} = {Beautify(tbl)}`

        local indentation = ""
        if FunctionStart and FunctionStart <= #Output then
            local nextLine = Output[FunctionStart]
            indentation = match(nextLine, "^%s*") or ""
        end

        if FunctionStart and InsertPosition <= #Output then -- not sure
            insert(Output, FunctionStart, indentation .. `local {Var} = \{}`)
            Append(TableDeclaration)
        elseif FunctionStart then -- inside a function
            insert(Output, FunctionStart, indentation .. `local {TableDeclaration}`)
        elseif InsertPosition <= #Output then -- inside a block like while, if and for
            local Indent = match(Output[InsertPosition], "^%s*") or ""
            insert(Output, InsertPosition, Indent .. `local {Var} = \{}`)
            if not IsEmpty then
                Append(TableDeclaration) -- ignore tables like {} since we already did that at the top
            end
        else -- nothing special happened
            Append(`local {TableDeclaration}`)
        end

        local oldmt = getmetatable(tbl)
        local newmt = GetMetatable(Var)

        if oldmt then return end

        local mt = setmetatable(tbl, newmt)

        Variables[mt] = Var
        Variables[tbl] = Var

        return mt
    end

    local Prometheus = {}

    local Libs = {table=true,coroutine=true,string=true,bit32=true,math=true}
    local Whiles = {
        Stops = 0,
        Started = {}
    }
    local TotalWhiles = 0;

    local IsNestedLoop -- How to check? If a detected while loop exists while inside another one.

    local BaseEnv = {
        COMPL = Comp("<"),
        COMPG = Comp(">"),
        COMPLE = Comp("<="),
        COMPGE = Comp(">="),
        CHECKOR = Comp("or"),
        CHECKUNM = SingleComp("-"),
        CHECKLEN = SingleComp("#"),
        CHECKNOT = SingleComp("not"),
        CHECKAND = Comp("and"),
        CHECKINDEX = Settings.checkIndex and function(tbl, key)
            --local val = GetInternalValue(tbl)

            --tbl = val

            --local val = GetInternalValue(tbl) --! SOMETIMES THIS IS NOT EQUAL TO TBL, EXAMPLE: getfenv() 😠

            local Path = Variables[key]

            if typeof(tbl) == "string" then
                return Env.string[key]
            end

            if Path or Tables[tbl] then
                local _key = key;
                key = GetInternalValue(key)

                OpCountCheck()

                local Var = GetVar()

                if not DefineTable(tbl, Var) then Id -= 1 end

                local Value = tbl[key]

                if not (typeof(key) == "number" and Value) then
                    Var = GetVar()
                    local Beautified = Beautify(tbl)
                    Append(`local {Var} = {Index(_key, Beautified)}`)

                    local md = Metadata[key] or {}
                    local eq = getmetatable(_key).__eq

                    if md.is_important and eq then -- compare it to all keys & valuyes
                        for i, v in next, tbl do
                            Value = Value or GetInternalValue(eq(Var, i)) or GetInternalValue(eq(Var, v))
                        end
                    end
                end

                --SetInternal(Var, Value) -- tbl = {[y] = 3} and tbl = {["1"] = 3} support

                --return Spy(Var)
                return FallbackValue(Var, Value)
            end

            return tbl[key]
        end or nil,
        CONSTRUCT = function(tbl) --! DO NOT TURN ON FOR LURAPH
            local isVararg = true
            local count = 0

            count = #tbl--getCount(tbl)

            for _, v in next, tbl do
                local first = sub(Variables[v] or "abc", 1, 3)

                if not (first == "arg" or first == "...") then
                    isVararg = false
                    break
                end
            end

            if isVararg and count ~= 0 then --! issue here, idk whats happening but issue
                local Var = DefineVar("({...})", SpiedParams)

                local Spied = Spy(Var)

                ParamVars[Spied] = true
                Variables[Spied] = Var
                Tables[Spied] = true

                return Spied
                --return tbl
            end

            --[[if #tbl == 1 and ParamVars[tbl[1] then -- local x = {\n...\n}
                local Var = GetVar()
                Define(Var, "({...})")

                return Spy(Var)
            end]]

            local MT = getmetatable(tbl)

            if MT or count >= 100 then return tbl end

            for i, v in next, tbl do
                local Var = Variables[v]
                if (Variables[i] or Var) and not Functions[v] and not Libs[Var] then
                    local Beautified = Beautify(tbl, nil, {ignore_funcs=true})
                    local Var = DefineVar(Beautified)

                    local spiedmt = GetMetatable(Var, {
                        __index = function(_, Key)
                            local Indexed = Index(Key, Var)
                            local v2 = GetVar()

                            local Value = rawget(tbl, Key)

                            --print("IDX",tbl,Key,Value)

                            -- if the key ISNT a number (then def do it, otherwise ONLY if the value doesnt exist)

                            local isNum = typeof(Key) == "number"

                            if (not isNum) or (Value ~= nil) then
                                DefineTable(tbl, GetVar())
                                Append(`local {v2} = {Indexed}`)
                            end

                            local Spied = Spy(Indexed)

                            Variables[Spied] = v2
                            SetInternal(v2, Value)

                            return Spied
                        end
                    })

                    local mt = setmetatable(tbl, spiedmt)

                    --Variables[mt] = Var
                    --Tables[mt] = true

                    return mt
                end
            end

            return tbl
        end,
        CHECKWHILE = function(x)
            return GetInternalValue(x)
        end,
        FORSTEP = GetInternalValue,
        checkwhile = function(x) -- the check used inside the loop itself (ignore variables because spying them will be really slow)
            if Whiles.Started[x] then
                CloseStatement()
                print("Closing", x, PossibleWhiles[x], Whiles.Stops) --CloseStatement()
                return;
            end

            if Whiles.Stops > 0 then
                print("Bye", x)
                Whiles.Stops -= 1
                return;
            end

            if PossibleWhiles[x] then
                print("Possible while",x,TotalWhiles)
                IsNestedLoop = IsNestedLoop or TotalWhiles ~= 0

                Append(`while {Beautify(PossibleWhiles[x])} do`)
                AddNest()
                Whiles.Started[x] = #Output
                --if IsNestedLoop then WaitingEnds.whiles += 1 end

                TotalWhiles += 1

                --StartedPossibleWhile = #Output
            end

            WhileCount += 1

            if WhileCount >= WHILE_LIMIT then
                Append(`while {x} do end -- exited this loop due to it having {WHILE_LIMIT} iterations.`)
                error("too many iterations")
            end

            return GetInternalValue(x)
        end,
        checkwhileend = function(condition) -- the condition it was called with is LastWhile probably
            --[[if StartedPossibleWhile and StartedPossibleWhile ~= #Output then
                CloseStatement()
                StopWhile, StartedPossibleWhile = true, nil
                return;
            end]]

            if Whiles.Started[condition] then
                print("Added 1 stop")
                CloseStatement()
                TotalWhiles -= 1

                Whiles.Stops += 1
                Whiles.Started[condition] = nil
                --Whiles.Started
                return;
            end

            if WaitingEnds.whiles > 0 then
                WaitingEnds.whiles -= 1
                
                return CloseStatement();
            end

            if IsNestedLoop and Variables[condition] then
                return CloseStatement();
            end
        end,
        CHECKIF = function(x)
            local Var = Variables[x]

            if Var then
                local Value = GetInternalValue(x)
                
                ExprId += 1

                local Hook = Hooks[ExprId]
                local HookExists = Hook ~= nil

                local willrun = Value

                --if willrun == nil then willrun = true end -- then it's just gonna use x lol
                if HookExists then willrun = Hook end

                WaitingEnds.ifs += (willrun and 1 or 0)

                Append(`if {tostring(x)} then -- {willrun and "ran" or "didnt run"}, expr id {ExprId}`) --> tostring(x) to trigger __tostring in case its a param
                if willrun then
                    AddNest()
                else Append("end") end

                if Hook ~= nil then
                    return Hook
                else
                    return willrun
                end
            end

            --[[local Ifs = {}
            
            local FirstCondition = GetInternalValue(x)

            if not FirstCondition then
                for _, v in next, elseifs or {} do insert(Ifs, v) end
            else
                insert(Ifs, {x, callback})
            end

            local Spied = Variables[x] ~= nil;
            local WillRun = FirstCondition;

            local ShouldAddElse = not FirstCondition;

            if Spied and not FirstCondition then
                Append(`if {x} then end`)
            end

            for i, Data in next, Ifs do
                local Condition, Callback = Data[1], Data[2]
                local Var = Variables[Condition]

                if Var then
                    Spied = true

                    print("Yes if check",Data)
                    local Body = Beautify(Callback, Nest, {ignore_args=true, dont_wrap=true})
                    Append(`{i > 1 and "else" or ""}if {Condition} then`)
                    Append(Body)

                    WillRun = WillRun or GetInternalValue(Condition)
                end
            end

            print("Will run:",WillRun)

            if Spied then
                print('hi boi')
                if not WillRun and lastElse then
                    print('boi..?')
                    local Body = Beautify(lastElse, Nest, {ignore_args=true, dont_wrap=true})
                    Append(`if not {x} then -- this was the result of an 'else'`)
                    Append(Body)
                end

                Append("end")
            end

            if FirstCondition then
                callback(...)
            elseif lastElse then
                lastElse(...)
            end]]
            return x
        end,
        CHECKELSE = function(x)
            local Var = Variables[x]

            if Var then
                if WaitingEnds.ifs == 0 then
                    Append(`if not {Var} then`)
                    AddNest()
                    Append('-- this didnt run, this just triggered an \'else\' check.')
                    AddNest(-1)
                    Append('else')
                end

                WaitingEnds.ifs += 1
                AddNest()
            end

            return x
        end,
        checkifend = function()
            if WaitingEnds.ifs > 0 then -- support for obf and twinzos
                WaitingEnds.ifs -= 1
                
                CloseStatement()
            end
        end,
        CHECKEQ = Eq("=="),
        CHECKNEQ = Eq("~="),
        SETLOCAL = function(var, ...) -- local x, y = SETLOCAL("var", 1) -> var = "x", ... = 1
            local vals = table.pack(...)
            local spied = {}

            local UnpackedLocals = {var}
            local AreAllLocals = Locals[var];

            for i = 1, vals.n do
                local v = vals[i]
                local t = typeof(v)

                if Variables[v] or find({"function", "table", "number", "string", "userdata"}, t) then
                    return unpack(vals)
                else
                    local Var = UnpackedLocals[i]
                    if not Var then
                        Var = GetVar()
                        UnpackedLocals[i] = Var
                    end

                    SetInternal(Var, v)

                    AreAllLocals = AreAllLocals and Locals[Var]

                    insert(spied, Spy(Var))
                    Locals[Var] = true
                end
            end
            
            Append(`{AreAllLocals and "" or "local "}{concat(UnpackedLocals, ", ")} = {BeautifyTuple(...)}`)
            
            return unpack(spied)
        end,
        CALL = function(f, ...)
            return (FuncHooks[f] or f)(...)
        end
    }

    for i in BaseEnv do
        SetInternal(i, nil)

        Prometheus[i] = true
    end

    local Gets = 0

    local MethodHooks = {
        RunService = {
            IsStudio = function(self) return false end
        },
        HttpService = {
            JSONEncode = function(self, x)
                x = GetInternalValue(x)

                local Var = self[2]

                if Variables[x] or typeof(x) ~= "table" then
                    return Spy(Var)
                end

                return FallbackValue(Var, serde.encode("json", x))
            end,
            JSONDecode = function(self, x)
                x = GetInternalValue(x)
                
                local Var = self[2]

                if Variables[x] or typeof(x) ~= "string" then
                    return Spy(Var)
                end

                local Value = serde.decode("json", x); -- can error

                return FallbackValue(Var, Value)
            end
        },
        DataModel = {
            HttpGet = function(self, url)
                --[[
                    self1 is the spied instance
                    self2 is the variable name
                ]]

                if match(url, "https?://") and Gets <= 3 then
                    for _, Url in next, ignored_urls do
                        if url:match(Url) then
                            return Spy(self[2])
                        end
                    end

                    Gets += 1

                    local req;
                    local success = pcall(function()
                        req = IsTesting and net.request(url) or net.request({
                            url = API_URL,
                            method = "POST",
                            headers = {
                                ["Roblox-Id"] = tostring(math.random(1e5, 1e6)),
                                ["User-Agent"] = "RobloxStudio/WinInet RobloxApp/0.682.0.6820537 (GlobalDist; RobloxDirectDownload)",
                                ["Content-Type"] = "application/json"
                            },
                            body = serde.encode("json", {udcheck = "hello123", url = url})
                        })
                    end)

                    if success and req.body and req.ok then
                        return FallbackValue(self[2], req.body)
                    end
                end
                
                return Spy(self[2])
            end
        },
        ["*"] = { -- for all
            GetPropertyChangedSignal = function(self, ...)
                return CreateSignal(self[2])
            end
        }
    }

    local PlaceId = GetMetatable("game.PlaceId", {
        __eq = function(Var, val)
            return typeof(val) == "number" and FallbackValue(Var, true) or FallbackValue(Var, false)
        end
    })

    local JobId

    do
        local ActualJobId = `{GenerateId(8)}-{GenerateId(4)}-{GenerateId(4)}-{GenerateId(4)}-{GenerateId(12)}`
        SetInternal("game.JobId", ActualJobId)

        JobId = GetMetatable("game.JobId", {
            __eq = function(Var, val)
                return typeof(val) == "string" and FallbackValue(Var, true) or FallbackValue(Var, false)
            end,
            __len = function() return #ActualJobId end
        })
    end

    Metadata[PlaceId] = { is_important = true }
    Metadata[JobId] = { is_important = true }

    local PropertyHooks = {
        DataModel = {
            PlaceId = PlaceId,
            JobId = JobId
        }
    }

    local IsInPcall
    local AllAllowed = {
        "ReplicatedStorage", "ReplicatedFirst", "CoreGui"
    }

    if Original then
        ADD("cls")

        local function GetData(Table) -- Add Instance methods & properties to a table
            for Key, List in next, InstanceClass do
                local Tuple = Table[Key] or {}

                for i, v in next, List do
                    Tuple[i] = v
                end
            end
            return Table
        end

        local function GetProperType(Property)
            local StrType = ""

            if Property.Category == "Primitive" then
                local Name = Property.Name
                StrType = ({bool = "boolean", float = "number", int = "number", int64 = "number"})[Name] or Name
            end

            return StrType
        end

        local function CreateInstance(Class, Name)
            local Created = Instance.new(Class)
            local IsService = Services[Class]
            local Service = GetData(IsService or Classes[Class] or {})

            Created.Name = Class

            local Properties, methods, Events, Callbacks = Service.properties, Service.methods, Service.events, Service.callbacks or {}
            local ChangedEvents = {}

            CreateSignal = function(Variable, Callback) -- Variable should already be defined
                local Keys = { "Connect", "ConnectParallel", "Wait", "Once" }
                local Table = {}

                for _, Key in next, Keys do
                    Table[Key] = CreateFunction(function(_, Function)
                        local Var = DefineVar(`{Variable}:{Key}({Beautify(Function)})`)
                        PotentialTypes[Var] = "RBXScriptConnection"

                        if Callback then Callback(_, Function) end

                        return Spy(Var)
                    end, Index(Key, Variable))
                end

                local Metatable = setmetatable(Table, {
                    __metatable = "This metatable is locked.",
                    __index = function(_, Key)
                        DefineVar(Index(Key, Variable))

                        return error(`{Key} is not a valid member of RBXScriptSignal`)
                    end,
                    __newindex = error,
                    __iter = error,
                    __tostring = function() return Variable end
                })

                Variables[Metatable] = Variable
                PotentialTypes[Variable] = "RBXScriptSignal"

                return Metatable
            end

            local Metatable = GetMetatable(Name, {
                __index = function(_, Key)
                    local Indexed = Index(Key, Name)

                    local Var, Method, FuncMethod = Indexed, methods[Key], (MethodHooks[Class] or {})[Key] or MethodHooks["*"][Key];
                    local Property = Properties[Key]

                    local PropertyHook = (PropertyHooks[Class] or {})[Key]

                    if not Method and not FuncMethod and not Events[Key] then
                        Var = DefineVar(Indexed)
                    end -- Since the index added 1 (GetMetatable)

                    if PropertyHook then
                        return PropertyHook
                    end

                    local Success, Value = pcall(function()
                        if Method or FuncMethod then
                            return CreateFunction(function(...)
                                local Args = {...}
                                local Arg1 = Args[1]

                                local IsSelf = Variables[Arg1] == Name
                                local Index = IsSelf and 2 or 1

                                local Path = IsSelf and `{Name}:{Key}` or `{Name}.{Key}`
                                local Out = DefineVar(`{Path}({BeautifyTuple(select(Index, ...))})`)

                                if FuncMethod then
                                    local Result = FuncMethod({Arg1, Out}, select(2, ...))
                                    return Result
                                end

                                local Type = GetProperType(Method.ReturnType or {})
                                local Value = {}; -- 1 = Modified, 2 = Value

                                if Type ~= "" then PotentialTypes[Out] = Type end

                                if Key == "IsA" then
                                    Value = { true, InstanceFunctions.IsA(Class, Args[2]) }
                                end

                                if Value[1] then SetInternal(Out, Value[2]) end

                                return Spy(Out)
                            end, Indexed)
                        end

                        return Created[Key]
                    end)

                    if Key == "Changed" then
                        return CreateSignal(Indexed, function(_, f) insert(ChangedEvents, {setfenv(f, Env)}) end)
                    elseif Key == "GetPropertyChangedSignal" then
                        return CreateFunction(function(_, Prop)
                            return CreateSignal(`{Beautify(_)}:{Key}({Beautify(Prop)})`, function(_, f)
                                insert(ChangedEvents, {setfenv(f, Env), Prop})
                            end)
                        end, Indexed)
                    end

                    if Class == "DataModel" and (Classes[Key] or Services[Key]) then
                        return Instances[Key] or CreateInstance(Key, Var)
                    end

                    if (Value == nil or not Success) and Property then
                        if Property.ValueType.Category == "Class" then
                            return CreateInstance(Property.ValueType.Name, Var)
                        end
                        
                        -- Stuff like strings and numbers
                        return FallbackValue(Var, GenerateProperty(Property.ValueType))
                    end

                    if Success then
                        if typeof(Value) == "Instance" then -- Sandbox immediately.
                            Value = Instances[Value.ClassName] or CreateInstance(Value.ClassName, Var) -- May be REALLY stupid?
                        end

                        return FallbackValue(Var or Indexed, Value)
                    end

                    --! Probably an event, if not return nil.

                    --print("Failed all.",Key,Events[Key])
                    if Events[Key] then
                        return CreateSignal(Indexed)
                    end

                    if find(AllAllowed, Class) then return Spy(Var or DefineVar(Indexed)) end
                    if IsInPcall then
                        error(`{Key} is not a valid member of {Class} '{Created.Name}'`)
                    end
                end,
                __newindex = function(_, Key, Value)
                    local Property = Properties[Key]
                    local Callback = Callbacks[Key]

                    Property = Property or Callback

                    -- If the object is a callback, then it HAS to be a function.

                    Append(`{Index(Key, Name)} = {Beautify(Value, nil, {ignore_funcs = not Callback, ignore_mt = true})}`)

                    Value = GetInternalValue(Value)

                    local ValueType = Property.ValueType or {}

                    if not Property then return error(`'{Key}' is not a valid member of {Class} '{Created.Name}'`) end
                    if find(Property.Tags or {}, "ReadOnly") then error(`Unable to assign property {Key}. Property is read only`) end
                    if ValueType.Category == "Primitive" and GetProperType(ValueType) ~= type(Value) then
                        error(`Unable to assign property {Key}. {ValueType.Name} expected, got {type(Value)}`)
                    end

                    for _, v in next, ChangedEvents do
                        local i = v[2]
                        if typeof(i) == "string" and i == Key or typeof(i) == "number" then
                            task.spawn(v[1], Key)
                        end
                    end

                    pcall(function() Created[Key] = Value end)
                end
            })

            Instances[Class] = Instances[Class] or Metatable

            return Metatable
        end

        MethodHooks.DataModel.GetService = function(_, service) -- scuffed af
            local Var = Variables[Instances[service]]
            if Var and _[2] ~= Var or not Var then
                return CreateInstance(service, _[2])
            end
            return Instances[service]
        end

        print("Setting")

        BaseEnv.game = CreateInstance("DataModel", "game")
        BaseEnv.Game = CreateInstance("DataModel", "Game")

        BaseEnv.workspace = CreateInstance("Workspace", "workspace")
        BaseEnv.Workspace = CreateInstance("Workspace", "Workspace")

        BaseEnv.script = CreateInstance("LocalScript", "script")

        BaseEnv.UserSettings = function()
            return Instances.UserSettings or CreateInstance("UserSettings", DefineVar("UserSettings()"))
        end

        BaseEnv.cloneref = function(Object)
            if not Variables[Object] then
                return error("invalid argument #1 to 'cloneref'")
            end

            local Var = DefineVar(`cloneref({Beautify(Object, nil, {ignore_funcs = true, ignore_mt = true})})`)

            return Object
        end
        
        local InstanceLib = {
            new = function(Class, Parent)
                Class = GetInternalValue(Class)

                local Type = Typeof(Class)

                if Type ~= "string" then
                    error(`invalid argument #1 to 'new' (string expected, got {Type})`)
                end

                local Tags = (Classes[Class] or {}).tags or {}
                if find(Tags, "NotCreatable") then
                    error(`Unable to create an Instance of type "{Class}"`)
                end

                return CreateInstance(Class, DefineVar(`Instance.new({Beautify(Class, nil, {ignore_mt = true, ignore_funcs = true})})`)) --! add Parent soon
            end
        }

        Variables[InstanceLib] = "Instance"
        SetInternal("Instance", InstanceLib)
        BaseEnv.Instance = InstanceLib

        local Libraries = {
            "Vector2", "Vector3", "UDim", "UDim2", "Axes", "BrickColor", "CFrame", "Color3", "ColorSequence", "ColorSequenceKeypoint", "Content", "Faces", "NumberRange",
            "NumberSequence", "NumberSequenceKeypoint", "Ray", "Rect", "Region3", "Region3int16", "Vector2int16", "Vector3int16"
        }

        local LibrariesTable = {}
        for _, Lib in next, Libraries do
            LibrariesTable[Lib] = roblox[Lib]
        end

        for LibName, Lib in next, LibrariesTable do
            BaseEnv[LibName] = GetMetatable(LibName, {
                __index = function(_, Key)
                    local Var = DefineVar(Index(Key, LibName))
                    local Int = Lib[Key]

                    if typeof(Int) ~= "function" then return Spy(Var) end

                    return CreateFunction(function(...)
                        local Args = pack(...)
                        local SpyAll;

                        for i = 1, Args.n do
                            local v = Args[i]
                            local Var = Variables[v]

                            if not Var then continue end

                            local Value = Internal[Var]

                            if Value then
                                Args[i] = Value[1]
                            else
                                SpyAll = true
                                break;
                            end
                        end

                        local Var2 = DefineVar(`{Var}({BeautifyTuple(...)})`)

                        if SpyAll then return Spy(Var2) end

                        Metadata[Var2] = {custom_var=true}

                        return FallbackValue(Var2, Int(unpack(Args)))
                    end, Var)
                end
            })
        end
    end

    BaseEnv.hookfunction = function(original, hooked)
        local Variable = Variables[original]

        if Variable then
            SetInternal(Variable, hooked)
        end
        
        FuncHooks[original] = hooked

        local Name;
        if not Variable then
            Name = "_" .. GenerateId(8)

            local OriginalFunc = Beautify(original, nil, {funcName = Name})

            Append("local " .. OriginalFunc)
        else Name = Variable end

        return Spy(DefineVar(`hookfunction({Name}, {Beautify(hooked)})`))
    end
    
    BaseEnv.isfunctionhooked = function(f)
        Append(`isfunctionhooked({Beautify(f)})`)

        return FuncHooks[f] ~= nil
    end
    BaseEnv.ishooked = BaseEnv.isfunctionhooked

    BaseEnv.isexecutorclosure = function(f)
        --return FallbackValue(DefineVar(`isexecutorclosure({Beautify(f)})`), Variables[f] ~= nil);
        return FallbackValue(DefineVar(`isexecutorclosure({Beautify(f)})`), true); -- any function used in the script is an executor closure
    end
    BaseEnv.isexecclosure = BaseEnv.isexecutorclosure
    BaseEnv.queueonteleport = function(n)
        n = GetInternalValue(n)

        local IsNatural = not Variables[n]
        local tp = typeof(n)

        Append(`queueonteleport({tp == "string" or Variables[n] and Beautify(n) or '\'invalid_type (not a string)\''})`)
        if tp ~= "string" then
            error(`invalid argument #1 to 'queueonteleport', string expected, got {tp}`)
        end
    end
    BaseEnv.queue_on_teleport = BaseEnv.queueonteleport

    BaseEnv._VERSION = "Luau"
    
    EnvValues.bit = {table.clone(bit32)}--HookLib("bit32")
    EnvValues.bit32 = {table.clone(bit32)}--HookLib("bit32")
    
    BaseEnv.getgc = function()
        Append("getgc()")

        return table.create(math.random(1000, 5000), {})
    end
    BaseEnv.gethwid = function()
        local Var = DefineVar("gethwid()")

        PotentialTypes[Var] = "string"

        return FallbackValue(Var, HardwareId)
    end

    local SafeEnv = { -- functions that are allowed by default
        -- funcs
        "assert", "select", "newproxy", "rawset",
        "rawequal"
    }

    local Wrapped = { -- functions that check arguments before processing
        "os", -- "coroutine",
        --"rawset", "xpcall", "pcall", "setfenv"
    }

    local Pristine = false;
    local MatchCalls = 0

    local Gmatch = SafeWrap(string.gmatch, "string.gmatch")
    local Match = SafeWrap(string.match, "string.match")

    local function EndsWith(str, ending)
	    return sub(str, -#ending) == ending
    end

    local c = 0

    BaseEnv.string = HookLib("string", {
        gmatch = function(s, p, ...)
            if p == ":(%d*):" and match(s, "attempt to perform arithmetic %(div%) on number and string") then
                MatchCalls += 1

                return function() return MatchCalls end
            end

            return Gmatch(s, p, ...)
        end,
        find = function(str, pat, ...)
            print('find',BeautifyTuple(str, pat, ...))
            if pat == ":(%d+)[:\r\n]" then return 26, 28, 2 end -- luraph

            if typeof(str) ~= "string" then
                local Var = DefineVar(`string.find({BeautifyTuple(str, pat, ...)})`)

                local Str = GetInternalValue(str)
                if typeof(Str) == "string" then
                    return FallbackValue(Var, string.find(Str, pat, ...))
                end

                return Spy(Var)
            end

            return string.find(str, pat, ...)
        end,
        match = function(str, pat)
            print('match',BeautifyTuple(str, pat))
            --if pat == ":(%d+)[:\r\n]" then return "1" end -- luraph

            if typeof(str) ~= "string" then
                local Var = DefineVar(`string.match({BeautifyTuple(str, pat)})`)

                local Str = GetInternalValue(str)
                if typeof(Str) == "string" then
                    return FallbackValue(Var, match(Str, pat))
                end

                return Spy(Var)
            end

            return Match(str, pat)
        end
    })

    BaseEnv.require = function(path)
        if typeof(path) == "string" then
            local msg1 = `Unable to require module from given path '{path}'`

            if IsInPcall then
                error(msg1);
            end
            return nil;
        end

        return Spy(DefineVar(`require({Beautify(path, nil, {ignore_mt = true, ignore_funcs = true})})`))
    end
    BaseEnv.unpack = function(tbl, i, j)
        if Variables[tbl] and not Tables[tbl] then
            return Spy(DefineVar(`unpack({BeautifyTuple(tbl, i, j)})`))
        end

        if typeof(tbl) == "number" or not tbl then return end -- Prometheus
        if typeof(tbl) == "string" then return Spy(tbl) end
        if typeof(tbl) ~= "table" then return tbl end -- Prometheus

        return unpack(tbl, i, j)
    end

    BaseEnv.pcall = CreateFunction(function(f, ...)
        local Old = Output
        Output = {}

        IsInPcall = true

        AddNest()

        local vals = pack(pcall(f, ...))

        IsInPcall = false

        local x = Output

        Output = Old

        --[[
            the nesting here is just to make the variables INSIDE the pcall have the _1 suffix ONLY. (the AddNest(-1) below is for when #x == 0, the AddNest(1) under is to cancel that, the CloseStatement already does -1 so we dont have to do anything else.)
        ]]

        AddNest(-1)

        local success = vals[1]

        if #x ~= 0 then
            local Needed = {}
            local Fallbacks = {}

            local Comment = `-- {success}`
            local Replace = {}

            for n = 1, vals.n do
                local Var = GetVar()
                local Value = vals[n]

                if Variables[Value] then
                    Replace[Value] = Var
                end

                insert(Needed, Var)
                --insert(Fallbacks, FallbackValue(Var, Value))
                insert(Fallbacks, Value--[[FallbackValue(Var, Value)]])
            end

            Append(`local {concat(Needed, ", ")} = pcall(function(...)`)
            AddNest(1)

            for _, Line in next, x do
                if EndsWith(Line, "-- Loadstring error") then
                    Fallbacks[1] = false; -- error
                    Comment = "-- false"
                end
                
                Output[#Output+1] = Line
            end

            if success and vals.n > 1 then
                local ReturnValue = ""

                for i = 2, vals.n do -- nil values
                    local v = vals[i]

                    ReturnValue ..= Beautify(v, Nest + 1) .. ", " -- the previous nest + 1
                end

                ReturnValue = sub(ReturnValue, 1, -3)

                Append(`return {ReturnValue}`)
            end

            CloseStatement(`) {Comment}`)

            for i, v in next, Replace do
                Variables[i] = v
            end

            return unpack(Fallbacks)
        end

        return unpack(vals)
    end, "pcall")

    BaseEnv.error = SafeWrap(error, "error")

    BaseEnv.coroutine = HookLib("coroutine", {
        create = function(a)
            return coroutine.create(a)
        end
    })

    local random = math.random

    local Libs = {
        math = {
            huge = math.huge,
            pi = math.pi
        },
        table = {
            unpack = table.unpack,
            pack = table.pack
        },
        utf8 = {}
    }

    local function CreateEnum(Name, e)
        local function CreateEnumKey(Key2)
            local Path = `Enum.{Name}.{Key2}`
            local mt = setmetatable({ Name = Key2 }, {
                __tostring = function() return Path end,
                __metatable = "This metatable is locked.",
                __index = function(_, Key3)
                    local Var = GetVar()

                    Append(`local {Var} = {Index(Key3, Path)}`)
                    return Spy(Var)
                end
            })

            Variables[mt] = Path
            PotentialTypes[Path] = "EnumItem"

            return mt
        end

        local mt = setmetatable({
            Name = Name,
            GetEnumItems = function()
                local Out = {}

                for _, Key in next, e do
                    insert(Out, CreateEnumKey(Key))
                end

                return Out
            end
        }, {
            __tostring = function() return Name end,
            __metatable = "This metatable is locked.",
            __index = function(_, Key2)
                Append(`local {GetVar()} = {Index(Key2, "Enum." .. Name)}`)

                if not find(e, Key2) then return nil end
                
                return CreateEnumKey(Key2)
            end
        })

        local Var = `Enum.{Name}`
        
        Variables[mt] = Var
        PotentialTypes[Var] = "Enum"

        return mt
    end

    local Enum = setmetatable({
        GetEnums = function()
            local Out = {}

            for Key, List in next, EnumLibrary do
                insert(Out, CreateEnum(Key, List))
            end

            return Out
        end
    }, {
        __index = function(_, Key)
            local e = EnumLibrary[Key]
            Append(`local {GetVar()} = {Index(Key, "Enum")}`)
            if not e then return error(`{Key} is not a valid member of "Enum"`) end

            return CreateEnum(Key, e)
        end,
        __tostring = function() return "Enums" end
    })

    Variables[Enum] = "Enum"
    PotentialTypes["Enum"] = "Enums"

    BaseEnv.Enum = Enum

    for _, v in next, SafeEnv do
        BaseEnv[v] = TrueEnv[v]
    end

    for _, v in next, Wrapped do
        local Value = TrueEnv[v]

        if typeof(Value) == "table" then
            BaseEnv[v] = HookLib(v)
        else
            BaseEnv[v] = SafeWrap(Value, v)
        end
    end

    for LibName, Lib in next, Libs do
        BaseEnv[LibName] = HookLib(LibName, Lib)
    end

    -- File System (Session Only)
    local files = {}
    local FileFuncs = {}

    local function startswith(a, b) return sub(a, 1, #b) == b end
    local function endswith(hello, lo) return sub(hello, #hello - #lo + 1, #hello) == lo end

    FileFuncs.writefile = function(path, content)
        local Path = split(path, '/')
        local CurrentPath = {}

        for i = 1, #Path do
            local a = Path[i]
            CurrentPath[i] = a
            if not files[a] and i ~= #Path then
                files[concat(CurrentPath, '/')] = {}
                files[concat(CurrentPath, '/') .. '/'] = files[concat(CurrentPath, '/')]
            elseif i == #Path then
                files[concat(CurrentPath, '/')] = tostring(content)
            end
        end
    end
    FileFuncs.makefolder = function(path)
        files[path] = {}
        files[path .. '/'] = files[path]
    end
    FileFuncs.isfolder = function(path) return type(files[path]) == 'table' end
    FileFuncs.isfile = function(path) return type(files[path]) == 'string' end
    FileFuncs.readfile = function(path) return files[path] end
    FileFuncs.appendfile = function(path, text2)
        FileFuncs.writefile(path, FileFuncs.readfile(path) .. text2)
    end
    FileFuncs.loadfile = function(path)
        if not FileFuncs.isfile(path) then error('File \'' .. tostring(path) .. '\' does not exist.', 2) return '' end

        local content = FileFuncs.readfile(path)

        local s, func = pcall(function()
            return loadstring(content)
        end)

        Id -= 1 -- ts works idk why

        return s and function(...)
            Append(`var{Id}({BeautifyTuple(...)})`)
            return func(...)
        end or nil, s
    end
    FileFuncs.delfolder = function(path)
        local f = files[path]
        if type(f) == 'table' then files[path] = nil end
    end
    FileFuncs.delfile = function(path)
        local f = files[path]
        if type(f) == 'string' then files[path] = nil end
    end
    FileFuncs.listfiles = function(path)
        if not path or path == '' then
            local Files = {}
            for i, v in pairs(files) do
                if #i:split('/') == 1 then insert(Files, i) end
            end
            return Files
        end
        if type(files[path]) ~= 'table' then return error(path .. ' is not a folder.') end
        local Files = {}
        for i in pairs(files) do
            if startswith(i, path .. '/') and not endswith(i, '/') and i ~= path and #i:split('/') == (#path:split('/') + 1) then insert(Files, i) end
        end
        return Files
    end

    for FuncName, Func in next, FileFuncs do
        BaseEnv[FuncName] = function(...)
            --print("Called", FuncName, ...)

            local Var, Success, Value = GetVar(), pcall(Func, ...)

            Define(Var, `{FuncName}({BeautifyTuple(...)})`)

            if Var then PotentialTypes[Var] = find({"isfile", "isfolder"}, FuncName) and "boolean" or "string" end

            if not Success then
                Append(`-- file system error here`)

                Value = nil
            end

            return FallbackValue(Var, Value)
        end
    end

    local function GetExecutorFunction(f)
        return CreateFunction(function()
            if Settings.hookOp then
                local v1, v2 = GetVar(), GetVar()

                Append(`local {v1}, {v2} = {f}()`)

                SetInternal(v1, "Swift")
                SetInternal(v2, "3.0.0")

                return Spy(v1, v2)
            end

            Append(f .. "()")
            return "Swift", "3.0.0"
        end, f)
    end

    BaseEnv.getexecutorname = GetExecutorFunction("getexecutorname")
    BaseEnv.identifyexecutor = GetExecutorFunction("identifyexecutor")

    local TickCalls = 0;

    local function tick(): number
        TickCalls += 1

	    return os.clock() + (os.time() - os.time(os.date("*t", os.clock()))) + TickCalls / 10
    end

    BaseEnv.os = HookLib("os", {
        time = function(...)
            local Time = os.time() + TimeOffset

            local Var = GetVar()
            Define(Var, `os.time({select('#', ...) > 0 and BeautifyTuple(...) or ''})`)

            if Settings.hookOp then
                SetInternal(Var, Time)
                PotentialTypes[Var] = "number"

                return Spy(Var)
            end

            return Time
        end,
        clock = function(...)
            local Time = os.clock() + TimeOffset

            local Var = GetVar()
            Define(Var, `os.clock({select('#', ...) > 0 and BeautifyTuple(...) or ''})`)

            if Settings.hookOp then
                SetInternal(Var, Time)
                PotentialTypes[Var] = "number"

                return Spy(Var)
            end

            return Time
        end
    })

    BaseEnv.tick = function() -- we spoof tick 🤫
        local Var = GetVar()
        Define(Var, "tick()", "__call")

        local Value = tick()

        if Settings.hookOp then
            SetInternal(Var, Value)

            return Spy(Var)
        end
        return Value
    end

    BaseEnv.wait = function(x) --! maybe change later
        Wait(x)

        local Var = DefineVar(`wait({x and Beautify(x) or ""})`)

        return FallbackValue(Var, math.random(1, 100) / 100)
    end

    BaseEnv.getmetatable = function(tbl)
        if Variables[tbl] then return nil end

        local tp = typeof(tbl)

        if tp ~= "table" and tp ~= "userdata" then error("invalid argument #1 to 'getmetatable', 'table' or 'userdata' expected got '" .. tp .. '') end
        local x = getmetatable(tbl)
        local mt = MetaTables[tbl] or x

        if mt and mt.__metatable then return mt.__metatable end
        return mt
    end

    BaseEnv.setmetatable = function(tbl, mt)
        local Path = Variables[tbl]
        local mt2 = getmetatable(tbl)

        if not Tables[tbl] and Path or (mt2 and typeof(mt2) ~= "table") then
            if Path then
                Append(`setmetatable({Beautify(tbl)}, {Beautify(mt)})`)
            end

            error("attempt to modify a readonly table")
        end

        MetaTables[tbl] = mt

        if mt and mt.__metatable then
            local t2 = table.clone(mt)
            t2.__metatable = nil
            
            return setmetatable(tbl, t2)
        end

        return setmetatable(tbl, mt)
    end

    local ValidDebug = {
        --"getconstant", "getconstants", "setconstant", "getupvalue", "getupvalues", "setupvalue", "getproto", "getprotos", "setproto",
        --"getstack", "setstack", "getregistry", "getlocal", "getlocals", "setlocal"
        "info"
    }

    local Infos = {}

    local function getmt(p)
        return CreateFunction(function(t)
            local Var = Variables[t]
            local MT = MetaTables[t]

            local Beautified = "{" .. Beautify(t, nil, {ignore_mt = true}) .. "}"
            local BeautifiedMT = MT and Beautify(MT) or "nil"

            local N = DefineVar(`{p}(setmetatable({Beautified}, {BeautifiedMT}))`)

            if Var then
                return Spy(N)
            end

            if typeof(t) ~= "table" then error(`invalid argument #1 to '{p}', table expected got '{typeof(t)}'`) end

            return FallbackValue(N, MT)
        end, p)
    end

    local function setmt(p)
        return CreateFunction(function(t, mt)
            local mtrms = DefineVar(`{p}({BeautifyTuple(t, mt)})`)

            local t1, t2 = typeof(t), typeof(mt)

            assert(t1 == "table", "invalid argument #1 to 'setmetatable', table expected got '" .. t1 .. "'")
            assert(t1 == "table", "invalid argument #2 to 'setmetatable', table expected got '" .. t2 .. "'")

            return FallbackValue(mtrms, setmetatable(t, mt))
        end, p)
    end

    BaseEnv.debug = setmetatable({
        getinfo = CreateFunction(function(x)
            if Infos[x] then return Infos[x] end

            print("getinfo",x)

            local _x = x
            local Type = Typeof(x)

            if Type ~= "function" and Type ~= "number" then return {numparams = 1, is_vararg = true, what = 'C', line = 1} end

            x = typeof(x) == "table" and pcall or x -- a c function i guess?

            local numparams, isvrg = debuginfo(x, 'a')
            local Var = GetVar()

            local Value = {
                ["line"] = 1,
                ["func"] = CreateFunction(debuginfo(x, "f"), `{Var}.func`),
                ['numparams'] = numparams,
                ['is_vararg'] = isvrg and 1 or 0,
                ['what'] = debuginfo(x, 's') == '[C]' and 'C' or 'Lua'
            }

            Define(Var, `debug.getinfo({Beautify(_x, nil, {ignore_funcs = true})})`)

            if Settings.hookOp then
                Variables[Value] = Var

                SetInternal(Var, Value)

                local s = Spy(Var)

                Infos[_x] = s

                return s
            end

            local mt = setmetatable(Value, {
                __tostring = function() return Var end
            })

            Variables[mt] = Var

            return mt
        end, "debug.getinfo"),
        setmetatable = setmt("debug.setmetatable"),
        traceback = CreateFunction(function(a)
            assert(not a or typeof(a) == "string", "invalid argument #1 to 'traceback' (string expected got " .. typeof(a) .. ")")

            local trace = debug.traceback(a)
            local lines = split(trace, "\n")
            local out = {}

            for _, v in next, lines do
                --v = gsub(v, ":%d+:", ":1:")
                if not match(v, "%[string \".*main\"%]") then
                    v = gsub(v, "string \"luau%.load%(.-%)\"", TraceId)
                    insert(out, v)
                end
            end --> covering my traces:)

            return concat(out, "\n")
        end, "debug.traceback"),
        info = CreateFunction(function(t, i)
            t = GetInternalValue(t)

            local Var = DefineVar(`debug.info({Beautify(t, Nest, {ignore_funcs=true})}, {Beautify(i)})`)

            if Variables[t] then
                return Spy(Var)
            end

            local result = debuginfo(typeof(t) == "number" and t + 2 or t, i)
            return result
        end, "debug.info"),
        getmetatable = getmt("debug.getmetatable"),
        getrawmetatable = getmt("debug.getrawmetatable")
    }, GetMetatable("debug", {
        __index = function(_, Key)
            local Var = GetVar()
            Define(Var, `{Index(Key, "debug")}`, "__index")

            if find(ValidDebug, Key) then
                return CreateFunction(function(...)
                    Append(`{Var}({BeautifyTuple(...)})`)

                    return nil -- nil
                end, Var)
            end

            return nil
        end
    }))

    BaseEnv.getrawmetatable = getmt("getrawmetatable")
    BaseEnv.setrawmetatable = setmt("setrawmetatable")

    BaseEnv.hookexpr = Settings.hookOp and function(id, val) Hooks[id] = val end or nil
    BaseEnv.tostring = function(Str)
        local Path = Variables[Str]

        if Functions[Str] then
            local addr = GetAddress(Path or tostring(random(1, 1e6)), "function")
            local Var = DefineVar(`tostring({Str})`)

            return FallbackValue(Var, addr)
        end

        if Path then --> Hey get off my variable
            if Path == "loadstring" then return nil end
            if PotentialTypes[Path] == "EnumItem" then return FallbackValue(DefineVar(`tostring({Path})`), Path) end

            local Type = PotentialTypes[Path] or GetType(Path)

            local addr = GetAddress(Path or tostring(random(1, 1e6)), Type or "function")
            local Var = DefineVar(`tostring({Str})`)

            return FallbackValue(Var, addr)
        end

        return tostring(Str)
    end
    BaseEnv.tonumber = function(n, base)
        local Var = Variables[n]
        if Var then
            local v = DefineVar(`tonumber({BeautifyTuple(n, base)})`)

            local val = GetInternalValue(n)
            local value = tonumber(val, base)

            if value then Append("--" .. value) else Append("--no value") end

            return FallbackValue(v, value)
        end

        return tonumber(n, base)
    end

    local CustomEnvs = {}
    local CustomPrefix;

    local function createEnv(path)
        CustomEnvs[path] = CustomEnvs[path] or {}

        local Self = CustomEnvs[path]

        local meta = GetMetatable(path, {
            __index = function(_, GKey)
                print("Index",path,GKey)

                local Var = DefineVar(Index(GKey, path))

                local Value = Self[GKey]

                if Value then return Value[1] end

                CustomPrefix = path

                return FallbackValue(Var, Self[GKey])
            end,
            __newindex = function(_, Key, Value)
                if Key == "25ms was here :)" then return end

                Self[Key] = {Value}

                Append(`{Index(Key, path)} = {Beautify(Value)}`)
            end
        })

        Variables[meta] = path --! not gonna mess with this rn

        return meta
    end

    local genv, _g, _shared = createEnv("getgenv()"), createEnv("_G"), createEnv("shared")

    local TaskCalls = 0
    local TaskHook = {
        synchronize = Spy("task.synchronize"),
        desynchronize = Spy("task.desynchronize")
    }

    local Task = setmetatable({}, {
        __index = function(_, Key)
            local Actual = task[Key] or TaskHook[Key]

            if not Actual then return end --! prevent crashes due to task[123] or whatever

            local Indexed = Index(Key, "task")

            return CreateFunction(function(...) --! might have to change this later due to antitampers
                TaskCalls += 1

                local Args = table.pack(...)

                for i = 1, Args.n do
                    local Arg = Args[i]

                    if typeof(Arg) == "function" then
                        Args[i] = setfenv(Arg, Env) -- so it cant use any real functions
                    end

                    local mt = typeof(Arg) == "table" and getmetatable(Arg)

                    if mt and mt.__tostring then return Actual(...) end --> antitamper
                end

                if Pristine and TaskCalls < 7 then
                    --print("Ok bro just take my money",TaskCalls,Indexed,Args)

                    return Actual(unpack(Args))
                end

                OpCountCheck()

                --print(Indexed, ...)
                local Value;
                if Indexed == "task.wait" then -- task.wait(1), value = WAIT_PER_FRAME * 60 (60 fps)
                    Value = Wait(Args[1])
                end

                local Var = DefineVar(`{Indexed}({BeautifyTuple(unpack(Args))})`)

                return FallbackValue(Var, Value)
            end, Indexed)
        end
    })

    BaseEnv.task = Task
    BaseEnv.spawn = CreateFunction(function(f)
        return Task.spawn(f)
    end, "spawn")

    local function Type(x, a)
        local p = Variables[a]
        local potential = PotentialTypes[p]

        if Functions[a] then
            potential = "function"
        end

        --print(x,potential,a,typeof(a))

        if potential then
            local Var = GetVar()
            Define(Var, `{x}({BeautifyTuple(a)})`)

            SetInternal(Var, potential)

            return Settings.hookOp and Spy(Var) or potential
        end

        if not p then return x == "type" and type(a) or typeof(a) end -- dont spy useless things

        local Var = GetVar()
        Define(Var, `{x}({Beautify(a)})`, "__call")

        local P = GetActualPath(p) or p
        local _type = GetType(P)

        if _type == "nil" and not Settings.spyexeconly then
            _type = ((x == "type" and type or typeof)(a)) -- true type
        end

        if p == "game" or p == "workspace" or p == "Workspace" or p == "Game" then --! hardcoded for now
            if x == "type" then
                _type = "userdata"
            else
                _type = "Instance"
            end
        end

        SetInternal(Var, _type)

        return Spy(Var)
    end

    BaseEnv.type, BaseEnv.typeof = function(x) return Type("type", x) end, function(x) return Type("typeof", x) end

    BaseEnv.islclosure = function(a)
        Define(GetVar(), `islclosure({Beautify(a)})`, "__call")

        if IsExecutor(a) then return false end
            
        return islclosure(a)
    end

    BaseEnv.iscclosure = function(a)
        Define(GetVar(), `iscclosure({Beautify(a)})`, "__call")

        if IsExecutor(a) or iscclosure(a) then return true end

        return false
    end

    BaseEnv.xpcall = function(a, b)
        return xpcall(setfenv(a, Env), setfenv(b, Env))
    end

    BaseEnv.setfenv = function(a, b) --! not thi
        if getmetatable(b) then return end --> we don't wanna override, do we?

        setfenv(a, setmetatable(b, Env))
    end

    BaseEnv.loadstring, BaseEnv.load = Loadstring, load
    BaseEnv.getgenv, BaseEnv._G = function() return genv end, _g

    BaseEnv.collectgarbage = function(t)
        if t ~= "count" then error("collectgarbage must be called with 'count'; use gcinfo() instead") end

        return collectgarbage("count")
    end

    local function DoIgnore(Key, Value) -- true = ignore the variable
        if typeof(Key) ~= "string" then return false end
        if not find({12, 13, 14, 15, 17, 32}, #Key) then return false end
        
        -- must have: 1 uppercase, 1 lowercase

        local Uppercase = match(Key, "[A-Z]")
        local Lowercase = match(Key, "[a-z]")
        --local Number = match(Key, "%d")

        return Uppercase and Lowercase-- and Number
    end

    local IterFuncs = {"pairs", "ipairs", "next"}
    local Getfenv = CreateFunction(function(lvl)
        lvl = lvl or 0
        
        if lvl < 0 or lvl == math.huge then return error("invalid argument #1 to 'getfenv' (level must be non-negative)") end
        if typeof(lvl) == "number" and (lvl // 1 ~= lvl or lvl > Nest + 1) then return error("invalid argument #1 to 'getfenv' (invalid level)") end -- float??

        top_level.fenv = true

        return GetMetatable("getfenv()", {
            __index = function(_, Key)
                if Prometheus[Key] then return end

                CustomPrefix = "fenv"

                return Env[Key]
            end,
            __newindex = function(_, Key, Value)
                CustomPrefix = "fenv"

                Env[Key] = Value
            end
        })
    end, "getfenv()")

    SetInternal("getfenv", Getfenv)
    Variables[Getfenv] = "getfenv"

    for i, v in next, EnvValues do
        BaseEnv[i] = v[1]
    end

    for i, v in next, BaseEnv do
        if typeof(v) == "function" and not find(SafeEnv, i) then
            --BaseEnv[i] = newcclosure(v)
            BaseEnv[i] = CreateFunction(function(...)
                if not TrueEnv[i] and not Prometheus[i] then OpCountCheck() end

                return v(...)
            end, i) -- maybe aura?
            PotentialTypes[i] = "function"
        end
    end

    local mt = {
        __index = function(_, Key)
            --OpCountCheck()

            if Key == "getconstants" or Key == "_ENV" or Key == "bat" then return end

            local Genv = CustomEnvs["getgenv()"][Key]

            if Genv then return Genv[1] end

            if Key == "_G" then return _g end
            if Key == "shared" then return _shared end
            if Key == "getfenv" then return Getfenv end

            local Value = EnvValues[Key]
            local IsExec = IsExecutor(Key)

            if Key == "next" then
                return function(tbl, k)
                    local Var = Variables[tbl]

                    if k or not Var then
                        if Variables[k] then return nil, nil end

                        return next(tbl, k)
                    end

                    --if Var == "getfenv()" then return next(Env) end

                    return getmetatable(tbl).__iter(Var, "next")(k)
                end
            end

            if find(IterFuncs, Key) then
                return CreateFunction(function(t, k)
                    local Variable = Variables[t]
                    if Variable then
                        return getmetatable(t).__iter(Variable, Key)
                    else
                        return TrueEnv[Key](t, k)
                    end
                end, Key)
            end

            local Indexed = Index(Key, CustomPrefix)

            CustomPrefix = nil

            if DoIgnore(Key) or (Settings.spyexeconly and (not IsExec or Value)) then return (Value or {})[1] end

            if Value then
                if typeof(Value[1]) ~= "function" then return Value[1] end

                return CreateFunction(function(...)
                    local CurrentVar = GetVar()
                    Append(`local {CurrentVar} = {Indexed}({BeautifyTuple(...)})`)

                    local StartLine = #Output
                    local Old = table.clone(Output)
                    local Out = pack(Value[1](...))

                    Output = Old --^^ ONLY extract the return values, ignore the code

                    for i = 1, Out.n do
                        local arg = Out[i]
                        if Variables[arg] then
                            local Vars = {}
                            local Line = ""

                            for _ = 1, Out.n do
                                local Var = GetVar()
                                insert(Vars, Spy(Var))

                                Line ..= `{Var}, `
                            end

                            Line = sub(Line, 1, -3)

                            Output = move(Output, 1, StartLine - 1, 1, {}) -- remove the lil thing we added a first lines ago
                            Append(`local {Line} = {Indexed}({BeautifyTuple(...)})`)
                            
                            return unpack(Vars)
                        end
                    end

                    return unpack(Out)
                end, Indexed)
            end

            return Spy(Indexed)
        end,
        __newindex = function(_, Key, Value)
            --[[if typeof(Value) == "table" then -- this guy is annoying as shit
                DefineTable(Value, GetVar())
            end]]

            if typeof(Value) == "function" then pcall(setfenv, Value, Env) end

            EnvValues[Key] = {Value} --? for nil & false

            --!REMOVE THE ISEXECUTOR DUDE 💔💔 (the only reason its there is because moonsec does print = something and everything breaks)

            local IsVar = Variables[Value]

            if Key == "heh" or Key == "ff" then Pristine = true return end --! ignore 25ms antitamper i guess?

            if (Settings.spyexeconly and (typeof(Value) == "table" or typeof(Value) == "function") and not IsVar) then return end
            if DoIgnore(Key, Value) or IsExecutor(Key) then return end

            if not IsVar then SetInternal(Key, Value) end
            
            local Indexed = Index(Key, CustomPrefix)
            CustomPrefix = nil

            --AddNest()
            local Beautified = Beautify(Value, Nest + 1)
            --AddNest(-1)

            Append(`{Indexed} = {Beautified}`)
        end,
        __tostring = function() return "getfenv()" end,
        __metatable = nil
    }

    local Spied = table.clone(getmetatable(Spy("getfenv()")))
    for i, v in next, mt do Spied[i] = v end

    Env = setmetatable(BaseEnv, Spied)

    Variables[Env] = "getfenv()"

    SetInternal("getfenv()", Env)

    local function SpyParams(Amount)
        local Params = {}

        for i = 1, Amount do
            insert(Params, Spy(`arg{i}{Suffix}`, {
                OriginalIsParam = true
            }))
        end

        insert(Params, Spy("...", {
            OriginalIsParam = true
        }))

        return Params
    end

    SpiedParams = SpyParams(ParamCount)

    local LoadedFunc;

    if typeof(Source) == "function" then
        if Variables[getfenv(Source)] then -- Env already exists.
            LoadedFunc = Source -- keeps the old env's nest..? Bad!!
        end
    else
        LoadedFunc = setfenv(Loaded, Env)
    end

    local Result = pack(pcall(LoadedFunc, unpack(SpiedParams)))
    local Message = not Result[1] and Result[2]
    local Out = ""

    function GetParamStr()
        if ParamCount == 0 then return "" end
        
        local str = {}

        for i = 1, ParamCount do
            insert(str, `arg{i}{Suffix}`)
        end

        return `local {concat(str, ", ")} = ...\n`
    end

    if Original and #Params > 0 then
        Out = GetParamStr()

        Output = move(Output, 1, #Output, 2, {Out})
    end

    for _, n in WaitingEnds do
        for x = 1, n do print("Closing empty statement", _, n) CloseStatement() end
    end

    local NewOut = {} -- so Val.Line is accurate
    for _, v in next, Output do
        for _, l in next, string.split(v, "\n") do
            insert(NewOut, l)
        end
    end

    Out = concat(NewOut, "\n")

    if not Result[1] then --! not success
        Out ..= `\n{Tab}error({Beautify(Message)})\n`

        Output = {}

        for _, v in next, Output do
            Out ..= v .. "\n"
        end
    else
        local ReturnValue = ""

        for i = 2, Result.n do -- nil values
            local x = Result[i]

            ReturnValue ..= Beautify(x) .. ", "
        end

        ReturnValue = sub(ReturnValue, 1, -3)

        if #ReturnValue > 0 then
            Out ..= `\n{Tab}return {ReturnValue}\n`
        end
    end

    Out = gsub(Out, "\n%s*\n", "\n")

    if Original then
        if top_level.fenv then
            Out = "local fenv = getfenv()\n\n" .. Out
        end
    end

    return Out
end

function Obf(Path)
    local Args = {
        `Prometheus/cli.lua`,
        "--LuaU",
        "--preset", "Minify"
    }

    if Settings.checkIndex then
        insert(Args, "--checkIndex")
    end

    insert(Args, Path)

    local POut = process.exec("lua", Args) --> unparser in written in lua, so run it.

    print("Output:",POut.stdout)
    warn("Errors:",POut.stderr)

    local Out = Path

    local FilePath = `{Out}.obfuscated.lua`

    local s, Content = pcall(fs.readFile, FilePath)
    if not DONT_DELETE_FILES and fs.isFile(FilePath) then fs.removeFile(FilePath) end
    if not s then return `--err\n{GenerateId(10)} = ("unable to parse this file (hookOp issue, try disabling it)")` end

    return Content
end

local function Decode(File, raw)
    Settings.outfile = Settings.outfile or "out.lua"

    File = File or Settings.input_file

    local function Save(x)
        fs.writeFile(Settings.outfile, x or "-- file doesn't exist")
    end

    local s, Source = pcall(fs.readFile, File)
    if not s then return Save() end

    print("Obfuscating")

    local ObfStart = clock()
    local SourceCode = Settings.hookOp and not raw and Obf(File) or Source

    print("Took",clock() - ObfStart,"seconds to obfuscate")

    local Start = clock()

    local Success, Code = pcall(Dump, SourceCode, nil, true)

    local End = clock() - Start

    print("Took",End,"seconds to process.",Success)

    if type(Code) == "userdata" or not Success then --! error
        Code = `error({format("%q", tostring(Code))}) --internal error`
    end

    Code = gsub(Code, "%.%.%.:", "(...):")

    local discord = "discord.gg/threaded or discord.gg/aqfudJEEeE"
    
    local Out = `-- This file was generated with UnveilR {Settings.version or "testing version"} at {discord}.\n\n{Code}`

    Out = gsub(Out, "%[string \\\"[^\n]*main\\\"%]", "[internal]") -- hide errors
    Out = gsub(Out, "C:\\\\[^\n]*main:", "[internal]:") -- hide errors
    Out = gsub(Out, `%[string \\"luau.load%(...%)\\"%]`, "[script]")

    if DIDNT_PARSE then
        Out = "--err\n" .. Out
    end

    Save(Out)

    if IsTesting then fs.writeFile("logs/logs.txt", concat(LOGS, "\n")) end
end

--return Decode("obf/ifcheck.txt")
--return Decode("obf/1mdollar.lua")
--return Decode("obf/rayfield.txt")
return Decode("luraph/script1.txt")