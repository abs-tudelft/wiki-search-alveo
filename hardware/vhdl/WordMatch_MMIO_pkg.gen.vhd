-- Generated using vhdMMIO 0.0.3 (https://github.com/abs-tudelft/vhdmmio)

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

library work;
use work.vhdmmio_pkg.all;

package WordMatch_MMIO_pkg is

  -- Types used by the register file interface.
  type wordmatch_mmio_g_filt_o_type is record
    f_title_offs_addr_data : std_logic_vector(63 downto 0);
    f_title_val_addr_data : std_logic_vector(63 downto 0);
    f_min_matches_data : std_logic_vector(15 downto 0);
    f_result_size_data : std_logic_vector(31 downto 0);
  end record;
  constant WORDMATCH_MMIO_G_FILT_O_RESET : wordmatch_mmio_g_filt_o_type := (
    f_title_offs_addr_data => (others => '0'),
    f_title_val_addr_data => (others => '0'),
    f_min_matches_data => (others => '0'),
    f_result_size_data => (others => '0')
  );
  subtype WordMatch_MMIO_f_index_data_type is std_logic_vector(19 downto 0);
  type WordMatch_MMIO_f_index_data_array is array (natural range <>) of WordMatch_MMIO_f_index_data_type;
  type wordmatch_mmio_g_cmd_o_type is record
    f_text_offs_addr_data : std_logic_vector(63 downto 0);
    f_text_val_addr_data : std_logic_vector(63 downto 0);
    f_index_data : WordMatch_MMIO_f_index_data_array(0 to 4);
    f_res_title_offs_addr_data : std_logic_vector(63 downto 0);
    f_res_title_val_addr_data : std_logic_vector(63 downto 0);
    f_res_match_addr_data : std_logic_vector(63 downto 0);
    f_res_stats_addr_data : std_logic_vector(63 downto 0);
  end record;
  constant WORDMATCH_MMIO_G_CMD_O_RESET : wordmatch_mmio_g_cmd_o_type := (
    f_text_offs_addr_data => (others => '0'),
    f_text_val_addr_data => (others => '0'),
    f_index_data => (others => (others => '0')),
    f_res_title_offs_addr_data => (others => '0'),
    f_res_title_val_addr_data => (others => '0'),
    f_res_match_addr_data => (others => '0'),
    f_res_stats_addr_data => (others => '0')
  );
  subtype WordMatch_MMIO_f_search_data_data_type is std_logic_vector(7 downto 0);
  type WordMatch_MMIO_f_search_data_data_array is array (natural range <>) of WordMatch_MMIO_f_search_data_data_type;
  type wordmatch_mmio_g_cfg_o_type is record
    f_search_data_data : WordMatch_MMIO_f_search_data_data_array(0 to 31);
    f_search_first_data : std_logic_vector(4 downto 0);
    f_whole_words_data : std_logic;
  end record;
  constant WORDMATCH_MMIO_G_CFG_O_RESET : wordmatch_mmio_g_cfg_o_type := (
    f_search_data_data => (others => (others => '0')),
    f_search_first_data => (others => '0'),
    f_whole_words_data => '0'
  );
  type wordmatch_mmio_g_stat_i_type is record
    f_num_word_matches_write_data : std_logic_vector(31 downto 0);
    f_num_page_matches_write_data : std_logic_vector(31 downto 0);
    f_max_word_matches_write_data : std_logic_vector(15 downto 0);
    f_max_page_idx_write_data : std_logic_vector(19 downto 0);
    f_cycle_count_write_data : std_logic_vector(31 downto 0);
  end record;
  constant WORDMATCH_MMIO_G_STAT_I_RESET : wordmatch_mmio_g_stat_i_type := (
    f_num_word_matches_write_data => (others => '0'),
    f_num_page_matches_write_data => (others => '0'),
    f_max_word_matches_write_data => (others => '0'),
    f_max_page_idx_write_data => (others => '0'),
    f_cycle_count_write_data => (others => '0')
  );

  -- Component declaration for WordMatch_MMIO.
  component WordMatch_MMIO is
    port (

      -- Clock sensitive to the rising edge and synchronous, active-high reset.
      clk : in std_logic;
      reset : in std_logic := '0';

      -- Interface group for:
      --  - field min_matches: Minimum number of times that the word needs to
      --    occur in the article text for the page to be considered to match.
      --  - field result_size: Number of matches to return. The kernel will
      --    always write this many match records; it'll just pad with empty
      --    title strings and 0 for the match count when less articles match
      --    than this value implies, and it'll void any matches it doesn't have
      --    room for.
      --  - field title_offs_addr: Address for the article title offset buffer.
      --  - field title_val_addr: Address for the article title value buffer.
      g_filt_o : out wordmatch_mmio_g_filt_o_type
          := WORDMATCH_MMIO_G_FILT_O_RESET;

      -- Interface group for:
      --  - field group index: input dataset indices.
      --  - field res_match_addr: Address for the match count value buffer.
      --  - field res_stats_addr: Address for the statistics buffer.
      --  - field res_title_offs_addr: Address for the matched article title
      --    offset buffer.
      --  - field res_title_val_addr: Address for the matched article title
      --    value buffer.
      --  - field text_offs_addr: Address for the compressed article data offset
      --    buffer.
      --  - field text_val_addr: Address for the compressed article data value
      --    buffer.
      g_cmd_o : out wordmatch_mmio_g_cmd_o_type := WORDMATCH_MMIO_G_CMD_O_RESET;

      -- Interface group for:
      --  - field group search_data: The word to match. The length is set by
      --    `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The
      --    character used to pad the unused bytes before the word is don't
      --    care.
      --  - field search_first: Index of the first valid character in
      --    `search_data`.
      --  - field whole_words: selects between whole-words and regular pattern
      --    matching.
      g_cfg_o : out wordmatch_mmio_g_cfg_o_type := WORDMATCH_MMIO_G_CFG_O_RESET;

      -- Interface group for:
      --  - field cycle_count: Number of cycles taken by the last command.
      --  - field max_page_idx: Index of the page with the most matches,
      --    relative to `first_idx` in the command registers.
      --  - field max_word_matches: Maximum number of matches in any single
      --    page.
      --  - field num_page_matches: Number of pages that contain the specified
      --    word at least as many times as requested by `min_match`.
      --  - field num_word_matches: Number of times that the word occured in the
      --    dataset.
      g_stat_i : in wordmatch_mmio_g_stat_i_type
          := WORDMATCH_MMIO_G_STAT_I_RESET;

      -- Interface for output port for internal signal start.
      s_start : out std_logic := '0';

      -- Interface for strobe port for internal signal starting.
      s_starting : in std_logic := '0';

      -- Interface for strobe port for internal signal done.
      s_done : in std_logic := '0';

      -- Interface for output port for internal signal interrupt.
      s_interrupt : out std_logic := '0';

      -- AXI4-lite + interrupt request bus to the master.
      mmio_awvalid : in  std_logic := '0';
      mmio_awready : out std_logic := '1';
      mmio_awaddr  : in  std_logic_vector(31 downto 0) := X"00000000";
      mmio_awprot  : in  std_logic_vector(2 downto 0) := "000";
      mmio_wvalid  : in  std_logic := '0';
      mmio_wready  : out std_logic := '1';
      mmio_wdata   : in  std_logic_vector(31 downto 0) := (others => '0');
      mmio_wstrb   : in  std_logic_vector(3 downto 0) := (others => '0');
      mmio_bvalid  : out std_logic := '0';
      mmio_bready  : in  std_logic := '1';
      mmio_bresp   : out std_logic_vector(1 downto 0) := "00";
      mmio_arvalid : in  std_logic := '0';
      mmio_arready : out std_logic := '1';
      mmio_araddr  : in  std_logic_vector(31 downto 0) := X"00000000";
      mmio_arprot  : in  std_logic_vector(2 downto 0) := "000";
      mmio_rvalid  : out std_logic := '0';
      mmio_rready  : in  std_logic := '1';
      mmio_rdata   : out std_logic_vector(31 downto 0) := (others => '0');
      mmio_rresp   : out std_logic_vector(1 downto 0) := "00";
      mmio_uirq    : out std_logic := '0'

    );
  end component;

end package WordMatch_MMIO_pkg;
