library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.Array_pkg.all;
entity Pages is
  generic (
    BUS_ADDR_WIDTH : integer := 64
  );
  port (
    bcd_clk                    : in  std_logic;
    bcd_reset                  : in  std_logic;
    kcd_clk                    : in  std_logic;
    kcd_reset                  : in  std_logic;
    Pages_title_valid          : out std_logic;
    Pages_title_ready          : in  std_logic;
    Pages_title_dvalid         : out std_logic;
    Pages_title_last           : out std_logic;
    Pages_title_length         : out std_logic_vector(31 downto 0);
    Pages_title_count          : out std_logic_vector(0 downto 0);
    Pages_title_chars_valid    : out std_logic;
    Pages_title_chars_ready    : in  std_logic;
    Pages_title_chars_dvalid   : out std_logic;
    Pages_title_chars_last     : out std_logic;
    Pages_title_chars_data     : out std_logic_vector(7 downto 0);
    Pages_title_chars_count    : out std_logic_vector(0 downto 0);
    Pages_title_cmd_valid      : in  std_logic;
    Pages_title_cmd_ready      : out std_logic;
    Pages_title_cmd_firstIdx   : in  std_logic_vector(31 downto 0);
    Pages_title_cmd_lastidx    : in  std_logic_vector(31 downto 0);
    Pages_title_cmd_ctrl       : in  std_logic_vector(2*bus_addr_width-1 downto 0);
    Pages_title_cmd_tag        : in  std_logic_vector(0 downto 0);
    Pages_title_unl_valid      : out std_logic;
    Pages_title_unl_ready      : in  std_logic;
    Pages_title_unl_tag        : out std_logic_vector(0 downto 0);
    Pages_title_bus_rreq_valid : out std_logic;
    Pages_title_bus_rreq_ready : in  std_logic;
    Pages_title_bus_rreq_addr  : out std_logic_vector(63 downto 0);
    Pages_title_bus_rreq_len   : out std_logic_vector(7 downto 0);
    Pages_title_bus_rdat_valid : in  std_logic;
    Pages_title_bus_rdat_ready : out std_logic;
    Pages_title_bus_rdat_data  : in  std_logic_vector(511 downto 0);
    Pages_title_bus_rdat_last  : in  std_logic;
    Pages_text_valid           : out std_logic;
    Pages_text_ready           : in  std_logic;
    Pages_text_dvalid          : out std_logic;
    Pages_text_last            : out std_logic;
    Pages_text_length          : out std_logic_vector(31 downto 0);
    Pages_text_count           : out std_logic_vector(0 downto 0);
    Pages_text_bytes_valid     : out std_logic;
    Pages_text_bytes_ready     : in  std_logic;
    Pages_text_bytes_dvalid    : out std_logic;
    Pages_text_bytes_last      : out std_logic;
    Pages_text_bytes_data      : out std_logic_vector(63 downto 0);
    Pages_text_bytes_count     : out std_logic_vector(3 downto 0);
    Pages_text_cmd_valid       : in  std_logic;
    Pages_text_cmd_ready       : out std_logic;
    Pages_text_cmd_firstIdx    : in  std_logic_vector(31 downto 0);
    Pages_text_cmd_lastidx     : in  std_logic_vector(31 downto 0);
    Pages_text_cmd_ctrl        : in  std_logic_vector(2*bus_addr_width-1 downto 0);
    Pages_text_cmd_tag         : in  std_logic_vector(0 downto 0);
    Pages_text_unl_valid       : out std_logic;
    Pages_text_unl_ready       : in  std_logic;
    Pages_text_unl_tag         : out std_logic_vector(0 downto 0);
    Pages_text_bus_rreq_valid  : out std_logic;
    Pages_text_bus_rreq_ready  : in  std_logic;
    Pages_text_bus_rreq_addr   : out std_logic_vector(63 downto 0);
    Pages_text_bus_rreq_len    : out std_logic_vector(7 downto 0);
    Pages_text_bus_rdat_valid  : in  std_logic;
    Pages_text_bus_rdat_ready  : out std_logic;
    Pages_text_bus_rdat_data   : in  std_logic_vector(511 downto 0);
    Pages_text_bus_rdat_last   : in  std_logic
  );
end entity;
architecture Implementation of Pages is
begin
  title_inst : ArrayReader
    generic map (
      BUS_ADDR_WIDTH     => 64,
      BUS_LEN_WIDTH      => 8,
      BUS_DATA_WIDTH     => 512,
      BUS_BURST_STEP_LEN => 1,
      BUS_BURST_MAX_LEN  => 64,
      INDEX_WIDTH        => 32,
      CFG                => "listprim(8)",
      CMD_TAG_ENABLE     => true,
      CMD_TAG_WIDTH      => 1
    )
    port map (
      bcd_clk                => bcd_clk,
      bcd_reset              => bcd_reset,
      kcd_clk                => kcd_clk,
      kcd_reset              => kcd_reset,
      bus_rreq_valid         => Pages_title_bus_rreq_valid,
      bus_rreq_ready         => Pages_title_bus_rreq_ready,
      bus_rreq_addr          => Pages_title_bus_rreq_addr,
      bus_rreq_len           => Pages_title_bus_rreq_len,
      bus_rdat_valid         => Pages_title_bus_rdat_valid,
      bus_rdat_ready         => Pages_title_bus_rdat_ready,
      bus_rdat_data          => Pages_title_bus_rdat_data,
      bus_rdat_last          => Pages_title_bus_rdat_last,
      cmd_valid              => Pages_title_cmd_valid,
      cmd_ready              => Pages_title_cmd_ready,
      cmd_firstIdx           => Pages_title_cmd_firstIdx,
      cmd_lastidx            => Pages_title_cmd_lastidx,
      cmd_ctrl               => Pages_title_cmd_ctrl,
      cmd_tag                => Pages_title_cmd_tag,
      unl_valid              => Pages_title_unl_valid,
      unl_ready              => Pages_title_unl_ready,
      unl_tag                => Pages_title_unl_tag,
      out_valid(0)           => Pages_title_valid,
      out_valid(1)           => Pages_title_chars_valid,
      out_ready(0)           => Pages_title_ready,
      out_ready(1)           => Pages_title_chars_ready,
      out_data(31 downto 0)  => Pages_title_length,
      out_data(32 downto 32) => Pages_title_count,
      out_data(40 downto 33) => Pages_title_chars_data,
      out_data(41 downto 41) => Pages_title_chars_count,
      out_dvalid(0)          => Pages_title_dvalid,
      out_dvalid(1)          => Pages_title_chars_dvalid,
      out_last(0)            => Pages_title_last,
      out_last(1)            => Pages_title_chars_last
    );
  text_inst : ArrayReader
    generic map (
      BUS_ADDR_WIDTH     => 64,
      BUS_LEN_WIDTH      => 8,
      BUS_DATA_WIDTH     => 512,
      BUS_BURST_STEP_LEN => 1,
      BUS_BURST_MAX_LEN  => 64,
      INDEX_WIDTH        => 32,
      CFG                => "listprim(8;epc=8)",
      CMD_TAG_ENABLE     => true,
      CMD_TAG_WIDTH      => 1
    )
    port map (
      bcd_clk                 => bcd_clk,
      bcd_reset               => bcd_reset,
      kcd_clk                 => kcd_clk,
      kcd_reset               => kcd_reset,
      bus_rreq_valid          => Pages_text_bus_rreq_valid,
      bus_rreq_ready          => Pages_text_bus_rreq_ready,
      bus_rreq_addr           => Pages_text_bus_rreq_addr,
      bus_rreq_len            => Pages_text_bus_rreq_len,
      bus_rdat_valid          => Pages_text_bus_rdat_valid,
      bus_rdat_ready          => Pages_text_bus_rdat_ready,
      bus_rdat_data           => Pages_text_bus_rdat_data,
      bus_rdat_last           => Pages_text_bus_rdat_last,
      cmd_valid               => Pages_text_cmd_valid,
      cmd_ready               => Pages_text_cmd_ready,
      cmd_firstIdx            => Pages_text_cmd_firstIdx,
      cmd_lastidx             => Pages_text_cmd_lastidx,
      cmd_ctrl                => Pages_text_cmd_ctrl,
      cmd_tag                 => Pages_text_cmd_tag,
      unl_valid               => Pages_text_unl_valid,
      unl_ready               => Pages_text_unl_ready,
      unl_tag                 => Pages_text_unl_tag,
      out_valid(0)            => Pages_text_valid,
      out_valid(1)            => Pages_text_bytes_valid,
      out_ready(0)            => Pages_text_ready,
      out_ready(1)            => Pages_text_bytes_ready,
      out_data(31 downto 0)   => Pages_text_length,
      out_data(32 downto 32)  => Pages_text_count,
      out_data(96 downto 33)  => Pages_text_bytes_data,
      out_data(100 downto 97) => Pages_text_bytes_count,
      out_dvalid(0)           => Pages_text_dvalid,
      out_dvalid(1)           => Pages_text_bytes_dvalid,
      out_last(0)             => Pages_text_last,
      out_last(1)             => Pages_text_bytes_last
    );
end architecture;
