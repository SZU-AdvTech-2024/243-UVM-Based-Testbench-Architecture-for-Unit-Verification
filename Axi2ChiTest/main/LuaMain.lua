local dma = require "EnvComponents"
local cfg = cfg
local axi = require "AXI4MasterAgent"
local AXI4BurstType = axi.AXI4BurstType
local AXI4MasterErrorCode = axi.AXI4MasterErrorCode
local AXI4WriteTask = axi.AXI4WriteTask
local AXI4ReadTask = axi.AXI4ReadTask
local AXI4MasterAgnet = axi.AXI4MasterAgnet
local CounterDelayer = require "CounterDelayer"
local random = math.random

local axi_master = dma.axi_master
local bridge_monitor = dma.bridge_monitor
local axi_addr_addr_gen = dma.axi_master_addr_gen
local axi_master_delayer = CounterDelayer(cfg.send_delay_min, cfg.send_delay_max)
local block_table = {}
local lshift = bit.lshift

local clock = dut.clock:chdl()

local AXI4BurstType = utils.enum_define({
	name = "AXI4BurstType",

	FIXED = 0,
	INCR = 1,
	WRAP = 2,
})

--------------------------------
-- Print with cycles info (this will increase simulation time)
--------------------------------
local old_print = print
local print = function(...)
	old_print("[LuaMain] ", ...)
end

--------------------------------
-- Main body
--------------------------------

local function lua_main()
	sim.dump_wave()
	-- assert(false)
	local clock = dut.clock:chdl()

	dut.reset = 1
	clock:posedge(10)
	dut.reset = 0

	clock:posedge(2000)

	local cycles = 0

	local last_time = 0
	cfg.trace_mode = false
	-- cfg.shutdown_cycles = 1000 * 10000
	-- cfg.shutdown_cycles = 500 * 10000
	-- cfg.shutdown_cycles = 300 * 10000
	-- cfg.shutdown_cycles = 100 * 10000
	-- cfg.shutdown_cycles = 15 * 10000
	cfg.shutdown_cycles = 500 * 1000
	-- cfg.shutdown_cycles = 10 * 1000
	cfg.enable_shutdown = true

	local function gen_random_hex()
		return string.format("0x%04X", random(0, 0xFFFF))
	end
	local function weightedRandomChoice()
		local choice = random(1, 100)
		if choice <= 80 then
			return 1
		elseif choice <= 90 then
			return 0
		else
			return 2
		end
	end

	local loop = function()
		if axi_master_delayer:fire() then
			local read_or_write = random(0, 1)
			local burst_mode = weightedRandomChoice()
			local addr = lshift(random(100, 80000), 5)
			local len = random(0, 4)
			if burst_mode == 2 then
				local len_choice = {1, 3}
				local index = random(1, #len_choice)
				len = len_choice[index]
			end
			local awid = random(0, 100)
			local arid = random(0, 100)
			if read_or_write == 1 then
				local data_pairs = {}
				local strb_pairs = {}
				for i = 1, len + 1 do
					table.insert(strb_pairs, 0xffffffff)
					local random_hex = gen_random_hex()
					table.insert(data_pairs, random_hex)
				end
				axi_master:write(AXI4WriteTask(
					awid,
					addr, --address
					data_pairs, -- datas
					strb_pairs,
					len, --len
					5,
					burst_mode
				))
			end
			if read_or_write == 0 then
				axi_master:read(AXI4ReadTask(
					arid,
					addr, --address
					len, --len
					5,
					burst_mode
				))
			end
		end

		if cycles % 1000 == 0 and cycles ~= 0 then
			local speed = (os.clock() - last_time) * 1e3
			-- print(cycles, "Running...", os.clock())
			print(string.format("%d\tRunning...\t%.2f", cycles, speed))
			io.flush()
			last_time = os.clock()
		end

		clock:posedge()
		cycles = cycles + 1
	end

	if cfg.enable_shutdown then
		for i = 0, cfg.shutdown_cycles do
			loop()
		end
	else
		while true do
			loop()
		end
	end

	print "Finish"
	sim.finish()
end

local function monitor_task()
	dut.clock:posedge()
	dut.reset:negedge()

	local cycles = 0
	local clock = dut.clock:chdl()
	while true do
		bridge_monitor:sample_all(cycles)
		clock:posedge()
		cycles = cycles + 1
	end
end

verilua "appendTasks"({
	main_task = lua_main,
	monitor_task = monitor_task,
})

verilua "startTask"({
	function()
		axi_master:init_resolve_backend()
	end,
})
