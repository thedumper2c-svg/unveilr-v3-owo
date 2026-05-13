--// Create Part for testing the ParticleEmitter
local testPart = Instance.new("Part")
testPart.Name = "TestPart"
testPart.Size = Vector3.new(4, 1, 4)
testPart.Position = Vector3.new(0, 5, 0)
testPart.Anchored = true
testPart.Material = Enum.Material.SmoothPlastic
testPart.Parent = workspace

--// Create ParticleEmitter and test NumberSequenceKeypoint for Size
local emitter = Instance.new("ParticleEmitter")
emitter.Rate = 10
emitter.Lifetime = NumberRange.new(1, 2)
emitter.Speed = NumberRange.new(2, 4)

-- Create a NumberSequence with KeyPoints to test
local sequence = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.5),  -- At time = 0, the size is 0.5
    NumberSequenceKeypoint.new(0.5, 1),  -- At time = 0.5, the size is 1
    NumberSequenceKeypoint.new(1, 0.25)  -- At time = 1, the size is 0.25
})

-- Apply the sequence to the Size property of the ParticleEmitter
emitter.Size = sequence
emitter.Parent = testPart

--// Sanity Check: Test if the NumberSequenceKeypoints are correct
local keypoints = emitter.Size.Keypoints

-- Sanity Check 1: Ensure that the number of keypoints is 3
assert(#keypoints == 3, "Number of keypoints is not 3!")

-- Sanity Check 2: Check if the first keypoint (time = 0) has the correct value (0.5)
assert(keypoints[1].Time == 0 and keypoints[1].Value == 0.5, "First keypoint is incorrect!")

-- Sanity Check 3: Check if the second keypoint (time = 0.5) has the correct value (1)
assert(keypoints[2].Time == 0.5 and keypoints[2].Value == 1, "Second keypoint is incorrect!")

-- Sanity Check 4: Check if the third keypoint (time = 1) has the correct value (0.25)
assert(keypoints[3].Time == 1 and keypoints[3].Value == 0.25, "Third keypoint is incorrect!")

-- Print success message if all checks pass
print("NumberSequenceKeypoint test passed successfully!")
