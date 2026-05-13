local net = require("@lune/net")
local handle = net.socket("localhost:8000")

print(handle)