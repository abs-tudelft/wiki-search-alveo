library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.Array_pkg.all;
entity Result is
  generic (
    BUS_ADDR_WIDTH : integer := 64
  );
  port (
    bcd_clk                      : in  std_logic;
    bcd_reset                    : in  std_logic;
    kcd_clk                      : in  std_logic;
    kcd_reset                    : in  std_logic;
    Result_title_valid           : in  std_logic;
    Result_title_ready           : out std_logic;
    Result_title_dvalid          : in  std_logic;
    Result_title_last            : in  std_logic;
    Result_title_length          : in  std_logic_vector(31 downto 0);
    Result_title_count           : in  std_logic_vector(0 downto 0);
    Result_title_chars_valid     : in  std_logic;
    Result_title_chars_ready     : out std_logic;
    Result_title_chars_dvalid    : in  std_logic;
    Result_title_chars_last      : in  std_logic;
    Result_title_chars_data      : in  std_logic_vector(7 downto 0);
    Result_title_chars_count     : in  std_logic_vector(0 downto 0);
    Result_title_cmd_valid       : in  std_logic;
    Result_title_cmd_ready       : out std_logic;
    Result_title_cmd_firstIdx    : in  std_logic_vector(31 downto 0);
    Result_title_cmd_lastidx     : in  std_logic_vector(31 downto 0);
    Result_title_cmd_ctrl        : in  std_logic_vector(2*bus_addr_width-1 downto 0);
    Result_title_cmd_tag         : in  std_logic_vector(0 downto 0);
    Result_title_unl_valid       : out std_logic;
    Result_title_unl_ready       : in  std_logic;
    Result_title_unl_tag         : out std_logic_vector(0 downto 0);
    Result_title_bus_wreq_valid  : out std_logic;
    Result_title_bus_wreq_ready  : in  std_logic;
    Result_title_bus_wreq_addr   : out std_logic_vector(63 downto 0);
    Result_title_bus_wreq_len    : out std_logic_vector(7 downto 0);
    Result_title_bus_wdat_valid  : out std_logic;
    Result_title_bus_wdat_ready  : in  std_logic;
    Result_title_bus_wdat_data   : out std_logic_vector(511 downto 0);
    Result_title_bus_wdat_strobe : out std_logic_vector(63 downto 0);
    Result_title_bus_wdat_last   : out std_logic;
    Result_count_valid           : in  std_logic;
    Result_count_ready           : out std_logic;
    Result_count_dvalid          : in  std_logic;
    Result_count_last            : in  std_logic;
    Result_count                 : in  std_logic_vector(31 downto 0);
    Result_count_cmd_valid       : in  std_logic;
    Result_count_cmd_ready       : out std_logic;
    Result_count_cmd_firstIdx    : in  std_logic_vector(31 downto 0);
    Result_count_cmd_lastidx     : in  std_logic_vector(31 downto 0);
    Result_count_cmd_ctrl        : in  std_logic_vector(bus_addr_width-1 downto 0);
    Result_count_cmd_tag         : in  std_logic_vector(0 downto 0);
    Result_count_unl_valid       : out std_logic;
    Result_count_unl_ready       : in  std_logic;
    Result_count_unl_tag         : out std_logic_vector(0 downto 0);
    Result_count_bus_wreq_valid  : out std_logic;
    Result_count_bus_wreq_ready  : in  std_logic;
    Result_count_bus_wreq_addr   : out std_logic_vector(63 downto 0);
    Result_count_bus_wreq_len    : out std_logic_vector(7 downto 0);
    Result_count_bus_wdat_valid  : out std_logic;
    Result_count_bus_wdat_ready  : in  std_logic;
    Result_count_bus_wdat_data   : out std_logic_vector(511 downto 0);
    Result_count_bus_wdat_strobe : out std_logic_vector(63 downto 0);
    Result_count_bus_wdat_last   : out std_logic
  );
end entity;
architecture Implementation of Result is
begin
  title_inst : ArrayWriter
    generic map (
      BUS_ADDR_WIDTH     => 64,
      BUS_LEN_WIDTH      => 8,
      BUS_DATA_WIDTH     => 512,
      BUS_STROBE_WIDTH   => 64,
      BUS_BURST_STEP_LEN => 1,
      BUS_BURST_MAX_LEN  => 64,
      INDEX_WIDTH        => 32,
      CFG                => "listprim(8;last_from_length=0)",
      CMD_TAG_ENABLE     => true,
      CMD_TAG_WIDTH      => 1
    )
    port map (
      bcd_clk               => bcd_clk,
      bcd_reset             => bcd_reset,
      kcd_clk               => kcd_clk,
      kcd_reset             => kcd_reset,
      bus_wreq_valid        => Result_title_bus_wreq_valid,
      bus_wreq_ready        => Result_title_bus_wreq_ready,
      bus_wreq_addr         => Result_title_bus_wreq_addr,
      bus_wreq_len          => Result_title_bus_wreq_len,
      bus_wdat_valid        => Result_title_bus_wdat_valid,
      bus_wdat_ready        => Result_title_bus_wdat_ready,
      bus_wdat_data         => Result_title_bus_wdat_data,
      bus_wdat_strobe       => Result_title_bus_wdat_strobe,
      bus_wdat_last         => Result_title_bus_wdat_last,
      cmd_valid             => Result_title_cmd_valid,
      cmd_ready             => Result_title_cmd_ready,
      cmd_firstIdx          => Result_title_cmd_firstIdx,
      cmd_lastidx           => Result_title_cmd_lastidx,
      cmd_ctrl              => Result_title_cmd_ctrl,
      cmd_tag               => Result_title_cmd_tag,
      unl_valid             => Result_title_unl_valid,
      unl_ready             => Result_title_unl_ready,
      unl_tag               => Result_title_unl_tag,
      in_valid(0)           => Result_title_valid,
      in_valid(1)           => Result_title_chars_valid,
      in_ready(0)           => Result_title_ready,
      in_ready(1)           => Result_title_chars_ready,
      in_data(31 downto 0)  => Result_title_length,
      in_data(32 downto 32) => Result_title_count,
      in_data(40 downto 33) => Result_title_chars_data,
      in_data(41 downto 41) => Result_title_chars_count,
      in_dvalid(0)          => Result_title_dvalid,
      in_dvalid(1)          => Result_title_chars_dvalid,
      in_last(0)            => Result_title_last,
      in_last(1)            => Result_title_chars_last
    );
  count_inst : ArrayWriter
    generic map (
      BUS_ADDR_WIDTH     => 64,
      BUS_LEN_WIDTH      => 8,
      BUS_DATA_WIDTH     => 512,
      BUS_STROBE_WIDTH   => 64,
      BUS_BURST_STEP_LEN => 1,
      BUS_BURST_MAX_LEN  => 64,
      INDEX_WIDTH        => 32,
      CFG                => "prim(32)",
      CMD_TAG_ENABLE     => true,
      CMD_TAG_WIDTH      => 1
    )
    port map (
      bcd_clk              => bcd_clk,
      bcd_reset            => bcd_reset,
      kcd_clk              => kcd_clk,
      kcd_reset            => kcd_reset,
      bus_wreq_valid       => Result_count_bus_wreq_valid,
      bus_wreq_ready       => Result_count_bus_wreq_ready,
      bus_wreq_addr        => Result_count_bus_wreq_addr,
      bus_wreq_len         => Result_count_bus_wreq_len,
      bus_wdat_valid       => Result_count_bus_wdat_valid,
      bus_wdat_ready       => Result_count_bus_wdat_ready,
      bus_wdat_data        => Result_count_bus_wdat_data,
      bus_wdat_strobe      => Result_count_bus_wdat_strobe,
      bus_wdat_last        => Result_count_bus_wdat_last,
      cmd_valid            => Result_count_cmd_valid,
      cmd_ready            => Result_count_cmd_ready,
      cmd_firstIdx         => Result_count_cmd_firstIdx,
      cmd_lastidx          => Result_count_cmd_lastidx,
      cmd_ctrl             => Result_count_cmd_ctrl,
      cmd_tag              => Result_count_cmd_tag,
      unl_valid            => Result_count_unl_valid,
      unl_ready            => Result_count_unl_ready,
      unl_tag              => Result_count_unl_tag,
      in_valid(0)          => Result_count_valid,
      in_ready(0)          => Result_count_ready,
      in_data(31 downto 0) => Result_count,
      in_dvalid(0)         => Result_count_dvalid,
      in_last(0)           => Result_count_last
    );
end architecture;
