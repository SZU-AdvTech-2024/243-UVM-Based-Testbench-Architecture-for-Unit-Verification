local chi = require "CHI"
local class = require "pl.class"
local scb = require "AxiScoreboard"
local texpect = require "TypeExpect"
local utils = require "LuaUtils"
local axiMaster = require "AXI4MasterAgent"

local OpcodeREQ = chi.OpcodeREQ
local OpcodeDAT = chi.OpcodeDAT
local OpcodeRSP = chi.OpcodeRSP

local tostring = tostring
local assert = assert
local type = type
local print = print
local rawset = rawset
local tonumber = tonumber
local format = string.format
local bit_rshift = bit.rshift
local bit_lshift = bit.lshift
local bit_and    = bit.band
local bit_or     = bit.bor
local bit_not    = bit.bnot
local table_insert = table.insert
local table_remove = table.remove
local log = math.log

local Fix  = axiMaster.AXI4BurstType.FIXED
local Incr = axiMaster.AXI4BurstType.INCR
local Wrap = axiMaster.AXI4BurstType.WRAP
local AXI4BurstType = utils.enum_define({
	name = "AXI4BurstType",

	FIXED = 0,
	INCR = 1,
	WRAP = 2,
})

local AxiMonitor = class()

function AxiMonitor:_init(name, aw_bundle, w_bundle, b_bundle, ar_bundle, r_bundle, txreq_bundle, txrsp_bundle, txdat_bundle, rxrsp_bundle, rxdat_bundle, verbose, enable, db)
	self.name = name

	texpect.expect_abdl(aw_bundle, "aw_bundle", {
		"valid",
		"ready",
		"addr",
		"id",
		"len",
		"size",
		"burst",
		"lock",
		"cache",
		"prot",
		"qos",
	})

	texpect.expect_abdl(w_bundle, "w_bundle", {
		"valid",
		"ready",
		"strb",
		"data",
		"last",
	})

	texpect.expect_abdl(b_bundle, "b_bundle", {
		"valid",
		"ready",
		"resp",
		"id",
	})

	texpect.expect_abdl(ar_bundle, "ar_bundle", {
		"valid",
		"ready",
		"addr",
		"id",
		"len",
		"size",
		"burst",
		"lock",
		"cache",
		"prot",
		"qos",
	})

	texpect.expect_abdl(r_bundle, "r_bundle", {
		"valid",
		"ready",
		"id",
		"last",
		"resp",
		"data",
	})

	self.aw = aw_bundle
	self.w = w_bundle
	self.b = b_bundle
	self.ar = ar_bundle
	self.r = r_bundle

	texpect.expect_abdl(txreq_bundle, "txreq_bundle", {
		"valid",
		"ready",
		"opcode",
		"addr",
		"txnID",
		"size",
	})

	texpect.expect_abdl(txrsp_bundle, "txrsp_bundle", {
		"valid",
		"ready",
		"opcode",
		"txnID",
	})

	texpect.expect_abdl(txdat_bundle, "txdat_bundle", {
		"valid",
		"ready",
		"opcode",
		"txnID",
		"data",
		"dataID",
	})

	texpect.expect_abdl(rxrsp_bundle, "rxrsp_bundle", {
		"valid",
		"ready",
		"opcode",
		"dbID",
		"txnID",
	})

	texpect.expect_abdl(rxdat_bundle, "rxdat_bundle", {
		"valid",
		"ready",
		"opcode",
		"txnID",
		"data",
		"dataID",
		"dbID",
	})

	self.txreq = txreq_bundle
	self.txrsp = txrsp_bundle
	self.txdat = txdat_bundle

	self.rxrsp = rxrsp_bundle
	self.rxdat = rxdat_bundle

	self.db = db
	if db then
		self.enable_db = true	
		texpect.expect_database(db, "DMABridge.db", {
			"cycles => INTEGER",
			"channel => TEXT",
			"opcode => TEXT",
			"address => TEXT",
			"txn_id => INTEGER",
			"db_id => INTEGER",
			"data => TEXT",
		})
		self.txreq_chnl_name = "DMABridge_TXREQ"
		self.txrsp_chnl_name = "DMABridge_TXRSP"
		self.txdat_chnl_name = "DMABridge_TXDAT"
		self.rxrsp_chnl_name = "DMABridge_RXRSP"
		self.rxdat_chnl_name = "DMABridge_RXDAT"
		self.ar_chnl_name    = "DMABridge_AR"
		self.r_chnl_name     = "DMABridge_R"
		self.aw_chnl_name    = "DMABridge_AW"
		self.w_chnl_name     = "DMABridge_W"
		self.b_chnl_name     = "DMABridge_B"
	else
		self.enable_db = false
	end

	self.ar_addr_pool = {}
	self.aw_addr_pool = {}
	self.aw_addr_queue = {}
	self.ar_addr_queue = {}

	self.txreq_txnid_pool_for_read = {} --<txn_id, address>
	self.txreq_txnid_pool_for_write = {} --<txn_id, address>
	self.rxrsp_dbid_pool_for_write = {} --<dbid, address>

	self.cycles = 0
	self.verbose = verbose or false
	self.enable = enable or true

	print("Create AxiMonitor => ", "name: " .. self.name, "verbose: " .. tostring(self.verbose))
end

function AxiMonitor:_log(...)
	if self.verbose then
		print("[" .. self.cycles .. "]", "[" .. self.name .. "]", ...)
	end
end

function AxiMonitor:sample_txreq()
	local txreq = self.txreq
	if txreq.valid:is(1) and txreq.ready:is(1) then
		local opcode = txreq.opcode:get()
		local origin_addr = txreq.addr:get() + 0ULL
		local address = bit_rshift(origin_addr + 0ULL, 5)
		local txn_id = txreq.txnID:get()
		local size = txreq.size:get()
		local _ = self.verbose and self:_log("[TXREQ]", OpcodeREQ(opcode), "address: " .. utils.to_hex_str(origin_addr), "txn_id: " .. txn_id, "size: " .. size)

		if opcode == OpcodeREQ.ReadOnce or opcode == OpcodeREQ.ReadNoSnp then
			local to_hex_addr = utils.to_hex_str(address)
			self.txreq_txnid_pool_for_read[txn_id] = origin_addr
			local exist = self.ar_addr_pool[to_hex_addr] ~= nil
			assert(exist == true, format("read address is not legal! address: %s txn_id: %d opcode: %s", utils.to_hex_str(origin_addr), txn_id, OpcodeREQ(opcode)))
			self.ar_addr_pool[to_hex_addr] = self.ar_addr_pool[to_hex_addr] - 1
			if self.ar_addr_pool[to_hex_addr] == 0 then
				self.ar_addr_pool[to_hex_addr] = nil
			end
		elseif opcode == OpcodeREQ.WriteUniquePtl or opcode == OpcodeREQ.WriteNoSnpPtl or opcode == OpcodeREQ.WriteUniqueFull or opcode == OpcodeREQ.WriteNoSnpFull then
			local to_hex_addr = utils.to_hex_str(address)
			self.txreq_txnid_pool_for_write[txn_id] = origin_addr
			local exist = self.aw_addr_pool[to_hex_addr] ~= nil
			assert(exist == true, format("write address is not legal! address: %s txn_id: %d opcode: %s", utils.to_hex_str(origin_addr), txn_id, OpcodeREQ(opcode)))
			self.aw_addr_pool[to_hex_addr] = self.aw_addr_pool[to_hex_addr] - 1
			if self.aw_addr_pool[to_hex_addr] == 0 then
				self.aw_addr_pool[to_hex_addr] = nil
			end
		else
			assert(false, "Unknown opcode => " .. OpcodeREQ(opcode))
		end
		
		if self.enable_db then
			self.db:save(
				self.cycles,
				self.txreq_chnl_name,
				OpcodeREQ(opcode),
				utils.to_hex_str(origin_addr),
				txn_id,
				"/",
				"/"
			)
		end

	end
end
function AxiMonitor:sample_txrsp()
	local txrsp = self.txrsp
	if txrsp.valid:is(1) and txrsp.ready:is(1) then
		local opcode = txrsp.opcode:get()
		local txn_id = txrsp.txnID:get()
		local _ = self:_log("[TXRSP]", OpcodeRSP(opcode), "txn_id: " .. txn_id)
	end
end

function AxiMonitor:sample_txdat()
	local txdat = self.txdat
	if txdat.valid:is(1) and txdat.ready:is(1) then
		local opcode = txdat.opcode:get()
		local txn_id = txdat.txnID:get()
		local data = txdat.data:get()
		local data_id = txdat.dataID:get()

		local address = 0
		if opcode == OpcodeDAT.NCBWrDataCompAck or OpcodeDAT.NonCopyBackWrData then
			address = self.rxrsp_dbid_pool_for_write[txn_id]
			assert(address ~= nil, format("address is nil! opcode: %s data: %s txn_id: %d", OpcodeDAT(opcode), utils.to_hex_str(data[1]), txn_id))

			if scb.enable then
				local addr = tonumber(bit_rshift(address + 0ULL, 5))
				if data_id == 2 then
					addr = addr + 1
				end
				scb:check("[" .. self.name .. "]" .. "[TXDAT]", addr, data, self.cycles)
			end
		else
			assert(false, "Unknown opcode => " .. OpcodeDAT(opcode))
		end

		local _ = self:_log("[TXDAT]", OpcodeDAT(opcode), "address: " .. utils.to_hex_str(address), "data: " .. utils.to_hex_str(data[1]), "txn_id: " .. txn_id, "data_id: " .. data_id)
	end
end

function AxiMonitor:sample_rxrsp()
	local rxrsp = self.rxrsp
	if rxrsp.valid:is(1) and rxrsp.ready:is(1) then
		local opcode = rxrsp.opcode:get()
		local db_id = rxrsp.dbID:get()
		local txn_id = rxrsp.txnID:get()

		local address = 0
		if opcode == OpcodeRSP.CompDBIDResp then
			address = self.txreq_txnid_pool_for_write[txn_id]
			if address == nil then
				assert(false, format("txn_id of rxrsp is illegal => txn_id: %d opcode: %s", txn_id, OpcodeRSP(opcode)))
			else
				self.rxrsp_dbid_pool_for_write[db_id] = address
			end
			self.txreq_txnid_pool_for_write[txn_id] = nil
		elseif opcode == OpcodeRSP.DBIDResp then
			address = self.txreq_txnid_pool_for_write[txn_id]
			if address == nil then
				assert(false, format("txn_id of rxrsp is illegal => txn_id: %d opcode: %s", txn_id, OpcodeRSP(opcode)))
			else
				self.rxrsp_dbid_pool_for_write[db_id] = address
			end
		elseif opcode == OpcodeRSP.Comp then
			address = self.txreq_txnid_pool_for_write[txn_id]
			if address == nil then
				assert(false, format("txn_id of rxrsp is illegal => txn_id: %d opcode: %s", txn_id, OpcodeRSP(opcode)))
			else
				self.txreq_txnid_pool_for_write[txn_id] = nil
			end
		end

		local _ = self:_log("[RXRSP]", OpcodeRSP(opcode), "txn_id: " .. txn_id, "db_id: " .. db_id)
	end
end

function AxiMonitor:sample_rxdat()
	local rxdat = self.rxdat
	if rxdat.valid:is(1) and rxdat.ready:is(1) then
		local opcode = rxdat.opcode:get()
		local txn_id = rxdat.txnID:get()
		local data = rxdat.data:get()
		local dataid = rxdat.dataID:get()
		local dbid = rxdat.dbID:get()

		local address = 0ULL
		if opcode == OpcodeDAT.CompData then
			address = self.txreq_txnid_pool_for_read[txn_id]
			if address == nil then
				assert(false, "error TxnID: " .. txn_id)
			else
				local addr = bit_rshift(tonumber(address) + 0ULL, 5)
				if dataid == 2 then
					addr = addr + 1
				end
				if scb.enable then
					scb:update_data(self.name .. "[RXDAT]", tonumber(addr), data, self.cycles)
				end
			end
		else
			assert(false, "Unknown opcode => " .. OpcodeDAT(opcode))
		end

		local _ =
			self:_log("[RXDAT]", OpcodeDAT(opcode), "address: " .. utils.to_hex_str(address), "txn_id: " .. txn_id, "db_id: " .. dbid, "data: " .. utils.to_hex_str(data[1]), "data_id: " .. dataid)
	end
end

function AxiMonitor:sample_ar()
	local ar = self.ar
	if ar.valid:is(1) and ar.ready:is(1) then
		local arid = ar.id:get()
		local size = ar.size:get()
		local origin_addr = ar.addr:get() + 0ULL
		local addr = bit_rshift(origin_addr + 0ULL, 5)
		local len = ar.len:get()
		local burst = ar.burst:get()
		local lenBits = log(len + 1, 2)
		for i = 0, len, 1 do
			local chiAddr = 0ULL
			if burst == Fix then
				chiAddr = addr
				local to_hex_addr = utils.to_hex_str(chiAddr)
				if self.ar_addr_pool[to_hex_addr] == nil then
					self.ar_addr_pool[to_hex_addr] = 1
				else
					self.ar_addr_pool[to_hex_addr] = 1 + self.ar_addr_pool[to_hex_addr]
				end
				if self.ar_addr_queue[arid] == nil then
					self.ar_addr_queue[arid] = {}
				end
				table_insert(self.ar_addr_queue[arid], chiAddr)
			elseif burst == Incr then
				chiAddr = addr + i
				local to_hex_addr = utils.to_hex_str(chiAddr)
				if chiAddr % 2 == 0 or i == 0 then
					self.ar_addr_pool[to_hex_addr] = 1
				end
				if self.ar_addr_queue[arid] == nil then
					self.ar_addr_queue[arid] = {}
				end
				table_insert(self.ar_addr_queue[arid], chiAddr)
			elseif burst == Wrap then
				local chiAddr = addr + i
				local mask = bit_lshift(1, lenBits) - 1
				local destAddr = bit_or(bit_and(mask, chiAddr), bit_not(bit_or(bit_not(addr), mask))) + 0ULL
				local to_hex_addr = utils.to_hex_str(destAddr)
				if self.ar_addr_pool[to_hex_addr] == nil  then
					self.ar_addr_pool[to_hex_addr] = 1
				else
					self.ar_addr_pool[to_hex_addr] = self.ar_addr_pool[to_hex_addr] + 1
				end
				if self.ar_addr_queue[arid] == nil then
					self.ar_addr_queue[arid] = {}
				end
				table_insert(self.ar_addr_queue[arid], destAddr)
			end
		end
		local _ = self:_log("[AXIAR]", "arid: " .. utils.to_hex_str(arid), "address: " .. utils.to_hex_str(origin_addr), "len: " .. utils.to_hex_str(len), "size: " .. utils.to_hex_str(size), "burst: " .. AXI4BurstType(burst))
	end
end

function AxiMonitor:sample_r()
	local r = self.r
	if r.valid:is(1) and r.ready:is(1) then
		local rid = r.id:get()
		local data = r.data:get()
		local last = r.last:get()
		local addr = self.ar_addr_queue[rid][1] + 0ULL

		if scb.enable then
			scb:check(self.name .. "[AXIR]", tonumber(addr), data, self.cycles)
				table_remove(self.ar_addr_queue[rid], 1)
		end
		local _ = self:_log("[AXI_R]", "rid:" .. utils.to_hex_str(rid), "data: " .. utils.to_hex_str(data[1]), "last: " .. tostring(last))
	end
end

function AxiMonitor:sample_aw()
	local aw = self.aw
	if aw.valid:is(1) and aw.ready:is(1) then
		local awid = aw.id:get()
		local origin_addr = aw.addr:get()
		local size = aw.size:get()
		local addr = bit_rshift(origin_addr + 0ULL, 5)
		local len = aw.len:get()
		local burst = aw.burst:get()
		local lenBits = log(len + 1, 2)
		for i = 0, len, 1 do
			local chiAddr = 0ULL
			if burst == Fix then
				chiAddr = addr
				local to_hex_addr = utils.to_hex_str(chiAddr)
				if self.aw_addr_pool[to_hex_addr] == nil then
					self.aw_addr_pool[to_hex_addr] = 1
				else
					self.aw_addr_pool[to_hex_addr] = 1 + self.aw_addr_pool[to_hex_addr]
				end
				table_insert(self.aw_addr_queue, chiAddr)
			elseif burst == Incr then
				chiAddr = addr + i
				local to_hex_addr = utils.to_hex_str(chiAddr)
				if (chiAddr % 2 == 0 or i == 0) and self.aw_addr_pool[to_hex_addr] == nil then
					self.aw_addr_pool[to_hex_addr] = 1
				elseif (chiAddr % 2 == 0 or i == 0) and self.aw_addr_pool[to_hex_addr] ~= nil then
					self.aw_addr_pool[to_hex_addr] = 1 + self.aw_addr_pool[to_hex_addr]
				end
				table_insert(self.aw_addr_queue, chiAddr)
			elseif burst == Wrap then
				chiAddr = addr + i
				local mask = bit_lshift(1, lenBits) - 1
				local destAddr = bit_or(bit_and(mask, chiAddr), bit_not(bit_or(bit_not(addr), mask))) + 0ULL
				local to_hex_addr = utils.to_hex_str(destAddr)
				if self.aw_addr_pool[to_hex_addr] == nil then
					self.aw_addr_pool[to_hex_addr] = 1
				else
					self.aw_addr_pool[to_hex_addr] = 1 + self.aw_addr_pool[to_hex_addr]
				end
				table_insert(self.aw_addr_queue, destAddr)
			end
		end

		local _ = self:_log("[AXI_AW]", "awid:" .. utils.to_hex_str(awid), "address: " .. utils.to_hex_str(origin_addr), "size: " .. utils.to_hex_str(size), "len: " .. len, "burst: " .. AXI4BurstType(burst))
	end
end

function AxiMonitor:sample_w()
	local w = self.w
	if w.valid:is(1) and w.ready:is(1) then
		local data = w.data:get()
		local strb = w.strb:get()
		local last = w.last:get()
		local addr = self.aw_addr_queue[1]
		table_remove(self.aw_addr_queue, 1)
		if scb.enable then
			scb:update_data(self.name .. "[AXIW]", tonumber(addr), data, self.cycles)
		end
		local _ = self.verbose and self:_log("[AXI_W]", "data:" .. utils.to_hex_str(data[1]), "strbe: " .. utils.to_hex_str(strb), "last: " .. tostring(last))
	end
end

function AxiMonitor:sample_b()
	local b = self.b
	if b.valid:is(1) and b.ready:is(1) then
		local bid = b.id:get()

		local _ = self.verbose and self:_log("[AXI_B]", "bid: " .. utils.to_hex_str(bid))
	end
end

function AxiMonitor:sample_all(cycles)
	if self.enable == false then
		return
	end

	assert(cycles ~= nil)
	self.cycles = cycles

	self:sample_aw()
	self:sample_w()
	self:sample_b()
	self:sample_ar()
	self:sample_r()

	self:sample_txreq()
	self:sample_txdat()
	self:sample_txrsp()
	self:sample_rxrsp()
	self:sample_rxdat()
end

return AxiMonitor
