local t = '';
(function(n)
	local l = n
	local o = 0
	local e = 0
	l = {
		(function(c)
			if o > 31 then
				return c
			end
			o = o + 1
			e = (e + 3381 - c) % 19
			--[[return (e % 3 == 1 and (function(l)
				if not n[l] then
					e = e + 1
					n[l] = (18);
					t = '\37';
					d = {
						function()
							d()
						end
					};
					t = t .. '\100\43';
				end
				return true
			end)'Rpnyw' and l[3](285 + c)) or (e % 3 == 0 and (function(l)
				if not n[l] then
					e = e + 1
					n[l] = (1);
				end
				return true
			end)'lWbWK' and l[2](c + 796)) or (e % 3 == 2 and (function(l)
				if not n[l] then
					e = e + 1
					n[l] = (34);
				end
				return true
			end)'VpcJO' and l[1](c + 236)) or c]]
		end)
	}
	l[1](3428)
end){};