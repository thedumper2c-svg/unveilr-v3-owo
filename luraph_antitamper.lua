local unfakedLine, finalLine;
local errMessage = "[internal]:891: attempt to call a nil value"
local startPos, endPos, line = string.find(errMessage, ":(%d+)[:\\r\\n]") -- 11, 15, 891
if not startPos or not endPos then end -- probably crashes (or returns) if true

unfakedLine = string.sub(errMessage, startPos + 1, endPos - 1)
    --> 12, 14 -> gets the actual line to make sure its not faked
finalLine = string.char(string.byte(errMessage, startPos + 1, endPos - 1))
    --> gets the actual line yet again (string.char cancels out string.byte, its pretty much the same as string.sub but with extra protection)

if not unfakedLine or not finalLine then end -- maybe return or crash

if (line == unfakedLine) then
    if (unfakedLine == finalLine) then
    else
    while true do end -- with a few other things, i just oversimplified ts
    end
end