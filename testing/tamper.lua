getgenv().antiSpy = {
	url = "", -- if you want to send webhook on tampering attempt, put dsc url here.
	maxSafety = false -- enables loading junk variables, will crash attacker's exec if triggered.
}

local msg = "tamper detected boiiii, how did you get this far?🤔"
do
	local x = {
		task.defer,
		task.wait,
		task.spawn,
		debug.getinfo,
		getfenv,
		setmetatable,
		pcall
	}
	local a = false;
	x[1](function()
		a = true
	end);
	x[2]()
	if not a then
		print(msg)
		return error()
	end
	local b = false;
	x[7](function()
		b = true
	end)
	if not b then
		print(msg)
		return error()
	end
	local c = x[4](x[2])
	if not c or c.what ~= "C" then
		print(msg)
		return error()
	end
	local d = false;
	x[3](function()
		d = true
	end);
	x[2]()
	if not d then
		print(msg)
		return error()
	end
	if x[5] then
		local e = x[5](0)
		if e.CHECKINDEX or e._G ~= _G then
			print(msg)
			return error()
		end
	end
	local f = x[6]({}, {
		__index = function()
			return true
		end
	})
	if not f.test then
		print(msg)
		return error()
	end
end

local function logAttempt(reason)
	local data = {
		["embeds"] = {
			{
				["title"] = "Security Alert",
				["description"] = reason,
				["color"] = 16727614,
				["footer"] = {
					["text"] = "User: " .. game:GetService("Players").LocalPlayer.Name .. " | Executor: " .. (identifyexecutor and identifyexecutor() or "Unknown shit exploit")
				}
			}
		}
	}
	local headers = {
		["content-type"] = "application/json"
	}
	local request = (syn and syn.request) or (http and http.request) or http_request or request
	if request and getgenv().antiSpy.url ~= "" then
		request({
			Url = getgenv().antiSpy.url,
			Method = "POST",
			Headers = headers,
			Body = game:GetService("HttpService"):JSONEncode(data)
		})
	end
end

local getreg = (debug and debug.getregistry)
local getinfo = (debug and debug.getinfo)
local current_ls = getgenv().loadstring
local success, i = pcall(function()
	return getinfo(current_ls)
end)
local is_hooked = false
local detected_what = "N/A"

if success and i then
	if i.what ~= "C" then
		is_hooked = true
		detected_what = i.what
	end
end

local candidates = 0
if getreg then
	for _, v in pairs(getreg()) do
		if type(v) == "function" then
			local info = getinfo and getinfo(v)
			if (info and info.name == "loadstring") or (v == current_ls) then
				candidates = candidates + 1
				if info and info.what ~= "C" then
					is_hooked = true
					detected_what = info.what
				end
			end
		end
	end
end

if candidates > 1 or is_hooked then
	if getgenv().antiSpy.url ~= "" then
		local reason = "**Tamper Detected!**\n**Language:** " .. tostring(detected_what) .. "\n**Detections:** " .. candidates
		logAttempt(reason)
	end
	game:GetService("Players").LocalPlayer:Kick("Tamper Detected!")
	return
end
if getgenv().antiSpy.maxSafety then
	for i = 1, 50 do
		loadstring("-- ACD BCD KYS" .. math.random(1, 10000) .. string.rep("A", 500000))
	end
end