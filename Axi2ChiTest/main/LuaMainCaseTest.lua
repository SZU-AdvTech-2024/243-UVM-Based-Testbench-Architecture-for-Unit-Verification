local dma = require "EnvComponents"
local cfg = cfg
local axi = require "AXI4MasterAgent"
local AXI4BurstType = axi.AXI4BurstType
local AXI4MasterErrorCode = axi.AXI4MasterErrorCode
local AXI4WriteTask = axi.AXI4WriteTask
local AXI4ReadTask = axi.AXI4ReadTask
local AXI4MasterAgnet = axi.AXI4MasterAgnet

local axi_master = dma.axi_master
local bridge_monitor = dma.bridge_monitor

local clock = dut.clock:chdl()

--------------------------------
-- Print with cycles info (this will increase simulation time)
--------------------------------
local old_print = print
local print = function(...)
	old_print("[LuaMain] ", ...)
end

--------------------------------
-- Function
--------------------------------

local function wait_axi_finish()
	local MAX_LIMIT = 5000
	local ok = clock:posedge_until(MAX_LIMIT, function()
		return axi_master:is_finish()
	end)

	assert(ok, "[wait_axi_finish] timeout!")
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

	-- write test case
	-- merge test

	-- axi_master:write(AXI4WriteTask(
	-- 	13,
	-- 	0x700000070020,
	-- 	-- 0x0020,  --addr
	-- 	{ "0x1234", "0x2678", "0x3468" }, -- datas
	-- 	{ 0x0000ffff, 0xffff0000, 0x0000ffff },
	-- 	2,
	-- 	4,
	-- 	AXI4BurstType.INCR
	-- ))
	-- wait_axi_finish()

	-- test write len convert to number of request

	-- axi_master:write(AXI4WriteTask(
	-- 	2,
	-- 	0x700000000020,
	-- 	-- 0x0020,  --addr
	-- 	{ "0x1234", "0x2678", "0x3468", "0x4188" }, -- datas
	-- 	{ 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff },
	-- 	3,
	-- 	5,
	-- 	AXI4BurstType.FIXED
	-- ))
	-- wait_axi_finish()

	-- len == 0 Axi mmio request

	-- axi_master:write(AXI4WriteTask(
	-- 	0,
	-- 	0x800000002020, --address
	-- 	{ "0x5678" }, -- datas
	-- 	{ 0xffffffff },
	-- 	0, --len
	-- 	5,
	-- 	AXI4BurstType.INCR
	-- ))
	-- wait_axi_finish()

	-- -- read test case
	-- -- long length test case

	axi_master:read(AXI4ReadTask(
		1, -- id
		0x8000000a0040, -- addr
		2, -- len
		5, -- size
		AXI4BurstType.INCR -- burst
	))
	wait_axi_finish()

	-- -- mmio read case test

	-- axi_master:read(AXI4ReadTask(
	-- 	0, -- id
	-- 	0x800000030000, -- addr
	-- 	-- 0x80000037, -- addr
	-- 	4, -- len
	-- 	5, -- size
	-- 	AXI4BurstType.INCR -- burst
	-- ))
	-- wait_axi_finish()

	-- -- len = 0 Axi request test case

	-- axi_master:read(AXI4ReadTask(
	-- 	0, -- id
	-- 	0x200000070020, -- addr
	-- 	-- 0x80000037, -- addr
	-- 	0, -- len
	-- 	5, -- size
	-- 	AXI4BurstType.INCR -- burst
	-- ))
	-- wait_axi_finish()

	local cycles = 0

	local last_time = 0
	cfg.trace_mode = false
	-- cfg.shutdown_cycles = 1000 * 10000
	-- cfg.shutdown_cycles = 500 * 10000
	-- cfg.shutdown_cycles = 300 * 10000
	-- cfg.shutdown_cycles = 100 * 10000
	-- cfg.shutdown_cycles = 15 * 10000
	-- cfg.shutdown_cycles = 50 * 1000
	cfg.shutdown_cycles = 10 * 1000
	cfg.enable_shutdown = true

	local loop = function()
		if cycles % 10 == 0 then
			--print(#transaction_fifo,buble_num,cycles)
		end

		if cycles % 1000 == 0 and cycles ~= 0 then
			local speed = (os.clock() - last_time) * 1e3
			-- print(cycles, "Running...", os.clock())
			print(string.format("%d\tRunning...\t%.2f", cycles, speed))
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
