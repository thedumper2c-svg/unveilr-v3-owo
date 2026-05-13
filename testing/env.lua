--// Services
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

--// Root container
local rootFolder = Instance.new("Folder")
rootFolder.Name = "EnvMockerTest"
rootFolder.Parent = Workspace

--// Model
local model = Instance.new("Model")
model.Name = "TestModel"
model.Parent = rootFolder

--// Primary Part
local basePart = Instance.new("Part")
basePart.Name = "Base"
basePart.Size = Vector3.new(10, 1, 10)
basePart.Position = Vector3.new(0, 5, 0)
basePart.Anchored = true
basePart.Material = Enum.Material.Concrete
basePart.Color = Color3.fromRGB(120, 120, 120)
basePart.CFrame = CFrame.new(0, 5, 0) * CFrame.Angles(0, math.rad(15), 0)
basePart.Parent = model

model.PrimaryPart = basePart

-- Sanity Check 1: Check if the base part's CFrame is set correctly
assert(basePart.CFrame.Position == Vector3.new(0, 5, 0), "Base part's CFrame is not at the correct position!")
assert(basePart.CFrame == CFrame.new(0, 5, 0) * CFrame.Angles(0, math.rad(15), 0), "Base part's CFrame rotation mismatch!")

--// Repeated Parts
for i = 1, 5 do
	local p = Instance.new("Part")
	p.Name = "Pillar_" .. i
	p.Size = Vector3.new(1, 6, 1)
	p.Material = Enum.Material.Metal
	p.BrickColor = BrickColor.new("Really black")
	p.CFrame =
		basePart.CFrame
		* CFrame.new(i * 2 - 6, 3, 0)

	p.Parent = model

	-- Sanity Check 2: Ensure that each pillar's position is where expected
	local expectedCFrame = basePart.CFrame * CFrame.new(i * 2 - 6, 3, 0)
	assert(p.CFrame.Position == expectedCFrame.Position, "Pillar " .. i .. " is not in the expected position!")

	-- Weld
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = basePart
	weld.Part1 = p
	weld.Parent = p

	CollectionService:AddTag(p, "TestPillar")
end


-- Sanity Check 3: Check if there are any parts tagged as "TestPillar"
local testPillars = CollectionService:GetTagged("TestPillar")
assert(#testPillars > 0, "No pillars tagged with 'TestPillar' found!")

--// Attachments & Constraint
local attachment0 = Instance.new("Attachment")
attachment0.Position = Vector3.new(0, 0.5, 0)
attachment0.Parent = basePart

local attachment1 = Instance.new("Attachment")
attachment1.Position = Vector3.new(0, -0.5, 0)
attachment1.Parent = model:FindFirstChild("Pillar_1")

local spring = Instance.new("SpringConstraint")
spring.Attachment0 = attachment0
spring.Attachment1 = attachment1
spring.Stiffness = 50
spring.Damping = 5
spring.Visible = true
spring.Parent = basePart

-- Sanity Check 4: Ensure spring stiffness and damping are correctly set
assert(spring.Stiffness == 50, "Spring stiffness is incorrect!")
assert(spring.Damping == 5, "Spring damping is incorrect!")

--// Value objects
local numberValue = Instance.new("NumberValue")
numberValue.Name = "Health"
numberValue.Value = 100
numberValue.Parent = model

local vectorValue = Instance.new("Vector3Value")
vectorValue.Name = "SpawnOffset"
vectorValue.Value = Vector3.new(0, 10, 0)
vectorValue.Parent = model

local cframeValue = Instance.new("CFrameValue")
cframeValue.Name = "SavedCFrame"
cframeValue.Value = basePart.CFrame
cframeValue.Parent = model

-- Sanity Check 5: Validate if health value is correct
assert(numberValue.Value == 100, "Health value is not 100!")

-- Sanity Check 6: Check vector value (should be Vector3.new(0, 10, 0))
assert(vectorValue.Value == Vector3.new(0, 10, 0), "Spawn offset is not as expected!")

--// Attributes
model:SetAttribute("IsTestModel", true)
model:SetAttribute("Version", 1)

-- Sanity Check 7: Ensure the model has the expected attributes
assert(model:GetAttribute("IsTestModel") == true, "IsTestModel attribute is incorrect!")
assert(model:GetAttribute("Version") == 1, "Version attribute is not correct!")

--// GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TestGui"
screenGui.ResetOnSpawn = false

local frame = Instance.new("Frame")
frame.Size = UDim2.fromScale(0.3, 0.2)
frame.Position = UDim2.fromScale(0.35, 0.4)
frame.BackgroundColor3 = Color3.fromHSV(0.6, 0.4, 0.9)
frame.BorderSizePixel = 2
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame

local uiStroke = Instance.new("UIStroke")
uiStroke.Thickness = 2
uiStroke.Color = Color3.new(1, 1, 1)
uiStroke.Parent = frame

-- Sanity Check 8: Check if the frame size is correct
assert(frame.Size == UDim2.fromScale(0.3, 0.2), "Frame size is not correct!")
assert(frame.Position == UDim2.fromScale(0.35, 0.4), "Frame position is not correct!")

--// Tween test
local tweenInfo = TweenInfo.new(
	1.5,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.InOut,
	-1,
	true
)

local tween = TweenService:Create(frame, tweenInfo, {
	BackgroundTransparency = 0.5
})

-- Sanity Check 9: Ensure the tween has been created and is working
assert(tween ~= nil, "Tween creation failed!")

--// ParticleEmitter
local emitter = Instance.new("ParticleEmitter")
emitter.Rate = 10
emitter.Lifetime = NumberRange.new(1, 2)
emitter.Speed = NumberRange.new(2, 4)
emitter.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.5),
	NumberSequenceKeypoint.new(1, 0)
})
emitter.Parent = basePart

-- Sanity Check 10: Check if emitter properties are valid
assert(emitter.Rate == 10, "Particle emitter rate is incorrect!")
assert(emitter.Size.Keypoints[1].Value == 0.5, "Particle emitter size is not as expected!")

--// RaycastParams (datatype only)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Blacklist
rayParams.FilterDescendantsInstances = { model }
rayParams.IgnoreWater = true

-- Sanity Check 11: Ensure raycast parameters are set correctly
assert(rayParams.IgnoreWater == true, "RaycastParams should ignore water!")

--// Finalize
model:PivotTo(CFrame.new(0, 5, 0))
tween:Play()

print("Env mocker test script executed successfully with sanity checks")