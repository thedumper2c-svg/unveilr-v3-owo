local v1 = string.char;
local v2 = string.byte;
local v3 = string.sub;
local v4 = bit32 or bit;
local v5 = v4.bxor;
local v6 = table.concat;
local v7 = table.insert;
local function v8(p1, p2)
    local v9 = {};
    for v10 = 1, #p1 do
        v7(v9, v1(v5(v2(v3(p1, v10, v10 + 1)), v2(v3(p2, 1 + v10 % #p2, 1 + v10 % #p2 + 1))) % 256)); 
    end;
    return v6(v9); 
end;
if game:GetService('CoreGui'):FindFirstAncestor("Meow") then
    print("Nice"); 
end;