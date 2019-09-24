library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.Array_pkg.all;
entity Stats is
  generic (
    BUS_ADDR_WIDTH : integer := 64
  );
  port (
    bcd_clk                     : in  std_logic;
    bcd_reset                   : in  std_logic;
    kcd_clk                     : in  std_logic;
    kcd_reset                   : in  std_logic;
    Stats_stats_valid           : in  std_logic;
    Stats_stats_ready           : out std_logic;
    Stats_stats_dvalid          : in  std_logic;
    Stats_stats_last            : in  std_logic;
    Stats_stats                 : in  std_logic_vector(63 downto 0);
    Stats_stats_cmd_valid       : in  std_logic;
    Stats_stats_cmd_ready       : out std_logic;
    Stats_stats_cmd_firstIdx    : in  std_logic_vector(31 downto 0);
    Stats_stats_cmd_lastidx     : in  std_logic_vector(31 downto 0);
    Stats_stats_cmd_ctrl        : in  std_logic_vector(bus_addr_width-1 downto 0);
    Stats_stats_cmd_tag         : in  std_logic_vector(0 downto 0);
    Stats_stats_unl_valid       : out std_logic;
    Stats_stats_unl_ready       : in  std_logic;
    Stats_stats_unl_tag         : out std_logic_vector(0 downto 0);
    Stats_stats_bus_wreq_valid  : out std_logic;
    Stats_stats_bus_wreq_ready  : in  std_logic;
    Stats_stats_bus_wreq_addr   : out std_logic_vector(63 downto 0);
    Stats_stats_bus_wreq_len    : out std_logic_vector(7 downto 0);
    Stats_stats_bus_wdat_valid  : out std_logic;
    Stats_stats_bus_wdat_ready  : in  std_logic;
    Stats_stats_bus_wdat_data   : out std_logic_vector(511 downto 0);
    Stats_stats_bus_wdat_strobe : out std_logic_vector(63 downto 0);
    Stats_stats_bus_wdat_last   : out std_logic
  );
end entity;
architecture Implementation of Stats is
begin
  stats_inst : ArrayWriter
    generic map (
      BUS_ADDR_WIDTH     => 64,
      BUS_LEN_WIDTH      => 8,
      BUS_DATA_WIDTH     => 512,
      BUS_STROBE_WIDTH   => 64,
      BUS_BURST_STEP_LEN => 1,
      BUS_BURST_MAX_LEN  => 64,
      INDEX_WIDTH        => 32,
      CFG                => "prim(64)",
      CMD_TAG_ENABLE     => true,
      CMD_TAG_WIDTH      => 1
    )
    port map (
      bcd_clk              => bcd_clk,
      bcd_reset            => bcd_reset,
      kcd_clk              => kcd_clk,
      kcd_reset            => kcd_reset,
      bus_wreq_valid       => Stats_stats_bus_wreq_valid,
      bus_wreq_ready       => Stats_stats_bus_wreq_ready,
      bus_wreq_addr        => Stats_stats_bus_wreq_addr,
      bus_wreq_len         => Stats_stats_bus_wreq_len,
      bus_wdat_valid       => Stats_stats_bus_wdat_valid,
      bus_wdat_ready       => Stats_stats_bus_wdat_ready,
      bus_wdat_data        => Stats_stats_bus_wdat_data,
      bus_wdat_strobe      => Stats_stats_bus_wdat_strobe,
      bus_wdat_last        => Stats_stats_bus_wdat_last,
      cmd_valid            => Stats_stats_cmd_valid,
      cmd_ready            => Stats_stats_cmd_ready,
      cmd_firstIdx         => Stats_stats_cmd_firstIdx,
      cmd_lastidx          => Stats_stats_cmd_lastidx,
      cmd_ctrl             => Stats_stats_cmd_ctrl,
      cmd_tag              => Stats_stats_cmd_tag,
      unl_valid            => Stats_stats_unl_valid,
      unl_ready            => Stats_stats_unl_ready,
      unl_tag              => Stats_stats_unl_tag,
      in_valid(0)          => Stats_stats_valid,
      in_ready(0)          => Stats_stats_ready,
      in_data(63 downto 0) => Stats_stats,
      in_dvalid(0)         => Stats_stats_dvalid,
      in_last(0)           => Stats_stats_last
    );
end architecture;
