--[[
    Comprehensive Roblox Environment Sanity Check
    This function performs deep validation to detect fake/mocked Roblox environments
    and ensures the code is running in a legitimate Roblox instance.
]]

local function isRobloxEnvironment()
    local checks = {}
    
    -- Phase 1: Basic Globals Check
    local env = getfenv()
    local robloxGlobals = {
        "game", "workspace", "script", "Instance", "Vector3", "CFrame",
        "UDim2", "Enum", "Color3", "BrickColor", "Ray", "Region3",
        "NumberSequence", "ColorSequence", "NumberRange", "Rect",
        "TweenInfo", "PhysicalProperties", "Faces", "Axes"
    }
    
    for _, globalName in ipairs(robloxGlobals) do
        if env[globalName] == nil then
            return false, "Missing Roblox global: " .. globalName
        end
    end
    table.insert(checks, "Basic globals present")
    
    -- Phase 2: Verify game is DataModel
    local success, isDataModel = pcall(function()
        return game:IsA("DataModel") and game.ClassName == "DataModel"
    end)
    if not success or not isDataModel then
        return false, "'game' is not a valid DataModel"
    end
    table.insert(checks, "game is valid DataModel")
    
    -- Phase 3: Check game has expected properties
    local gameProperties = {"PlaceId", "JobId", "PlaceVersion", "CreatorId", "CreatorType", "GameId"}
    for _, prop in ipairs(gameProperties) do
        local success = pcall(function()
            local _ = game[prop]
        end)
        if not success then
            return false, "game missing property: " .. prop
        end
    end
    table.insert(checks, "game has required properties")
    
    -- Phase 4: Verify critical services exist and are correct type
    local serviceChecks = {
        {"Players", "Players"},
        {"Workspace", "Workspace"},
        {"ReplicatedStorage", "ReplicatedStorage"},
        {"ReplicatedFirst", "ReplicatedFirst"},
        {"ServerStorage", "ServerStorage"},
        {"ServerScriptService", "ServerScriptService"},
        {"StarterGui", "StarterGui"},
        {"StarterPack", "StarterPack"},
        {"StarterPlayer", "StarterPlayer"},
        {"Teams", "Teams"},
        {"SoundService", "SoundService"},
        {"Chat", "Chat"},
        {"LocalizationService", "LocalizationService"},
        {"MarketplaceService", "MarketplaceService"},
        {"TeleportService", "TeleportService"},
        {"RunService", "RunService"},
        {"UserInputService", "UserInputService"},
        {"HttpService", "HttpService"},
        {"InsertService", "InsertService"},
        {"CollectionService", "CollectionService"},
        {"BadgeService", "BadgeService"},
        {"DataStoreService", "DataStoreService"},
        {"MessagingService", "MessagingService"},
        {"PathfindingService", "PathfindingService"},
        {"PhysicsService", "PhysicsService"},
        {"ProximityPromptService", "ProximityPromptService"},
        {"TextService", "TextService"},
        {"TweenService", "TweenService"},
        {"UserService", "UserService"},
        {"VoiceChatService", "VoiceChatService"},
    }
    
    local servicesFound = 0
    for _, serviceData in ipairs(serviceChecks) do
        local success, service = pcall(function()
            return game:GetService(serviceData[1])
        end)
        if success and service and service.ClassName == serviceData[2] then
            servicesFound = servicesFound + 1
        end
    end
    
    if servicesFound < #serviceChecks * 0.8 then -- At least 80% should be accessible
        return false, "Too few services accessible: " .. servicesFound .. "/" .. #serviceChecks
    end
    table.insert(checks, servicesFound .. " services accessible")
    
    -- Phase 5: Test Instance creation and destruction
    local instanceTypes = {"Part", "Folder", "Model", "Script", "LocalScript", "ModuleScript", 
                          "BindableEvent", "RemoteEvent", "RemoteFunction", "ObjectValue",
                          "IntValue", "StringValue", "BoolValue", "NumberValue"}
    
    for _, className in ipairs(instanceTypes) do
        local success, instance = pcall(function()
            local inst = Instance.new(className)
            local hasDestroy = typeof(inst.Destroy) == "function"
            inst:Destroy()
            return hasDestroy
        end)
        if not success or not instance then
            return false, "Cannot create/destroy: " .. className
        end
    end
    table.insert(checks, "Instance creation/destruction works")
    
    -- Phase 6: Verify data types work correctly with operations
    local success = pcall(function()
        -- Vector3 operations
        local v1 = Vector3.new(1, 2, 3)
        local v2 = Vector3.new(4, 5, 6)
        local v3 = v1 + v2
        assert(v3.X == 5 and v3.Y == 7 and v3.Z == 9, "Vector3 math failed")
        assert(v1.Magnitude > 0, "Vector3 Magnitude failed")
        
        -- CFrame operations
        local cf1 = CFrame.new(1, 2, 3)
        local cf2 = CFrame.Angles(math.pi/2, 0, 0)
        local cf3 = cf1 * cf2
        assert(cf3.Position.X == 1, "CFrame math failed")
        
        -- Color3
        local c1 = Color3.new(1, 0, 0)
        local c2 = Color3.fromRGB(255, 0, 0)
        assert(c1.R == 1, "Color3 failed")
        
        -- UDim2
        local u1 = UDim2.new(0.5, 100, 0.5, 100)
        assert(u1.X.Scale == 0.5 and u1.X.Offset == 100, "UDim2 failed")
        
        -- BrickColor
        local bc = BrickColor.new("Bright red")
        assert(bc.Name == "Bright red", "BrickColor failed")
        
        -- Enums
        assert(Enum.Material.Plastic, "Enum.Material failed")
        assert(Enum.PartType.Ball, "Enum.PartType failed")
    end)
    
    if not success then
        return false, "Data type operations failed"
    end
    table.insert(checks, "Data type operations validated")
    
    -- Phase 7: Check workspace properties
    local success = pcall(function()
        local ws = game:GetService("Workspace")
        assert(typeof(ws.CurrentCamera) == "Instance" or ws.CurrentCamera == nil, "CurrentCamera type wrong")
        assert(typeof(ws.Gravity) == "number", "Gravity type wrong")
        assert(typeof(ws:GetChildren()) == "table", "GetChildren failed")
        assert(typeof(ws.ChildAdded) == "RBXScriptSignal", "ChildAdded signal wrong")
    end)
    
    if not success then
        return false, "Workspace validation failed"
    end
    table.insert(checks, "Workspace properties valid")
    
    -- Phase 8: Check RunService methods
    local success = pcall(function()
        local rs = game:GetService("RunService")
        assert(typeof(rs.IsStudio) == "function", "IsStudio not a function")
        assert(typeof(rs.IsClient) == "function", "IsClient not a function")
        assert(typeof(rs.IsServer) == "function", "IsServer not a function")
        assert(typeof(rs.Heartbeat) == "RBXScriptSignal", "Heartbeat not a signal")
        assert(typeof(rs.RenderStepped) == "RBXScriptSignal" or rs.RenderStepped == nil, "RenderStepped invalid")
        
        -- These should return consistent values
        local isStudio = rs:IsStudio()
        local isClient = rs:IsClient()
        local isServer = rs:IsServer()
        assert(typeof(isStudio) == "boolean", "IsStudio didn't return boolean")
        assert(typeof(isClient) == "boolean", "IsClient didn't return boolean")
        assert(typeof(isServer) == "boolean", "IsServer didn't return boolean")
    end)
    
    if not success then
        return false, "RunService validation failed"
    end
    table.insert(checks, "RunService methods valid")
    
    -- Phase 9: Test Instance hierarchy and parenting
    local success = pcall(function()
        local folder = Instance.new("Folder")
        local part = Instance.new("Part")
        part.Parent = folder
        
        assert(part.Parent == folder, "Parenting failed")
        assert(#folder:GetChildren() == 1, "GetChildren failed")
        assert(folder:FindFirstChild("Part") == part, "FindFirstChild failed")
        
        part:Destroy()
        folder:Destroy()
        
        assert(part.Parent == nil, "Destroy didn't clear parent")
    end)
    
    if not success then
        return false, "Instance hierarchy test failed"
    end
    table.insert(checks, "Instance hierarchy works")
    
    -- Phase 10: Test events/signals
    local success = pcall(function()
        local bindable = Instance.new("BindableEvent")
        local fired = false
        
        local conn = bindable.Event:Connect(function()
            fired = true
        end)
        
        assert(typeof(conn) == "RBXScriptConnection", "Connection type wrong")
        assert(typeof(conn.Connected) == "boolean", "Connection.Connected missing")
        
        bindable:Fire()
        task.wait(0.01) -- Allow event to fire
        
        assert(fired == true, "Event didn't fire")
        
        conn:Disconnect()
        bindable:Destroy()
    end)
    
    if not success then
        return false, "Event/signal test failed"
    end
    table.insert(checks, "Events/signals work")
    
    -- Phase 11: Test task library (Roblox-specific)
    local success = pcall(function()
        assert(typeof(task) == "table", "task library missing")
        assert(typeof(task.wait) == "function", "task.wait missing")
        assert(typeof(task.spawn) == "function", "task.spawn missing")
        assert(typeof(task.defer) == "function", "task.defer missing")
        assert(typeof(task.delay) == "function", "task.delay missing")
        
        local waited = false
        task.spawn(function()
            waited = true
        end)
        task.wait(0.01)
        assert(waited == true, "task.spawn didn't execute")
    end)
    
    if not success then
        return false, "task library validation failed"
    end
    table.insert(checks, "task library validated")
    
    -- Phase 12: Verify typeof function (Roblox extension)
    local success = pcall(function()
        assert(typeof(game) == "Instance", "typeof(game) wrong")
        assert(typeof(Vector3.new()) == "Vector3", "typeof(Vector3) wrong")
        assert(typeof(CFrame.new()) == "CFrame", "typeof(CFrame) wrong")
        assert(typeof(workspace.ChildAdded) == "RBXScriptSignal", "typeof(signal) wrong")
    end)
    
    if not success then
        return false, "typeof validation failed"
    end
    table.insert(checks, "typeof function validated")
    
    -- Phase 13: Check script context
    if script == nil then
        return false, "script global is nil"
    end
    
    local success = pcall(function()
        assert(typeof(script) == "Instance", "script is not an Instance")
        assert(script:IsA("LuaSourceContainer"), "script not a LuaSourceContainer")
        local scriptType = script.ClassName
        assert(scriptType == "Script" or scriptType == "LocalScript" or scriptType == "ModuleScript" or scriptType == "CoreScript", "Invalid script type: " .. scriptType)
    end)
    
    if not success then
        return false, "script validation failed"
    end
    table.insert(checks, "script context valid")
    
    -- Phase 14: Memory/reference validation
    local success = pcall(function()
        local part1 = Instance.new("Part")
        local part2 = part1
        assert(part1 == part2, "Reference equality failed")
        part1:Destroy()
        assert(part1 == part2, "References diverged after destroy")
    end)
    
    if not success then
        return false, "Reference validation failed"
    end
    table.insert(checks, "Reference semantics valid")
    
    return true, "All checks passed: " .. table.concat(checks, ", ")
end

-- Run the comprehensive sanity check
local isRoblox, message = isRobloxEnvironment()

if not isRoblox then
    error("[SANITY CHECK FAILED] Environment is not legitimate Roblox: " .. message)
else
    print("[SANITY CHECK PASSED] Legitimate Roblox environment detected")
    print("Message: " .. message)
    
    -- Print environment details
    local rs = game:GetService("RunService")
    print("\nEnvironment Details:")
    print("  - Studio Mode: " .. tostring(rs:IsStudio()))
    print("  - Client Context: " .. tostring(rs:IsClient()))
    print("  - Server Context: " .. tostring(rs:IsServer()))
    print("  - PlaceId: " .. tostring(game.PlaceId))
    print("  - Script Type: " .. script.ClassName)
end

return isRoblox