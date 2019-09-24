library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.vhdmmio_pkg.all;
use work.mmio_pkg.all;

entity word_match_cmd_gen is
  generic (
    BUS_ADDR_WIDTH            : integer := 64
  );
  port (
    clk                       : in  std_logic;
    reset                     : in  std_logic;

    -- MMIO register interface.
    mmio_cmd                  : in  mmio_g_cmd_o_type;
    mmio_stat                 : out mmio_g_stat_i_type;

    -- Article title input command stream.
    pages_title_cmd_valid     : out std_logic;
    pages_title_cmd_ready     : in  std_logic;
    pages_title_cmd_firstIdx  : out std_logic_vector(31 downto 0);
    pages_title_cmd_lastidx   : out std_logic_vector(31 downto 0);
    pages_title_cmd_ctrl      : out std_logic_vector(2*BUS_ADDR_WIDTH-1 downto 0);
    pages_title_cmd_tag       : out std_logic_vector(0 downto 0);

    -- Article title input unlock stream.
    pages_title_unl_valid     : in  std_logic;
    pages_title_unl_ready     : out std_logic;
    pages_title_unl_tag       : in  std_logic_vector(0 downto 0);

    -- Compressed article text input command stream.
    pages_text_cmd_valid      : out std_logic;
    pages_text_cmd_ready      : in  std_logic;
    pages_text_cmd_firstIdx   : out std_logic_vector(31 downto 0);
    pages_text_cmd_lastidx    : out std_logic_vector(31 downto 0);
    pages_text_cmd_ctrl       : out std_logic_vector(2*BUS_ADDR_WIDTH-1 downto 0);
    pages_text_cmd_tag        : out std_logic_vector(0 downto 0);

    -- Compressed article text input unlock stream.
    pages_text_unl_valid      : in  std_logic;
    pages_text_unl_ready      : out std_logic;
    pages_text_unl_tag        : in  std_logic_vector(0 downto 0);

    -- Match result output command stream for title column.
    result_title_cmd_valid    : out std_logic;
    result_title_cmd_ready    : in  std_logic;
    result_title_cmd_firstIdx : out std_logic_vector(31 downto 0);
    result_title_cmd_lastidx  : out std_logic_vector(31 downto 0);
    result_title_cmd_ctrl     : out std_logic_vector(2*BUS_ADDR_WIDTH-1 downto 0);
    result_title_cmd_tag      : out std_logic_vector(0 downto 0);

    -- Match result output unlock stream for title column.
    result_title_unl_valid    : in  std_logic;
    result_title_unl_ready    : out std_logic;
    result_title_unl_tag      : in  std_logic_vector(0 downto 0);

    -- Match result output command stream for match count column.
    result_count_cmd_valid    : out std_logic;
    result_count_cmd_ready    : in  std_logic;
    result_count_cmd_firstIdx : out std_logic_vector(31 downto 0);
    result_count_cmd_lastidx  : out std_logic_vector(31 downto 0);
    result_count_cmd_ctrl     : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    result_count_cmd_tag      : out std_logic_vector(0 downto 0);

    -- Match result output unlock stream for match count column.
    result_count_unl_valid    : in  std_logic;
    result_count_unl_ready    : out std_logic;
    result_count_unl_tag      : in  std_logic_vector(0 downto 0);

    -- Statistics data output command stream.
    stats_stats_cmd_valid     : out std_logic;
    stats_stats_cmd_ready     : in  std_logic;
    stats_stats_cmd_firstIdx  : out std_logic_vector(31 downto 0);
    stats_stats_cmd_lastidx   : out std_logic_vector(31 downto 0);
    stats_stats_cmd_ctrl      : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    stats_stats_cmd_tag       : out std_logic_vector(0 downto 0);

    -- Statistics data output unlock stream.
    stats_stats_unl_valid     : in  std_logic;
    stats_stats_unl_ready     : out std_logic;
    stats_stats_unl_tag       : in  std_logic_vector(0 downto 0)

  );
end entity;

architecture Implementation of word_match_cmd_gen is
begin
end architecture;
