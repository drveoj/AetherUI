--[[--------------------------------------------------------------------------
	Print the skins Core/Palette.lua computes, for Tools/preview.py.

	A skin is no longer written out token by token: it is eight chrome values
	composed with the shared semantic colours when the file loads (see CHROME
	and Compose there). So the preview asks the palette itself rather than
	parsing its source, which is how it fell a generation behind before.

	Run:  luajit Tools/palette_dump.lua [skin ...]
	Out:  one line per colour token:  skin <tab> token <tab> r,g,b,a[;r,g,b,a...]
	      a token that is a list of colours (a gradient pair) has them joined
	      by ';'. Values are 0..1. Booleans print as true/false.
----------------------------------------------------------------------------]]

local root = (arg and arg[0] or ""):match("^(.*)[/\\]Tools[/\\][^/\\]*$") or "."
local A = {}
local chunk = assert(loadfile(root .. "/Core/Palette.lua"))
chunk("Lattice", A)
local P = A.Palette

local function colour(v)
	return type(v) == "table" and type(v[1]) == "number" and #v >= 3
end

local function fmt(v)
	return string.format("%.6f,%.6f,%.6f,%.6f", v[1], v[2], v[3], v[4] or 1)
end

local want = {}
for i = 1, #(arg or {}) do want[#want + 1] = arg[i] end
if #want == 0 then want = P.order end

for _, name in ipairs(want) do
	local skin = assert(P.skins[name], "no skin called " .. tostring(name))
	local keys = {}
	for k in pairs(skin) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local v = skin[k]
		if colour(v) then
			print(name .. "\t" .. k .. "\t" .. fmt(v))
		elseif type(v) == "table" and colour(v[1]) then
			local parts = {}
			for i, c in ipairs(v) do
				if colour(c) then parts[i] = fmt(c) end
			end
			print(name .. "\t" .. k .. "\t" .. table.concat(parts, ";"))
		elseif type(v) == "boolean" then
			print(name .. "\t" .. k .. "\t" .. tostring(v))
		end
	end
end
