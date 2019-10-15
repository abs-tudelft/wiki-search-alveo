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
use work.Interconnect_pkg.all;
use work.UtilStr_pkg.all;
use work.UtilConv_pkg.all;

-- pragma simulation timeout 50 us

entity WordMatch_SimTop_tc is
  generic (
    BUS_ADDR_WIDTH              : natural := 64;
    BUS_DATA_WIDTH              : natural := 64
  );
end WordMatch_SimTop_tc;

architecture Behavorial of WordMatch_SimTop_tc is

  -- Sim signals
  signal clock_stop             : boolean := false;

  -- Accelerator signals
  signal dec_clk                : std_logic;
  signal dec_reset              : std_logic;

  -- Fletcher bus signals
  signal bus_clk                : std_logic;
  signal bus_reset              : std_logic;

  -- MMIO signals
  signal mmio_awvalid           : std_logic := '0';
  signal mmio_awready           : std_logic := '0';
  signal mmio_awaddr            : std_logic_vector(31 downto 0);
  signal mmio_wvalid            : std_logic := '0';
  signal mmio_wready            : std_logic := '0';
  signal mmio_wdata             : std_logic_vector(31 downto 0);
  signal mmio_wstrb             : std_logic_vector(3 downto 0);
  signal mmio_bvalid            : std_logic := '0';
  signal mmio_bready            : std_logic := '0';
  signal mmio_bresp             : std_logic_vector(1 downto 0);
  signal mmio_arvalid           : std_logic := '0';
  signal mmio_arready           : std_logic := '0';
  signal mmio_araddr            : std_logic_vector(31 downto 0);
  signal mmio_rvalid            : std_logic := '0';
  signal mmio_rready            : std_logic := '0';
  signal mmio_rdata             : std_logic_vector(31 downto 0);
  signal mmio_rresp             : std_logic_vector(1 downto 0);

  -- Mmio signals to source in mmio procedures.
  type mmio_source_t is record
    awvalid           : std_logic;
    awaddr            : std_logic_vector(31 downto 0);
    wvalid            : std_logic;
    wdata             : std_logic_vector(31 downto 0);
    wstrb             : std_logic_vector(3 downto 0);
    bready            : std_logic;

    arvalid           : std_logic;
    araddr            : std_logic_vector(31 downto 0);
    rready            : std_logic;
  end record;

  -- Mmio signals to sink in mmio procedures
  type mmio_sink_t is record
    reset             : std_logic;

    wready            : std_logic;

    awready           : std_logic;

    bvalid            : std_logic;
    bresp             : std_logic_vector(1 downto 0);

    arready           : std_logic;

    rvalid            : std_logic;
    rdata             : std_logic_vector(31 downto 0);
    rresp             : std_logic_vector(1 downto 0);
  end record;

  signal mmio_source : mmio_source_t;
  signal mmio_sink : mmio_sink_t;

  -- Memory interface signals
  signal m_axi_aresetn          : std_logic;
  signal m_axi_araddr           : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal m_axi_arlen            : std_logic_vector(7 downto 0);
  signal m_axi_arvalid          : std_logic := '0';
  signal m_axi_arready          : std_logic;
  signal m_axi_arsize           : std_logic_vector(2 downto 0);
  signal m_axi_rdata            : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
  signal m_axi_rresp            : std_logic_vector(1 downto 0);
  signal m_axi_rlast            : std_logic;
  signal m_axi_rvalid           : std_logic;
  signal m_axi_rready           : std_logic := '0';
  signal m_axi_awvalid          : std_logic := '0';
  signal m_axi_awready          : std_logic;
  signal m_axi_awaddr           : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal m_axi_awlen            : std_logic_vector(7 downto 0);
  signal m_axi_awsize           : std_logic_vector(2 downto 0);
  signal m_axi_wvalid           : std_logic := '0';
  signal m_axi_wready           : std_logic;
  signal m_axi_wdata            : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
  signal m_axi_wlast            : std_logic;
  signal m_axi_wstrb            : std_logic_vector(BUS_DATA_WIDTH/8-1 downto 0);
  signal m_axi_bvalid           : std_logic;
  signal m_axi_bready           : std_logic;
  signal m_axi_bresp            : std_logic_vector(1 downto 0);

  procedure mmio_write (constant idx    : in  natural;
                        constant data   : in  std_logic_vector(31 downto 0);
                        signal   source : out mmio_source_t;
                        signal   sink   : in  mmio_sink_t)
  is
  begin
    -- Wait for reset
    loop
      exit when sink.reset = '0';
      wait until rising_edge(bus_clk);
    end loop;
    -- Address write channel
    source.awaddr <= slv((32/8)*idx, 32);
    source.awvalid <= '1';
    loop
      wait until rising_edge(bus_clk);
      exit when sink.awready = '1';
    end loop;
    source.awvalid <= '0';
    source.awaddr <= (others => 'U');
    -- Write channel
    source.wdata <= data;
    source.wstrb <= (others => '1');
    source.wvalid <= '1';
    loop
      wait until rising_edge(bus_clk);
      exit when sink.wready = '1';
    end loop;
    source.wvalid <= '0';
    source.wstrb <= (others => 'U');
    source.wdata <= (others => 'U');
    -- Write response channel.
    source.bready <= '1';
    loop
      wait until rising_edge(bus_clk);
      exit when sink.bvalid = '1';
    end loop;
    source.bready <= '0';
  end procedure;

  procedure mmio_read(constant idx    : in  natural;
                      variable data   : out std_logic_vector(31 downto 0);
                      signal   source : out mmio_source_t;
                      signal   sink   : in  mmio_sink_t)
  is
  begin
    -- Wait for reset
    loop
      exit when sink.reset = '0';
      wait until rising_edge(bus_clk);
    end loop;
    -- Address read channel
    source.araddr <= slv((32/8)*idx, 32);
    source.arvalid <= '1';
    loop
      wait until rising_edge(bus_clk);
      exit when sink.arready = '1';
    end loop;
    source.arvalid <= '0';
    source.araddr <= (others => 'U');
    -- Read channel
    loop
      source.rready <= '1';
      wait until rising_edge(bus_clk);
      if sink.rvalid = '1' then
        data := sink.rdata;
        exit;
      end if;
    end loop;
    source.rready <= '0';
  end procedure;


begin

  -- Connect to records for easier readibility downstream.
  mmio_awvalid <= mmio_source.awvalid;
  mmio_awaddr  <= mmio_source.awaddr;
  mmio_wvalid  <= mmio_source.wvalid;
  mmio_wdata   <= mmio_source.wdata;
  mmio_wstrb   <= mmio_source.wstrb;
  mmio_bready  <= mmio_source.bready;
  mmio_arvalid <= mmio_source.arvalid;
  mmio_araddr  <= mmio_source.araddr;
  mmio_rready  <= mmio_source.rready;

  mmio_sink.reset   <= dec_reset;
  mmio_sink.wready  <= mmio_wready;
  mmio_sink.awready <= mmio_awready;
  mmio_sink.bvalid  <= mmio_bvalid;
  mmio_sink.bresp   <= mmio_bresp;
  mmio_sink.arready <= mmio_arready;
  mmio_sink.rvalid  <= mmio_rvalid;
  mmio_sink.rdata   <= mmio_rdata;
  mmio_sink.rresp   <= mmio_rresp;


  -- Typical stimuli process:
  stimuli_proc : process is
    variable read_data        : std_logic_vector(31 downto 0) := X"DEADBEEF";
    variable read_data_masked : std_logic_vector(31 downto 0);
  begin
    mmio_source.awvalid <= '0';
    mmio_source.wvalid  <= '0';
    mmio_source.bready  <= '0';

    mmio_source.arvalid <= '0';
    mmio_source.rready  <= '0';

    wait until dec_reset = '1' and bus_reset = '1';

    -- Input buffer addresses.
    mmio_write(4, X"00000000", mmio_source, mmio_sink); -- Pages title_offsets
    mmio_write(5, X"00000000", mmio_source, mmio_sink);
    mmio_write(6, X"00000040", mmio_source, mmio_sink); -- Pages title_values
    mmio_write(7, X"00000000", mmio_source, mmio_sink);
    mmio_write(8, X"00000080", mmio_source, mmio_sink); -- Pages text_offsets
    mmio_write(9, X"00000000", mmio_source, mmio_sink);
    mmio_write(10, X"000000c0", mmio_source, mmio_sink); -- Pages text_values
    mmio_write(11, X"00000000", mmio_source, mmio_sink);

    -- Input buffer size and distribution over subkernels.
    mmio_write(12, X"00000000", mmio_source, mmio_sink); -- Pages first index
    mmio_write(13, X"00000001", mmio_source, mmio_sink); -- Middle index
    mmio_write(14, X"00000002", mmio_source, mmio_sink); -- Middle index
    mmio_write(15, X"00000003", mmio_source, mmio_sink); -- Pages last index

    -- Result buffer addresses.
    mmio_write(16, X"00000000", mmio_source, mmio_sink); -- Result title_offsets
    mmio_write(17, X"00000001", mmio_source, mmio_sink);
    mmio_write(18, X"00000000", mmio_source, mmio_sink); -- Result title_values
    mmio_write(19, X"00000002", mmio_source, mmio_sink);
    mmio_write(20, X"00000000", mmio_source, mmio_sink); -- Result count_values
    mmio_write(21, X"00000003", mmio_source, mmio_sink);
    mmio_write(22, X"00000000", mmio_source, mmio_sink); -- Stats stats_values
    mmio_write(23, X"00000004", mmio_source, mmio_sink);

    -- Configure the kernel.
    mmio_write(24, X"00000000", mmio_source, mmio_sink); -- search data 0
    mmio_write(25, X"00000000", mmio_source, mmio_sink); -- search data 4
    mmio_write(26, X"00000000", mmio_source, mmio_sink); -- search data 8
    mmio_write(27, X"00000000", mmio_source, mmio_sink); -- search data 12
    mmio_write(28, X"00000000", mmio_source, mmio_sink); -- search data 16
    mmio_write(29, X"00000000", mmio_source, mmio_sink); -- search data 20
    mmio_write(30, X"00000000", mmio_source, mmio_sink); -- search data 24
    mmio_write(31, X"656E696C", mmio_source, mmio_sink); -- search data 28
    mmio_write(32, X"0001001c", mmio_source, mmio_sink); -- search config
    mmio_write(33, X"00000002", mmio_source, mmio_sink); -- number of result records

    -- 5. Start the user core.
    mmio_write(0, X"00000001", mmio_source, mmio_sink);

    -- 6. Poll for completion
    loop
      -- Wait a bunch of cycles.
      for I in 0 to 128 loop
        wait until rising_edge(bus_clk);
      end loop;

      -- Read the status register.
      mmio_read(0, read_data, mmio_source, mmio_sink);

      -- Check if we're done.
      exit when read_data(1) = '1';
    end loop;

    -- 7. Read return register.
    mmio_read(34, read_data, mmio_source, mmio_sink);
    println("Magic number: " & slvToHex(read_data));
    mmio_read(35, read_data, mmio_source, mmio_sink);
    println("Word match count: " & slvToHex(read_data));
    mmio_read(36, read_data, mmio_source, mmio_sink);
    println("Page match count: " & slvToHex(read_data));
    mmio_read(37, read_data, mmio_source, mmio_sink);
    println("Max matches in a single article: " & slvToHex(read_data));
    mmio_read(38, read_data, mmio_source, mmio_sink);
    println("Index of the above article: " & slvToHex(read_data));
    mmio_read(39, read_data, mmio_source, mmio_sink);
    println("Number of cycles: " & slvToHex(read_data));

    -- 8. Finish and stop simulation.
    report "Stimuli done.";
    clock_stop <= true;

    wait;
  end process;

  bus_clk_proc: process is
  begin
    if not clock_stop then
      wait for 2 ns;
      bus_clk <= '0';
      wait for 2 ns;
      bus_clk <= '1';
    else
      wait;
    end if;
  end process;

  dec_clk_proc: process is
  begin
    if not clock_stop then
      wait for 3.3 ns;
      dec_clk <= '0';
      wait for 3.3 ns;
      dec_clk <= '1';
    else
      wait;
    end if;
  end process;

  reset_proc: process is
  begin
    dec_reset <= '1';
    bus_reset <= '1';
    wait for 50 ns;
    wait until rising_edge(dec_clk);
    dec_reset <= '0';
    wait until rising_edge(bus_clk);
    bus_reset <= '0';
    wait;
  end process;

  m_axi_aresetn <= not bus_reset;

  memory_inst: entity work.WordMatch_AxiSlaveMock
    generic map (
      ADDR_WIDTH                => BUS_ADDR_WIDTH,
      DATA_WIDTH                => BUS_DATA_WIDTH,

      SEED                      => 1337,
      AW_STALL_PROB             => 0.0,
      W_STALL_PROB              => 0.0,
      B_STALL_PROB              => 0.0,
      AR_STALL_PROB             => 0.0,
      R_STALL_PROB              => 0.0,

      DUMP_WRITES               => true,
      SREC_FILE_IN              => "memory.srec",
      SREC_FILE_OUT             => ""
    )
    port map (
      aclk                      => bus_clk,
      aresetn                   => m_axi_aresetn,

      awvalid                   => m_axi_awvalid,
      awready                   => m_axi_awready,
      awid                      => X"00",
      awaddr                    => m_axi_awaddr,
      awlen                     => m_axi_awlen,
      awsize                    => m_axi_awsize,
      awburst                   => "01",

      wvalid                    => m_axi_wvalid,
      wready                    => m_axi_wready,
      wid                       => X"00",
      wdata                     => m_axi_wdata,
      wstrb                     => m_axi_wstrb,
      wlast                     => m_axi_wlast,

      bvalid                    => m_axi_bvalid,
      bready                    => m_axi_bready,
      bid                       => open,
      bresp                     => m_axi_bresp,

      arvalid                   => m_axi_arvalid,
      arready                   => m_axi_arready,
      arid                      => X"00",
      araddr                    => m_axi_araddr,
      arlen                     => m_axi_arlen,
      arsize                    => m_axi_arsize,
      arburst                   => "01",

      rvalid                    => m_axi_rvalid,
      rready                    => m_axi_rready,
      rid                       => open,
      rdata                     => m_axi_rdata,
      rresp                     => m_axi_rresp,
      rlast                     => m_axi_rlast
    );

  -----------------------------------------------------------------------------
  -- Fletcher generated wrapper
  -----------------------------------------------------------------------------
  uut: entity work.WordMatch_AxiTop
    generic map (
      BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
      BUS_DATA_WIDTH            => BUS_DATA_WIDTH
    )
    port map (
      dec_clk                   => dec_clk,
      dec_reset                 => dec_reset,
      bus_clk                   => bus_clk,
      bus_reset                 => bus_reset,
      m_axi_araddr              => m_axi_araddr,
      m_axi_arlen               => m_axi_arlen,
      m_axi_arvalid             => m_axi_arvalid,
      m_axi_arready             => m_axi_arready,
      m_axi_arsize              => m_axi_arsize,
      m_axi_rdata               => m_axi_rdata,
      m_axi_rresp               => m_axi_rresp,
      m_axi_rlast               => m_axi_rlast,
      m_axi_rvalid              => m_axi_rvalid,
      m_axi_rready              => m_axi_rready,
      m_axi_awvalid             => m_axi_awvalid,
      m_axi_awready             => m_axi_awready,
      m_axi_awaddr              => m_axi_awaddr,
      m_axi_awlen               => m_axi_awlen,
      m_axi_awsize              => m_axi_awsize,
      m_axi_wvalid              => m_axi_wvalid,
      m_axi_wready              => m_axi_wready,
      m_axi_wdata               => m_axi_wdata,
      m_axi_wlast               => m_axi_wlast,
      m_axi_wstrb               => m_axi_wstrb,
      m_axi_bvalid              => m_axi_bvalid,
      m_axi_bready              => m_axi_bready,
      m_axi_bresp               => m_axi_bresp,
      s_axi_awvalid             => mmio_awvalid,
      s_axi_awready             => mmio_awready,
      s_axi_awaddr              => mmio_awaddr,
      s_axi_wvalid              => mmio_wvalid,
      s_axi_wready              => mmio_wready,
      s_axi_wdata               => mmio_wdata,
      s_axi_wstrb               => mmio_wstrb,
      s_axi_bvalid              => mmio_bvalid,
      s_axi_bready              => mmio_bready,
      s_axi_bresp               => mmio_bresp,
      s_axi_arvalid             => mmio_arvalid,
      s_axi_arready             => mmio_arready,
      s_axi_araddr              => mmio_araddr,
      s_axi_rvalid              => mmio_rvalid,
      s_axi_rready              => mmio_rready,
      s_axi_rdata               => mmio_rdata,
      s_axi_rresp               => mmio_rresp
    );

end architecture;
