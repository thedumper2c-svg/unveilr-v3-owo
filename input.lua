if game:GetService("CoreGui") then
    print("CoreGui exists")
    if a then
        print("a & CoreGui both exist.")
    else
        print("a does not exist but CoreGui does.")
    end
else
    print("CoreGui is nil?")
end