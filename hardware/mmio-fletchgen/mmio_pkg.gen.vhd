-- Generated using vhdMMIO 0.0.3 (https://github.com/abs-tudelft/vhdmmio)

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

library work;
use work.vhdmmio_pkg.all;

package mmio_pkg is

  -- Types used by the register file interface.
  type mmio_g_result_i_type is record
    f_num_word_matches_write_data : std_logic_vector(31 downto 0);
    f_num_word_matches_write_enable : std_logic;
    f_num_page_matches_write_data : std_logic_vector(31 downto 0);
    f_num_page_matches_write_enable : std_logic;
  end record;
  constant MMIO_G_RESULT_I_RESET : mmio_g_result_i_type := (
    f_num_word_matches_write_data => (others => '0'),
    f_num_word_matches_write_enable => '0',
    f_num_page_matches_write_data => (others => '0'),
    f_num_page_matches_write_enable => '0'
  );
  type mmio_g_cmd_o_type is record
    f_first_idx_data : std_logic_vector(31 downto 0);
    f_last_idx_data : std_logic_vector(31 downto 0);
    f_reserved_1_data : std_logic_vector(31 downto 0);
    f_result_size_data : std_logic_vector(31 downto 0);
    f_reserved_2_data : std_logic_vector(31 downto 0);
    f_reserved_3_data : std_logic_vector(31 downto 0);
    f_title_offs_addr_data : std_logic_vector(63 downto 0);
    f_title_val_addr_data : std_logic_vector(63 downto 0);
    f_text_offs_addr_data : std_logic_vector(63 downto 0);
    f_text_val_addr_data : std_logic_vector(63 downto 0);
    f_res_title_offs_addr_data : std_logic_vector(63 downto 0);
    f_res_title_val_addr_data : std_logic_vector(63 downto 0);
    f_res_match_addr_data : std_logic_vector(63 downto 0);
    f_res_stats_addr_data : std_logic_vector(63 downto 0);
    s_start : std_logic;
  end record;
  constant MMIO_G_CMD_O_RESET : mmio_g_cmd_o_type := (
    f_first_idx_data => (others => '0'),
    f_last_idx_data => (others => '0'),
    f_reserved_1_data => (others => '0'),
    f_result_size_data => (others => '0'),
    f_reserved_2_data => (others => '0'),
    f_reserved_3_data => (others => '0'),
    f_title_offs_addr_data => (others => '0'),
    f_title_val_addr_data => (others => '0'),
    f_text_offs_addr_data => (others => '0'),
    f_text_val_addr_data => (others => '0'),
    f_res_title_offs_addr_data => (others => '0'),
    f_res_title_val_addr_data => (others => '0'),
    f_res_match_addr_data => (others => '0'),
    f_res_stats_addr_data => (others => '0'),
    s_start => '0'
  );
  subtype mmio_f_search_data_data_type is std_logic_vector(7 downto 0);
  type mmio_f_search_data_data_array is array (natural range <>) of mmio_f_search_data_data_type;
  type mmio_g_cfg_o_type is record
    f_search_data_data : mmio_f_search_data_data_array(0 to 31);
    f_search_first_data : std_logic_vector(4 downto 0);
    f_whole_words_data : std_logic;
    f_min_matches_data : std_logic_vector(15 downto 0);
  end record;
  constant MMIO_G_CFG_O_RESET : mmio_g_cfg_o_type := (
    f_search_data_data => (others => (others => '0')),
    f_search_first_data => (others => '0'),
    f_whole_words_data => '0',
    f_min_matches_data => (others => '0')
  );
  type mmio_g_stat_i_type is record
    s_starting : std_logic;
    s_done : std_logic;
  end record;
  constant MMIO_G_STAT_I_RESET : mmio_g_stat_i_type := (
    s_starting => '0',
    s_done => '0'
  );

  -- Component declaration for mmio.
  component mmio is
    port (

      -- Clock sensitive to the rising edge and synchronous, active-high reset.
      clk : in std_logic;
      reset : in std_logic := '0';

      -- Interface group for:
      --  - field num_page_matches: Number of pages that contain the specified
      --    word at least as many times as requested by `min_match`.
      --  - field num_word_matches: Number of times that the word occured in the
      --    dataset.
      g_result_i : in mmio_g_result_i_type := MMIO_G_RESULT_I_RESET;

      -- Interface group for:
      --  - field first_idx: First index to process in the input dataset.
      --  - field last_idx: Last index to process in the input dataset,
      --    diminished-one.
      --  - field res_match_addr: Address for the match count value buffer.
      --  - field res_stats_addr: Address for the 64-bit result "buffer".
      --  - field res_title_offs_addr: Address for the matched article title
      --    offset buffer.
      --  - field res_title_val_addr: Address for the matched article title
      --    value buffer.
      --  - field reserved_1: Reserved for first index in result record batch,
      --    should be 0.
      --  - field reserved_2: Reserved for first index in stats record batch,
      --    should be 0. The kernel always writes a single 64-bit integer, with
      --    the low word representing the total number of word matches, and the
      --    high word representing the total number of article matches.
      --  - field reserved_3: Reserved for last index in stats record batch,
      --    should be 1.
      --  - field result_size: Number of matches to return. The kernel will
      --    always write this many match records; it'll just pad with empty
      --    title strings and 0 for the match count when less articles match
      --    than this value implies, and it'll void any matches it doesn't have
      --    room for.
      --  - field text_offs_addr: Address for the compressed article data offset
      --    buffer.
      --  - field text_val_addr: Address for the compressed article data value
      --    buffer.
      --  - field title_offs_addr: Address for the article title offset buffer.
      --  - field title_val_addr: Address for the article title value buffer.
      --  - output port for internal signal start.
      g_cmd_o : out mmio_g_cmd_o_type := MMIO_G_CMD_O_RESET;

      -- Interface group for:
      --  - field group search_data: The word to match. The length is set by
      --    `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The
      --    character used to pad the unused bytes before the word is don't
      --    care.
      --  - field min_matches: Minimum number of times that the word needs to
      --    occur in the article text for the page to be considered to match.
      --  - field search_first: Index of the first valid character in
      --    `search_data`.
      --  - field whole_words: When set, interpunction/spacing must exist before
      --    and after the word for it to match.
      g_cfg_o : out mmio_g_cfg_o_type := MMIO_G_CFG_O_RESET;

      -- Interface group for:
      --  - strobe port for internal signal done.
      --  - strobe port for internal signal starting.
      g_stat_i : in mmio_g_stat_i_type := MMIO_G_STAT_I_RESET;

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

end package mmio_pkg;
