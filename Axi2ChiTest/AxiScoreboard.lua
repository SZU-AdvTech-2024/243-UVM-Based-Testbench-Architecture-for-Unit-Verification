class = require "pl.class"
utils = require "LuaUtils"
local bit = bit or require "bit"

local cfg = cfg
local colors = colors
local verilua_warning = verilua_warning

local print = print
local assert = assert
local type = type
local bit_rshift = bit.rshift
local bit_lshift = bit.lshift
local format = string.format
local table_insert = table.insert

local Scoreboard = class()

function Scoreboard:_init(name)
	self.name = name or "BridgeScoreboard"
	self.cycles = 0
	self.pool = {}
	self.enable = cfg.enable_scoreboard
	self.verbose = cfg.verbose_scoreboard
end

function Scoreboard:_log(...)
	if self.verbose then
		print("[" .. self.cycles .. "]", "[" .. self.name .. "]", ...)
	end
end

function Scoreboard:update_data(info, address, data, cycles)
	if not self.enable then
		return
	end
	data = data[1]
	self.cycles = cycles or 0
	if self.pool[address] == nil then
		self.pool[address] = {}
	end
	table_insert(self.pool[address], data)
	local _ = self:_log(info .. " update => address: " .. utils.to_hex_str(address) .. " data: " .. utils.to_hex_str(data))
end

function Scoreboard:check(info, address, data, cycles)
	if not self.enable then
		return
	end
	if type(address) == "table" then
		address = address[1]
	end
	data = data[1]
	local scb_data = self.pool[address][1]
	table.remove(self.pool[address], 1)
	if scb_data == nil then
		scb_data = 0
		verilua_warning(format("data in scb is nil addr => addr: 0x%x", bit_lshift(address, 5)))
	end
	if scb_data ~= data then
		assert(
			false,
			"\n"
				.. "["
				.. self.cycles
				.. "]"
				.. info
				.. "data mismatch! address: "
				.. utils.to_hex_str(bit_lshift(address, 5))
				.. "\n\t"
				.. colors.green
				.. "expect: "
				.. utils.to_hex_str(scb_data)
				.. colors.reset
				.. "\n\t"
				.. colors.red
				.. "got  : "
				.. utils.to_hex_str(data)
				.. colors.reset
		)
	end
	local _ = self.verbose and self:_log(info .. " address " .. utils.to_hex_str(bit_lshift(address, 5)) .. " data " .. utils.to_hex_str(data) .. " check success! ")
end

function Scoreboard:check_addr_exist(address)
	local idx = tonumber(address + 0ULL)
	local data = self.pool[idx]
	if data == nil then
		return false
	end
	return true
end

function Scoreboard:clear(address)
	if type(address) == "table" then
		address = address[1]
	end
	local idx = tonumber(address + 0ULL)
	self.pool[idx] = nil
end

local global_scb = Scoreboard()

return global_scb
