-- Configuration -----------------------------------------------------------

local AxiMonitor = require "AxiMonitor"
local axi = require "AXI4MasterAgent"
local LuaDataBase = require "LuaDataBase"
local cfg = cfg
local AXI4MasterAgnet = axi.AXI4MasterAgnet

local assert = assert
local table_insert = table.insert
local random = math.random
local f = string.format

local dma_db = nil
if cfg.enable_dma_database then
    dma_db = LuaDataBase({
        table_name = "DMADataBase",
        elements = {
            "cycles => INTEGER",
			"channel => TEXT",
			"opcode => TEXT",
			"address => TEXT",
			"txn_id => INTEGER",
			"db_id => INTEGER",
			"data => TEXT",
        },
        path = cfg.dma_db_path,
        file_name = cfg.dma_db_file_name,
        save_cnt_max = 1000,
        verbose = cfg.verbose_dma_database,
    })
end
assert(dma_db ~= nil)

local bridge_hier = cfg.top .. "." .. "u_Axi2ChiTop.axi2chi"

local mon_axi_aw = ([[
    | valid
    | ready
    | bits_id => id
    | bits_addr => addr
    | bits_len => len
    | bits_size => size
    | bits_burst => burst
    | bits_lock => lock
    | bits_cache => cache
    | bits_prot => prot
    | bits_qos => qos
]]):abdl({ hier = bridge_hier, prefix = "axi_aw_", name = "axi_aw" })

local mon_axi_w = ([[
    | ready
    | valid
    | bits_last => last
    | bits_strb => strb
    | bits_data => data
]]):abdl({ hier = bridge_hier, prefix = "axi_w_", name = "axi_w" })

local mon_axi_b = ([[
    | ready
    | valid
    | bits_id => id
    | bits_resp => resp
]]):abdl({ hier = bridge_hier, prefix = "axi_b_", name = "axi_b" })

local mon_axi_ar = ([[
    | ready
    | valid
    | bits_addr => addr
    | bits_id => id
    | bits_len => len
    | bits_size => size
    | bits_burst => burst
    | bits_lock => lock
    | bits_prot => prot
    | bits_cache => cache
    | bits_qos => qos
]]):abdl({ hier = bridge_hier, prefix = "axi_ar_", name = "axi_ar" })

local mon_axi_r = ([[
    | ready
    | valid
    | bits_data => data
    | bits_last => last
    | bits_resp => resp
    | bits_id => id
]]):abdl({ hier = bridge_hier, prefix = "axi_r_", name = "axi_r" })

local mon_txreq = ([[
    | ready
    | valid
    | bits_Addr => addr
    | bits_TxnID => txnID
    | bits_Opcode => opcode
    | bits_Size => size
]]):abdl({ hier = bridge_hier, prefix = "icn_tx_req_", name = "txreq" })

local mon_txdat = ([[
    | ready
    | valid
    | bits_Data => data
    | bits_DataID => dataID
    | bits_TxnID => txnID
    | bits_Opcode => opcode
]]):abdl({ hier = bridge_hier, prefix = "icn_tx_data_", name = "txdat" })

local mon_txrsp = ([[
    | ready
    | valid
    | bits_TxnID => txnID
    | bits_Opcode => opcode
    | bits_DBID => dbID
]]):abdl({ hier = bridge_hier, prefix = "icn_tx_resp_", name = "txdat" })

local mon_rxrsp = ([[
    | ready
    | valid
    | bits_TxnID => txnID
    | bits_Opcode => opcode
    | bits_DBID => dbID
]]):abdl({ hier = bridge_hier, prefix = "icn_rx_resp_", name = "rxrsp" })

local mon_rxdat = ([[
    | ready
    | valid
    | bits_Data => data
    | bits_DataID => dataID
    | bits_TxnID => txnID
    | bits_Opcode => opcode
    | bits_DBID => dbID
]]):abdl({ hier = bridge_hier, prefix = "icn_rx_data_", name = "rxdat" })

local bridge_monitor = AxiMonitor(
	"bridge_monitor",

	-- AXI channels
	mon_axi_aw,
	mon_axi_w,
	mon_axi_b,
	mon_axi_ar,
	mon_axi_r,

	-- CHI channels
	mon_txreq,
	mon_txrsp,
	mon_txdat,
	mon_rxrsp,
	mon_rxdat,

	cfg.verbose_monitor,
	cfg.enable_monitor,
    dma_db
)

local axi_master = AXI4MasterAgnet(
	"axi_master",

	-- AXI channels
	mon_axi_aw,
	mon_axi_w,
	mon_axi_b,
	mon_axi_ar,
	mon_axi_r,

	16,
	16,
	cfg.enable_aximaster
)

return {
	axi_master = axi_master,
	bridge_monitor = bridge_monitor,
}
