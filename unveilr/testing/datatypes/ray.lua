local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Blacklist
rayParams.FilterDescendantsInstances = { workspace }
rayParams.IgnoreWater = true

print("Ok!",rayParams)