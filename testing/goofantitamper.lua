task.defer(function()
	coroutine.yield()
end)

task.defer(function()
	local success1: boolean, result1: string? | any = pcall(function() (require)("@self") end)
	local success2: boolean, result2: string? | any = pcall(function() (require)("@game") end)
	local success3: boolean, result3: string? | any = pcall(function() (require)("@lune") end)
	local success4: boolean, result4: string? | any = pcall(function() workspace.Terrain:GetMaterialColor(Enum.Material.Air) end)
	local success5: boolean, result5: string? | any = pcall(function() workspace.Terrain:GetMaterialColor(Enum.Material.Metal) end)
	local success6: boolean, result6: string? | any = pcall(function() return workspace.Terrain:GetMaterialColor(Enum.Material.Grass) end)
	local _turn_string = function(str) 
		local characters = ""

		local ran = Random.new(tick()*math.random()*math.random())
		for i = 1,ran:NextNumber(20,30) do
			characters = characters .. utf8.char(ran:NextNumber(97,8000))
		end

		return str .. ("\0"):rep(25) .. characters
	end
	local GOOF_CRASH = function()
		(("sigma"):rep(20000) ..  "\000\00\000\0"):find(".*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*.*#\000\00\0\000\00")
		return nil;
	end;
	if not string.find(result1, "Unable to require module from given path") then
		GOOF_CRASH()
		return "get fucked lmao"
	end
	if not string.find(result2, "Unable to require module from given path") then
		GOOF_CRASH()
		return "get fucked lmao"
	end
	if not string.find(result3, "Path contains unsupported") then
		GOOF_CRASH()
		return "get fucked lmao"
	end
	if _turn_string("goofy") == "goofy" then
		GOOF_CRASH()
		return "get fucked lmao"
	end
	if not workspace.Terrain then
		GOOF_CRASH()
		return "get fucked lmao"
	end
	workspace.Terrain:SetAttribute("GoofyCheck", true)
	if #workspace:QueryDescendants("Terrain[$GoofyCheck][ClassName = Terrain]") < 1 then
		GOOF_CRASH()
		return "get fucked lmao"
	end
	if result4 ~= "Unsupported terrain material" then
		GOOF_CRASH()
		return "get fucked lmao"
	end
	if result5 ~= "Invalid terrain material" then
		GOOF_CRASH()
		return "get fucked lmao"
	end
	if typeof(result6) ~= "Color3" then
		GOOF_CRASH()
		return "get fucked lmao"
	end

	--rest of the script
	print("ENV LOGGER - PASSED")
end)

coroutine.yield()