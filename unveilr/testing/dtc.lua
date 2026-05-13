-- Nil Detection --

local x = Instance.new("Hat",game.Workspace)

x.Name = "unveilr_dtc1"
local cantsucceednext = false

if game.Workspace.unveilr_dtc1 then
	print("passed nil detection test 1")
else
	print("failed nil detection test 1")
	cantsucceednext = true
end

x:Destroy()

if not game.Workspace:FindFirstChild("unveilr_dtc1") and not cantsucceednext then
	print("passed nil detection test 2")
else
	print("failed nil detection test 2")
end

-- Missing or stack mismatch loadstring detection --
local s1,s2 = pcall(loadstring,"return true")
if s1 == true and s2 == true then
	local func1 = loadstring("return getfenv(2)")

	local func1_sucess,func1_result = pcall(func1)

	if not func1_sucess then
		print("failed stack check : ",func1_result)
	else
		if func1_result == getfenv(1) then
			print("passed stack check")
		else
			print("failed stack check - environments dont match")
		end
	end
end

-- shitty detection but skids will do anything --
-- error name detection --

local _,result = pcall(function()
	error("")
end)

if string.find(result,"unveilr") then
	print("found unveilr string in error. Try virtualizing name to not include your directories - use luau's loadstring to get [string 'stringhere']")
else
	print("passed error detection")
end


xpcall(
	function() 
		error("") 
	end,
	function() 
		local name,func = debug.info(4,"n")
		
		if name == "__call" then
			print("unveilr call hook detected - invalid stack!")
		end
	end
)

if not debug.getmemorycategory then
	print("missing roblox function - debug.getmemorycategory")
end

if not debug.setmemorycategory then
	print("missing roblox function - debug.setmemorycategory")
end

if not debug.resetmemorycategory then
	print("missing roblox function - debug.resetmemorycategory")
end

if not debug.dumpcodesize then
	print("missing roblox function - debug.dumpcodesize")
end

-- data types check -- (roblox only)

local ver = _VERSION

if ver == "Luau" then
	
	-- script automation here saves alot of time lol
	local datatypes = {
		["Axes"] = {
			"new"
		},
		["BrickColor"] = {
			"Blue",
			"White",
			"Yellow",
			"Red",
			"Gray",
			"palette",
			"New",
			"Black",
			"Green",
			"Random",
			"DarkGray",
			"random",
			"new",
		},
		["CatalogSearchParams"] = {
			"new"
		},
		["CFrame"] = {
			"Angles",
			"fromEulerAnglesYXZ",
			"fromRotationBetweenVectors",
			"lookAlong",
			"fromOrientation",
			"fromMatrix",
			"fromEulerAnglesXYZ",
			"fromEulerAngles",
			"lookAt",
			"fromAxisAngle",
			"new",
		},
		["Color3"] = {
			"fromHSV",
			"toHSV",
			"fromRGB",
			"new",
		},
		["ColorSequence"] = {
			"new",
		},
		["ColorSequenceKeypoint"] = {
			"new",
		},
		["Content"] = {
			"fromUri",
			"fromObject",
			"fromAssetId",
			"none",
		},
		["DateTime"] = {
			"now",
			"fromIsoDate",
			"fromUnixTimestampMillis",
			"fromLocalTime",
			"fromUniversalTime",
		},
		["Faces"] = {
			"new",
		},
		["FloatCurveKey"] = {
			"new",
		},
		["Font"] = {
			"fromId",
			"fromEnum",
			"fromName",
			"new",
		},
		["Instance"] = {
			"new",
			"fromExisting"
		},
		["NumberRange"] = {
			"new",
		},
		["NumberSequence"] = {
			"new",
		},
		["NumberSequenceKeypoint"] = {
			"new",
		},
		["OverlapParams"] = {
			"new",
		},
		["Path2DControlPoint"] = {
			"new",
		},
		["PathWaypoint"] = {
			"new",
		},
		["PhysicalProperties"] = {
			"new",
		},
		["Random"] = {
			"new",
		},
		["Ray"] = {
			"new",
		},
		["RaycastParams"] = {
			"new",
		},
		["Rect"] = {
			"new",
		},
		["Region3"] = {
			"new",
		},
		["Region3int16"] = {
			"new",
		},
		["RotationCurveKey"] = {
			"new",
		},
		["SharedTable"] = {
			"cloneAndFreeze",
			"clear",
			"clone",
			"isFrozen",
			"size",
			"increment",
			"update",
			"new",
		},
		["TweenInfo"] = {
			"new",
		},
		["UDim"] = {
			"new",
		},
		["UDim2"] = {
			"new",
		},
		["Vector2"] = {
			"new",
		},
		["Vector2int16"] = {
			"new",
		},
		["Vector3"] = {
			"new",
		},
		["Vector3int16"] = {
			"new",
		},
	}
	
	local env = getfenv()
	
	for Name,ReqFields in datatypes do
		local Type = env[Name]
		
		if not Type then
			print("DataType : ",Name," was not defined - detected")
		else
			local failed = false
			for _,ReqField in ReqFields do
				local Field = Type[ReqField]
				if not Field or type(Field) ~= "function" and typeof(Field) ~= "Content" then
					print("DataType : ",Name," missing field : ",ReqField)
					failed = true
				end
			end
			
			if not failed then
				print("DataType : ",Name," is sync'ed with roblox - no detections here other than potential creation detections")
			else
				print("DataType : ",Name," has possible detection vectors from nil fields, check above for missing fields ^")
			end
		end
	end
end