-- Copyright 2018 Delft University of Technology
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

library work;
use work.Axi_pkg.all;
use work.UtilInt_pkg.all;
use work.UtilConv_pkg.all;
use work.UtilMisc_pkg.all;

-------------------------------------------------------------------------------
-- AXI4 compatible top level for Fletcher generated accelerators.
-------------------------------------------------------------------------------
-- Requires an AXI4 port to host memory.
-- Requires an AXI4-lite port from host for MMIO.
-------------------------------------------------------------------------------
entity AxiTop is
  generic (
    -- AXI4 (full) bus properties for memory access.
    BUS_ADDR_WIDTH              : natural := 64;
    BUS_DATA_WIDTH              : natural := 512;
    BUS_STROBE_WIDTH            : natural := 64;
    BUS_LEN_WIDTH               : natural := 8;
    BUS_BURST_MAX_LEN           : natural := 64;
    BUS_BURST_STEP_LEN          : natural := 1;
    
    -- AXI4-lite bus properties for MMIO
    MMIO_ADDR_WIDTH             : natural := 32;
    MMIO_DATA_WIDTH             : natural := 32
  );

  port (
    -- Kernel clock domain.
    kcd_clk                     : in  std_logic;
    kcd_reset                   : in  std_logic;
    
    -- Bus clock domain.
    bcd_clk                     : in  std_logic;
    bcd_reset                   : in  std_logic;

    ---------------------------------------------------------------------------
    -- AXI4 master as Host Memory Interface
    ---------------------------------------------------------------------------
    -- Read address channel
    m_axi_araddr                : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    m_axi_arlen                 : out std_logic_vector(7 downto 0);
    m_axi_arvalid               : out std_logic := '0';
    m_axi_arready               : in  std_logic;
    m_axi_arsize                : out std_logic_vector(2 downto 0);

    -- Read data channel
    m_axi_rdata                 : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    m_axi_rresp                 : in  std_logic_vector(1 downto 0);
    m_axi_rlast                 : in  std_logic;
    m_axi_rvalid                : in  std_logic;
    m_axi_rready                : out std_logic := '0';

    -- Write address channel
    m_axi_awvalid               : out std_logic := '0';
    m_axi_awready               : in  std_logic;
    m_axi_awaddr                : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    m_axi_awlen                 : out std_logic_vector(7 downto 0);
    m_axi_awsize                : out std_logic_vector(2 downto 0);

    -- Write data channel
    m_axi_wvalid                : out std_logic := '0';
    m_axi_wready                : in  std_logic;
    m_axi_wdata                 : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    m_axi_wlast                 : out std_logic;
    m_axi_wstrb                 : out std_logic_vector(BUS_DATA_WIDTH/8-1 downto 0);

    ---------------------------------------------------------------------------
    -- AXI4-lite Slave as MMIO interface
    ---------------------------------------------------------------------------
    -- Write adress channel
    s_axi_awvalid               : in std_logic;
    s_axi_awready               : out std_logic;
    s_axi_awaddr                : in std_logic_vector(MMIO_ADDR_WIDTH-1 downto 0);

    -- Write data channel
    s_axi_wvalid                : in std_logic;
    s_axi_wready                : out std_logic;
    s_axi_wdata                 : in std_logic_vector(MMIO_DATA_WIDTH-1 downto 0);
    s_axi_wstrb                 : in std_logic_vector((MMIO_DATA_WIDTH/8)-1 downto 0);

    -- Write response channel
    s_axi_bvalid                : out std_logic;
    s_axi_bready                : in std_logic;
    s_axi_bresp                 : out std_logic_vector(1 downto 0);

    -- Read address channel
    s_axi_arvalid               : in std_logic;
    s_axi_arready               : out std_logic;
    s_axi_araddr                : in std_logic_vector(MMIO_ADDR_WIDTH-1 downto 0);

    -- Read data channel
    s_axi_rvalid                : out std_logic;
    s_axi_rready                : in std_logic;
    s_axi_rdata                 : out std_logic_vector(MMIO_DATA_WIDTH-1 downto 0);
    s_axi_rresp                 : out std_logic_vector(1 downto 0)
  );
end AxiTop;

architecture Behavorial of AxiTop is

  -----------------------------------------------------------------------------
  -- Generated top-level wrapper component.
  -----------------------------------------------------------------------------
  component Mantle is
    generic(
      BUS_ADDR_WIDTH            : natural
    );
    port(
      bcd_clk                   : in  std_logic;
      bcd_reset                 : in  std_logic;
      kcd_clk                   : in  std_logic;
      kcd_reset                 : in  std_logic;
      rd_mst_rreq_valid         : out std_logic;
      rd_mst_rreq_ready         : in  std_logic;
      rd_mst_rreq_addr          : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      rd_mst_rreq_len           : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      rd_mst_rdat_valid         : in  std_logic;
      rd_mst_rdat_ready         : out std_logic;
      rd_mst_rdat_data          : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      rd_mst_rdat_last          : in  std_logic;

      wr_mst_wreq_valid         : out std_logic;
      wr_mst_wreq_ready         : in std_logic;
      wr_mst_wreq_addr          : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      wr_mst_wreq_len           : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
      wr_mst_wdat_valid         : out std_logic;
      wr_mst_wdat_ready         : in std_logic;
      wr_mst_wdat_data          : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
      wr_mst_wdat_strobe        : out std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
      wr_mst_wdat_last          : out std_logic;
      mmio_awvalid              : in  std_logic;
      mmio_awready              : out std_logic;
      mmio_awaddr               : in  std_logic_vector(31 downto 0);
      mmio_wvalid               : in  std_logic;
      mmio_wready               : out std_logic;
      mmio_wdata                : in  std_logic_vector(31 downto 0);
      mmio_wstrb                : in  std_logic_vector(3 downto 0);
      mmio_bvalid               : out std_logic;
      mmio_bready               : in  std_logic;
      mmio_bresp                : out std_logic_vector(1 downto 0);
      mmio_arvalid              : in  std_logic;
      mmio_arready              : out std_logic;
      mmio_araddr               : in  std_logic_vector(31 downto 0);
      mmio_rvalid               : out std_logic;
      mmio_rready               : in  std_logic;
      mmio_rdata                : out std_logic_vector(31 downto 0);
      mmio_rresp                : out std_logic_vector(1 downto 0)
    );
  end component;
  
  -----------------------------------------------------------------------------
  -- Internal signals.  
  
  -- Active low reset for bus clock domain
  signal bcd_reset_n            : std_logic;
  
  -- Bus signals to convert to AXI.
  signal rd_mst_rreq_addr       : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal rd_mst_rreq_len        : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
  signal rd_mst_rreq_valid      : std_logic;
  signal rd_mst_rreq_ready      : std_logic;
  signal rd_mst_rdat_data       : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
  signal rd_mst_rdat_last       : std_logic;
  signal rd_mst_rdat_valid      : std_logic;
  signal rd_mst_rdat_ready      : std_logic;
  signal wr_mst_wreq_valid      : std_logic;
  signal wr_mst_wreq_ready      : std_logic;
  signal wr_mst_wreq_addr       : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal wr_mst_wreq_len        : std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
  signal wr_mst_wdat_valid      : std_logic;
  signal wr_mst_wdat_ready      : std_logic;
  signal wr_mst_wdat_data       : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
  signal wr_mst_wdat_strobe     : std_logic_vector(BUS_STROBE_WIDTH-1 downto 0);
  signal wr_mst_wdat_last       : std_logic;
begin

  -- Active low reset
  bcd_reset_n <= '0' when bcd_reset = '1' else '0';

  -----------------------------------------------------------------------------
  -- Fletcher generated wrapper
  -----------------------------------------------------------------------------
  Mantle_inst : Mantle
    generic map (
      BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH
    )
    port map (
      kcd_clk                   => kcd_clk,
      kcd_reset                 => kcd_reset,
      bcd_clk                   => bcd_clk,
      bcd_reset                 => bcd_reset,
      rd_mst_rreq_valid         => rd_mst_rreq_valid,
      rd_mst_rreq_ready         => rd_mst_rreq_ready,
      rd_mst_rreq_addr          => rd_mst_rreq_addr,
      rd_mst_rreq_len           => rd_mst_rreq_len,
      rd_mst_rdat_valid         => rd_mst_rdat_valid,
      rd_mst_rdat_ready         => rd_mst_rdat_ready,
      rd_mst_rdat_data          => rd_mst_rdat_data,
      rd_mst_rdat_last          => rd_mst_rdat_last,
      wr_mst_wreq_valid         => wr_mst_wreq_valid,
      wr_mst_wreq_ready         => wr_mst_wreq_ready,
      wr_mst_wreq_addr          => wr_mst_wreq_addr,
      wr_mst_wreq_len           => wr_mst_wreq_len,
      wr_mst_wdat_valid         => wr_mst_wdat_valid,
      wr_mst_wdat_ready         => wr_mst_wdat_ready,
      wr_mst_wdat_data          => wr_mst_wdat_data,
      wr_mst_wdat_strobe        => wr_mst_wdat_strobe,
      wr_mst_wdat_last          => wr_mst_wdat_last,
      mmio_awvalid              => s_axi_awvalid,
      mmio_awready              => s_axi_awready,
      mmio_awaddr               => s_axi_awaddr,
      mmio_wvalid               => s_axi_wvalid,
      mmio_wready               => s_axi_wready,
      mmio_wdata                => s_axi_wdata,
      mmio_wstrb                => s_axi_wstrb,
      mmio_bvalid               => s_axi_bvalid,
      mmio_bready               => s_axi_bready,
      mmio_bresp                => s_axi_bresp,
      mmio_arvalid              => s_axi_arvalid,
      mmio_arready              => s_axi_arready,
      mmio_araddr               => s_axi_araddr,
      mmio_rvalid               => s_axi_rvalid,
      mmio_rready               => s_axi_rready,
      mmio_rdata                => s_axi_rdata,
      mmio_rresp                => s_axi_rresp
    );

  -----------------------------------------------------------------------------
  -- AXI read converter
  -----------------------------------------------------------------------------
  -- Buffering bursts is disabled (ENABLE_FIFO=false) because BufferReaders
  -- are already able to absorb full bursts.
  axi_read_conv_inst: AxiReadConverter
    generic map (
      ADDR_WIDTH                => BUS_ADDR_WIDTH,
      MASTER_DATA_WIDTH         => BUS_DATA_WIDTH,
      MASTER_LEN_WIDTH          => BUS_LEN_WIDTH,
      SLAVE_DATA_WIDTH          => BUS_DATA_WIDTH,
      SLAVE_LEN_WIDTH           => BUS_LEN_WIDTH,
      SLAVE_MAX_BURST           => BUS_BURST_MAX_LEN,
      ENABLE_FIFO               => false,
      SLV_REQ_SLICE_DEPTH       => 0,
      SLV_DAT_SLICE_DEPTH       => 0,
      MST_REQ_SLICE_DEPTH       => 0,
      MST_DAT_SLICE_DEPTH       => 0
    )
    port map (
      clk                       => bcd_clk,
      reset_n                   => bcd_reset_n,
      slv_bus_rreq_addr         => rd_mst_rreq_addr,
      slv_bus_rreq_len          => rd_mst_rreq_len,
      slv_bus_rreq_valid        => rd_mst_rreq_valid,
      slv_bus_rreq_ready        => rd_mst_rreq_ready,
      slv_bus_rdat_data         => rd_mst_rdat_data,
      slv_bus_rdat_last         => rd_mst_rdat_last,
      slv_bus_rdat_valid        => rd_mst_rdat_valid,
      slv_bus_rdat_ready        => rd_mst_rdat_ready,
      m_axi_araddr              => m_axi_araddr,
      m_axi_arlen               => m_axi_arlen,
      m_axi_arvalid             => m_axi_arvalid,
      m_axi_arready             => m_axi_arready,
      m_axi_arsize              => m_axi_arsize,
      m_axi_rdata               => m_axi_rdata,
      m_axi_rlast               => m_axi_rlast,
      m_axi_rvalid              => m_axi_rvalid,
      m_axi_rready              => m_axi_rready
    );
  -----------------------------------------------------------------------------
  -- AXI write converter
  -----------------------------------------------------------------------------
  -- Buffering bursts is disabled (ENABLE_FIFO=false) because BufferWriters
  -- are already able to absorb full bursts.
  axi_write_conv_inst: AxiWriteConverter
    generic map (
      ADDR_WIDTH                => BUS_ADDR_WIDTH,
      MASTER_DATA_WIDTH         => BUS_DATA_WIDTH,
      MASTER_LEN_WIDTH          => BUS_LEN_WIDTH,
      SLAVE_DATA_WIDTH          => BUS_DATA_WIDTH,
      SLAVE_LEN_WIDTH           => BUS_LEN_WIDTH,
      SLAVE_MAX_BURST           => BUS_BURST_MAX_LEN,
      ENABLE_FIFO               => false,
      SLV_REQ_SLICE_DEPTH       => 0,
      SLV_DAT_SLICE_DEPTH       => 0,
      MST_REQ_SLICE_DEPTH       => 0,
      MST_DAT_SLICE_DEPTH       => 0
    )
    port map (
      clk                       => bcd_clk,
      reset_n                   => bcd_reset_n,
      slv_bus_wreq_addr         => wr_mst_wreq_addr,
      slv_bus_wreq_len          => wr_mst_wreq_len,
      slv_bus_wreq_valid        => wr_mst_wreq_valid,
      slv_bus_wreq_ready        => wr_mst_wreq_ready,
      slv_bus_wdat_data         => wr_mst_wdat_data,
      slv_bus_wdat_strobe       => wr_mst_wdat_strobe,
      slv_bus_wdat_last         => wr_mst_wdat_last,
      slv_bus_wdat_valid        => wr_mst_wdat_valid,
      slv_bus_wdat_ready        => wr_mst_wdat_ready,
      m_axi_awaddr              => m_axi_awaddr,
      m_axi_awlen               => m_axi_awlen,
      m_axi_awvalid             => m_axi_awvalid,
      m_axi_awready             => m_axi_awready,
      m_axi_awsize              => m_axi_awsize,
      m_axi_wdata               => m_axi_wdata,
      m_axi_wstrb               => m_axi_wstrb,
      m_axi_wlast               => m_axi_wlast,
      m_axi_wvalid              => m_axi_wvalid,
      m_axi_wready              => m_axi_wready
    );

end architecture;
