-- Generated using vhdMMIO 0.0.3 (https://github.com/abs-tudelft/vhdmmio)

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

library work;
use work.vhdmmio_pkg.all;
use work.WordMatch_MMIO_pkg.all;

entity WordMatch_MMIO is
  port (

    -- Clock sensitive to the rising edge and synchronous, active-high reset.
    clk : in std_logic;
    reset : in std_logic := '0';

    -- Interface group for:
    --  - field min_matches: Minimum number of times that the word needs to
    --    occur in the article text for the page to be considered to match.
    --  - field result_size: Number of matches to return. The kernel will always
    --    write this many match records; it'll just pad with empty title strings
    --    and 0 for the match count when less articles match than this value
    --    implies, and it'll void any matches it doesn't have room for.
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
    --  - field res_title_val_addr: Address for the matched article title value
    --    buffer.
    --  - field text_offs_addr: Address for the compressed article data offset
    --    buffer.
    --  - field text_val_addr: Address for the compressed article data value
    --    buffer.
    g_cmd_o : out wordmatch_mmio_g_cmd_o_type := WORDMATCH_MMIO_G_CMD_O_RESET;

    -- Interface group for:
    --  - field group search_data: The word to match. The length is set by
    --    `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The character
    --    used to pad the unused bytes before the word is don't care.
    --  - field search_first: Index of the first valid character in
    --    `search_data`.
    --  - field whole_words: selects between whole-words and regular pattern
    --    matching.
    g_cfg_o : out wordmatch_mmio_g_cfg_o_type := WORDMATCH_MMIO_G_CFG_O_RESET;

    -- Interface group for:
    --  - field cycle_count: Number of cycles taken by the last command.
    --  - field max_page_idx: Index of the page with the most matches, relative
    --    to `first_idx` in the command registers.
    --  - field max_word_matches: Maximum number of matches in any single page.
    --  - field num_page_matches: Number of pages that contain the specified
    --    word at least as many times as requested by `min_match`.
    --  - field num_word_matches: Number of times that the word occured in the
    --    dataset.
    g_stat_i : in wordmatch_mmio_g_stat_i_type := WORDMATCH_MMIO_G_STAT_I_RESET;

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
end WordMatch_MMIO;

architecture behavioral of WordMatch_MMIO is
begin
  reg_proc: process (clk) is

    -- Convenience function for unsigned accumulation with differing vector
    -- widths.
    procedure accum_add(
      accum: inout std_logic_vector;
      addend: std_logic_vector) is
    begin
      accum := std_logic_vector(
        unsigned(accum) + resize(unsigned(addend), accum'length));
    end procedure accum_add;

    -- Convenience function for unsigned subtraction with differing vector
    -- widths.
    procedure accum_sub(
      accum: inout std_logic_vector;
      addend: std_logic_vector) is
    begin
      accum := std_logic_vector(
        unsigned(accum) - resize(unsigned(addend), accum'length));
    end procedure accum_sub;

    -- Bus response output register.
    variable bus_v : axi4l32_s2m_type := AXI4L32_S2M_RESET; -- reg

    -- Holding registers for the AXI4-lite request channels. Having these
    -- allows us to make the accompanying ready signals register outputs
    -- without sacrificing a cycle's worth of delay for every transaction.
    variable awl : axi4la_type := AXI4LA_RESET; -- reg
    variable wl  : axi4lw32_type := AXI4LW32_RESET; -- reg
    variable arl : axi4la_type := AXI4LA_RESET; -- reg

    -- Request flags for the register logic. When asserted, a request is
    -- present in awl/wl/arl, and the response can be returned immediately.
    -- This is used by simple registers.
    variable w_req : boolean := false;
    variable r_req : boolean := false;

    -- As above, but asserted when there is a request that can NOT be returned
    -- immediately for whatever reason, but CAN be started already if deferral
    -- is supported by the targeted block. Abbreviation for lookahead request.
    -- Note that *_lreq implies *_req.
    variable w_lreq : boolean := false;
    variable r_lreq : boolean := false;

    -- Request signals. w_strb is a validity bit for each data bit; it actually
    -- always has byte granularity but encoding it this way makes the code a
    -- lot nicer (and it should be optimized to the same thing by any sane
    -- synthesizer).
    variable w_addr : std_logic_vector(31 downto 0);
    variable w_data : std_logic_vector(31 downto 0) := (others => '0');
    variable w_strb : std_logic_vector(31 downto 0) := (others => '0');
    constant w_prot : std_logic_vector(2 downto 0) := (others => '0');
    variable r_addr : std_logic_vector(31 downto 0);
    constant r_prot : std_logic_vector(2 downto 0) := (others => '0');

    -- Logical write data holding registers. For multi-word registers, write
    -- data is held in w_hold and w_hstb until the last subregister is written,
    -- at which point their entire contents are written at once.
    variable w_hold : std_logic_vector(63 downto 0) := (others => '0'); -- reg
    variable w_hstb : std_logic_vector(63 downto 0) := (others => '0'); -- reg

    -- Between the first and last access to a multiword register, the multi
    -- bit will be set. If it is set while a request with a different *_prot is
    -- received, the interrupting request is rejected if it is A) non-secure
    -- while the interrupted request is secure or B) unprivileged while the
    -- interrupted request is privileged. If it is not rejected, previously
    -- buffered data is cleared and masked. Within the same security level, it
    -- is up to the bus master to not mess up its own access pattern. The last
    -- access to a multiword register clears the bit; for the read end r_hold
    -- is also cleared in this case to prevent data leaks.
    variable w_multi : std_logic := '0'; -- reg
    variable r_multi : std_logic := '0'; -- reg

    -- Response flags. When *_req is set and *_addr matches a register, it must
    -- set at least one of these flags; when *_rreq is set and *_rtag matches a
    -- register, it must also set at least one of these, except it cannot set
    -- *_defer. A decode error can be generated by intentionally NOT setting
    -- any of these flags, but this should only be done by registers that
    -- contain only one field (usually, these would be AXI-lite passthrough
    -- "registers"). The action taken by the non-register-specific logic is as
    -- follows (priority decoder):
    --
    --  - if *_defer is set, push *_dtag into the deferal FIFO;
    --  - if *_block is set, do nothing;
    --  - otherwise, if *_nack is set, send a slave error response;
    --  - otherwise, if *_ack is set, send a positive response;
    --  - otherwise, send a decode error response.
    --
    -- In addition to the above, the request stream(s) will be handshaked if
    -- *_req was set and a response is sent or the response is deferred.
    -- Likewise, the deferal FIFO will be popped if *_rreq was set and a
    -- response is sent.
    --
    -- The valid states can be summarized as follows:
    --
    -- .----------------------------------------------------------------------------------.
    -- | req | lreq | rreq || ack | nack | block | defer || request | response | defer    |
    -- |-----+------+------||-----+------+-------+-------||---------+----------+----------|
    -- |  0  |  0   |  0   ||  0  |  0   |   0   |   0   ||         |          |          | Idle.
    -- |-----+------+------||-----+------+-------+-------||---------+----------+----------|
    -- |  0  |  0   |  1   ||  0  |  0   |   0   |   0   ||         | dec_err  | pop      | Completing
    -- |  0  |  0   |  1   ||  1  |  0   |   0   |   0   ||         | ack      | pop      | previous,
    -- |  0  |  0   |  1   ||  -  |  1   |   0   |   0   ||         | slv_err  | pop      | no
    -- |  0  |  0   |  1   ||  -  |  -   |   1   |   0   ||         |          |          | lookahead.
    -- |-----+------+------||-----+------+-------+-------||---------+----------+----------|
    -- |  1  |  0   |  0   ||  0  |  0   |   0   |   0   || accept  | dec_err  |          | Responding
    -- |  1  |  0   |  0   ||  1  |  0   |   0   |   0   || accept  | ack      |          | immediately
    -- |  1  |  0   |  0   ||  -  |  1   |   0   |   0   || accept  | slv_err  |          | to incoming
    -- |  1  |  0   |  0   ||  -  |  -   |   1   |   0   ||         |          |          | request.
    -- |-----+------+------||-----+------+-------+-------||---------+----------+----------|
    -- |  1  |  0   |  0   ||  0  |  0   |   0   |   1   || accept  |          | push     | Deferring.
    -- |  0  |  1   |  0   ||  0  |  0   |   0   |   1   || accept  |          | push     | Deferring.
    -- |-----+------+------||-----+------+-------+-------||---------+----------+----------|
    -- |  0  |  1   |  1   ||  0  |  0   |   0   |   0   ||         | dec_err  | pop      | Completing
    -- |  0  |  1   |  1   ||  1  |  0   |   0   |   0   ||         | ack      | pop      | previous,
    -- |  0  |  1   |  1   ||  -  |  1   |   0   |   0   ||         | slv_err  | pop      | ignoring
    -- |  0  |  1   |  1   ||  -  |  -   |   1   |   0   ||         |          |          | lookahead.
    -- |-----+------+------||-----+------+-------+-------||---------+----------+----------|
    -- |  0  |  1   |  1   ||  0  |  0   |   0   |   1   || accept  | dec_err  | pop+push | Completing
    -- |  0  |  1   |  1   ||  1  |  0   |   0   |   1   || accept  | ack      | pop+push | previous,
    -- |  0  |  1   |  1   ||  -  |  1   |   0   |   1   || accept  | slv_err  | pop+push | deferring
    -- |  0  |  1   |  1   ||  -  |  -   |   1   |   1   || accept  |          | push     | lookahead.
    -- '----------------------------------------------------------------------------------'
    --
    -- This can be simplified to the following:
    --
    -- .----------------------------------------------------------------------------------.
    -- | req | lreq | rreq || ack | nack | block | defer || request | response | defer    |
    -- |-----+------+------||-----+------+-------+-------||---------+----------+----------|
    -- |  -  |  -   |  -   ||  -  |  -   |   1   |   -   ||         |          |          |
    -- |-----+------+------||-----+------+-------+-------||---------+----------+----------|
    -- |  -  |  -   |  1   ||  -  |  1   |   0   |   -   ||         | slv_err  | pop      |
    -- |  1  |  -   |  0   ||  -  |  1   |   0   |   -   || accept  | slv_err  |          |
    -- |-----+------+------||-----+------+-------+-------||---------+----------+----------|
    -- |  -  |  -   |  1   ||  1  |  0   |   0   |   -   ||         | ack      | pop      |
    -- |  1  |  -   |  0   ||  1  |  0   |   0   |   -   || accept  | ack      |          |
    -- |-----+------+------||-----+------+-------+-------||---------+----------+----------|
    -- |  -  |  -   |  1   ||  0  |  0   |   0   |   -   ||         | dec_err  | pop      |
    -- |  1  |  -   |  0   ||  0  |  0   |   0   |   -   || accept  | dec_err  |          |
    -- |-----+------+------||-----+------+-------+-------||---------+----------+----------|
    -- |  -  |  -   |  -   ||  -  |  -   |   -   |   1   || accept  |          | push     |
    -- '----------------------------------------------------------------------------------'
    --
    variable w_block : boolean := false;
    variable r_block : boolean := false;
    variable w_nack  : boolean := false;
    variable r_nack  : boolean := false;
    variable w_ack   : boolean := false;
    variable r_ack   : boolean := false;

    -- Logical read data holding register. This is set when r_ack is set during
    -- an access to the first physical register of a logical register for all
    -- fields in the logical register.
    variable r_hold  : std_logic_vector(63 downto 0) := (others => '0'); -- reg

    -- Physical read data. This is taken from r_hold based on which physical
    -- subregister is being read.
    variable r_data  : std_logic_vector(31 downto 0);

    -- Subaddress variables, used to index within large fields like memories and
    -- AXI passthroughs.
    variable subaddr_none         : std_logic_vector(0 downto 0);

    -- Private declarations for field start: start signal.
    type f_start_r_type is record
      busy : std_logic;
    end record;
    constant F_START_R_RESET : f_start_r_type := (
      busy => '0'
    );
    type f_start_r_array is array (natural range <>) of f_start_r_type;
    variable f_start_r : f_start_r_array(0 to 0) := (others => F_START_R_RESET);

    -- Private declarations for field done: done signal.
    type f_done_r_type is record
      done_reg : std_logic;
    end record;
    constant F_DONE_R_RESET : f_done_r_type := (
      done_reg => '0'
    );
    type f_done_r_array is array (natural range <>) of f_done_r_type;
    variable f_done_r : f_done_r_array(0 to 0) := (others => F_DONE_R_RESET);

    -- Private declarations for field idle: idle signal.
    type f_idle_r_type is record
      busy : std_logic;
    end record;
    constant F_IDLE_R_RESET : f_idle_r_type := (
      busy => '0'
    );
    type f_idle_r_array is array (natural range <>) of f_idle_r_type;
    variable f_idle_r : f_idle_r_array(0 to 0) := (others => F_IDLE_R_RESET);

    -- Private declarations for field gier: global interrupt enable register.
    type f_gier_r_type is record
      d : std_logic;
      v : std_logic;
    end record;
    constant F_GIER_R_RESET : f_gier_r_type := (
      d => '0',
      v => '0'
    );
    type f_gier_r_array is array (natural range <>) of f_gier_r_type;
    variable f_gier_r : f_gier_r_array(0 to 0) := (others => F_GIER_R_RESET);

    -- Private declarations for field iier_done: selects whether kernel
    -- completion triggers an interrupt.
    type f_iier_done_r_type is record
      d : std_logic;
      v : std_logic;
    end record;
    constant F_IIER_DONE_R_RESET : f_iier_done_r_type := (
      d => '0',
      v => '0'
    );
    type f_iier_done_r_array is array (natural range <>) of f_iier_done_r_type;
    variable f_iier_done_r : f_iier_done_r_array(0 to 0)
        := (others => F_IIER_DONE_R_RESET);

    -- Private declarations for field iisr_done: interrupt flag for kernel
    -- completion.
    type f_iisr_done_r_type is record
      flag : std_logic;
    end record;
    constant F_IISR_DONE_R_RESET : f_iisr_done_r_type := (
      flag => '0'
    );
    type f_iisr_done_r_array is array (natural range <>) of f_iisr_done_r_type;
    variable f_iisr_done_r : f_iisr_done_r_array(0 to 0)
        := (others => F_IISR_DONE_R_RESET);

    -- Private declarations for field title_offs_addr: Address for the article
    -- title offset buffer.
    type f_title_offs_addr_r_type is record
      d : std_logic_vector(63 downto 0);
      v : std_logic;
    end record;
    constant F_TITLE_OFFS_ADDR_R_RESET : f_title_offs_addr_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_title_offs_addr_r_array is array (natural range <>) of f_title_offs_addr_r_type;
    variable f_title_offs_addr_r : f_title_offs_addr_r_array(0 to 0)
        := (others => F_TITLE_OFFS_ADDR_R_RESET);

    -- Private declarations for field title_val_addr: Address for the article
    -- title value buffer.
    type f_title_val_addr_r_type is record
      d : std_logic_vector(63 downto 0);
      v : std_logic;
    end record;
    constant F_TITLE_VAL_ADDR_R_RESET : f_title_val_addr_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_title_val_addr_r_array is array (natural range <>) of f_title_val_addr_r_type;
    variable f_title_val_addr_r : f_title_val_addr_r_array(0 to 0)
        := (others => F_TITLE_VAL_ADDR_R_RESET);

    -- Private declarations for field text_offs_addr: Address for the compressed
    -- article data offset buffer.
    type f_text_offs_addr_r_type is record
      d : std_logic_vector(63 downto 0);
      v : std_logic;
    end record;
    constant F_TEXT_OFFS_ADDR_R_RESET : f_text_offs_addr_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_text_offs_addr_r_array is array (natural range <>) of f_text_offs_addr_r_type;
    variable f_text_offs_addr_r : f_text_offs_addr_r_array(0 to 0)
        := (others => F_TEXT_OFFS_ADDR_R_RESET);

    -- Private declarations for field text_val_addr: Address for the compressed
    -- article data value buffer.
    type f_text_val_addr_r_type is record
      d : std_logic_vector(63 downto 0);
      v : std_logic;
    end record;
    constant F_TEXT_VAL_ADDR_R_RESET : f_text_val_addr_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_text_val_addr_r_array is array (natural range <>) of f_text_val_addr_r_type;
    variable f_text_val_addr_r : f_text_val_addr_r_array(0 to 0)
        := (others => F_TEXT_VAL_ADDR_R_RESET);

    -- Private declarations for field group index: input dataset indices.
    type f_index_r_type is record
      d : std_logic_vector(19 downto 0);
      v : std_logic;
    end record;
    constant F_INDEX_R_RESET : f_index_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_index_r_array is array (natural range <>) of f_index_r_type;
    variable f_index_r : f_index_r_array(0 to 4) := (others => F_INDEX_R_RESET);

    -- Private declarations for field res_title_offs_addr: Address for the
    -- matched article title offset buffer.
    type f_res_title_offs_addr_r_type is record
      d : std_logic_vector(63 downto 0);
      v : std_logic;
    end record;
    constant F_RES_TITLE_OFFS_ADDR_R_RESET : f_res_title_offs_addr_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_res_title_offs_addr_r_array is array (natural range <>) of f_res_title_offs_addr_r_type;
    variable f_res_title_offs_addr_r : f_res_title_offs_addr_r_array(0 to 0)
        := (others => F_RES_TITLE_OFFS_ADDR_R_RESET);

    -- Private declarations for field res_title_val_addr: Address for the
    -- matched article title value buffer.
    type f_res_title_val_addr_r_type is record
      d : std_logic_vector(63 downto 0);
      v : std_logic;
    end record;
    constant F_RES_TITLE_VAL_ADDR_R_RESET : f_res_title_val_addr_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_res_title_val_addr_r_array is array (natural range <>) of f_res_title_val_addr_r_type;
    variable f_res_title_val_addr_r : f_res_title_val_addr_r_array(0 to 0)
        := (others => F_RES_TITLE_VAL_ADDR_R_RESET);

    -- Private declarations for field res_match_addr: Address for the match
    -- count value buffer.
    type f_res_match_addr_r_type is record
      d : std_logic_vector(63 downto 0);
      v : std_logic;
    end record;
    constant F_RES_MATCH_ADDR_R_RESET : f_res_match_addr_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_res_match_addr_r_array is array (natural range <>) of f_res_match_addr_r_type;
    variable f_res_match_addr_r : f_res_match_addr_r_array(0 to 0)
        := (others => F_RES_MATCH_ADDR_R_RESET);

    -- Private declarations for field res_stats_addr: Address for the statistics
    -- buffer.
    type f_res_stats_addr_r_type is record
      d : std_logic_vector(63 downto 0);
      v : std_logic;
    end record;
    constant F_RES_STATS_ADDR_R_RESET : f_res_stats_addr_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_res_stats_addr_r_array is array (natural range <>) of f_res_stats_addr_r_type;
    variable f_res_stats_addr_r : f_res_stats_addr_r_array(0 to 0)
        := (others => F_RES_STATS_ADDR_R_RESET);

    -- Private declarations for field group search_data: The word to match. The
    -- length is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
    -- The character used to pad the unused bytes before the word is don't care.
    type f_search_data_r_type is record
      d : std_logic_vector(7 downto 0);
      v : std_logic;
    end record;
    constant F_SEARCH_DATA_R_RESET : f_search_data_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_search_data_r_array is array (natural range <>) of f_search_data_r_type;
    variable f_search_data_r : f_search_data_r_array(0 to 31)
        := (others => F_SEARCH_DATA_R_RESET);

    -- Private declarations for field search_first: Index of the first valid
    -- character in `search_data`.
    type f_search_first_r_type is record
      d : std_logic_vector(4 downto 0);
      v : std_logic;
    end record;
    constant F_SEARCH_FIRST_R_RESET : f_search_first_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_search_first_r_array is array (natural range <>) of f_search_first_r_type;
    variable f_search_first_r : f_search_first_r_array(0 to 0)
        := (others => F_SEARCH_FIRST_R_RESET);

    -- Private declarations for field whole_words: selects between whole-words
    -- and regular pattern matching.
    type f_whole_words_r_type is record
      d : std_logic;
      v : std_logic;
    end record;
    constant F_WHOLE_WORDS_R_RESET : f_whole_words_r_type := (
      d => '0',
      v => '0'
    );
    type f_whole_words_r_array is array (natural range <>) of f_whole_words_r_type;
    variable f_whole_words_r : f_whole_words_r_array(0 to 0)
        := (others => F_WHOLE_WORDS_R_RESET);

    -- Private declarations for field min_matches: Minimum number of times that
    -- the word needs to occur in the article text for the page to be considered
    -- to match.
    type f_min_matches_r_type is record
      d : std_logic_vector(15 downto 0);
      v : std_logic;
    end record;
    constant F_MIN_MATCHES_R_RESET : f_min_matches_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_min_matches_r_array is array (natural range <>) of f_min_matches_r_type;
    variable f_min_matches_r : f_min_matches_r_array(0 to 0)
        := (others => F_MIN_MATCHES_R_RESET);

    -- Private declarations for field result_size: Number of matches to return.
    -- The kernel will always write this many match records; it'll just pad with
    -- empty title strings and 0 for the match count when less articles match
    -- than this value implies, and it'll void any matches it doesn't have room
    -- for.
    type f_result_size_r_type is record
      d : std_logic_vector(31 downto 0);
      v : std_logic;
    end record;
    constant F_RESULT_SIZE_R_RESET : f_result_size_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_result_size_r_array is array (natural range <>) of f_result_size_r_type;
    variable f_result_size_r : f_result_size_r_array(0 to 0)
        := (others => F_RESULT_SIZE_R_RESET);

    -- Private declarations for field deadcode: magic number used to test MMIO
    -- access.
    type f_deadcode_r_type is record
      d : std_logic_vector(31 downto 0);
      v : std_logic;
    end record;
    constant F_DEADCODE_R_RESET : f_deadcode_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_deadcode_r_array is array (natural range <>) of f_deadcode_r_type;
    variable f_deadcode_r : f_deadcode_r_array(0 to 0)
        := (others => F_DEADCODE_R_RESET);

    -- Private declarations for field num_word_matches: Number of times that the
    -- word occured in the dataset.
    type f_num_word_matches_r_type is record
      d : std_logic_vector(31 downto 0);
      v : std_logic;
    end record;
    constant F_NUM_WORD_MATCHES_R_RESET : f_num_word_matches_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_num_word_matches_r_array is array (natural range <>) of f_num_word_matches_r_type;
    variable f_num_word_matches_r : f_num_word_matches_r_array(0 to 0)
        := (others => F_NUM_WORD_MATCHES_R_RESET);

    -- Private declarations for field num_page_matches: Number of pages that
    -- contain the specified word at least as many times as requested by
    -- `min_match`.
    type f_num_page_matches_r_type is record
      d : std_logic_vector(31 downto 0);
      v : std_logic;
    end record;
    constant F_NUM_PAGE_MATCHES_R_RESET : f_num_page_matches_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_num_page_matches_r_array is array (natural range <>) of f_num_page_matches_r_type;
    variable f_num_page_matches_r : f_num_page_matches_r_array(0 to 0)
        := (others => F_NUM_PAGE_MATCHES_R_RESET);

    -- Private declarations for field max_word_matches: Maximum number of
    -- matches in any single page.
    type f_max_word_matches_r_type is record
      d : std_logic_vector(15 downto 0);
      v : std_logic;
    end record;
    constant F_MAX_WORD_MATCHES_R_RESET : f_max_word_matches_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_max_word_matches_r_array is array (natural range <>) of f_max_word_matches_r_type;
    variable f_max_word_matches_r : f_max_word_matches_r_array(0 to 0)
        := (others => F_MAX_WORD_MATCHES_R_RESET);

    -- Private declarations for field max_page_idx: Index of the page with the
    -- most matches, relative to `first_idx` in the command registers.
    type f_max_page_idx_r_type is record
      d : std_logic_vector(19 downto 0);
      v : std_logic;
    end record;
    constant F_MAX_PAGE_IDX_R_RESET : f_max_page_idx_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_max_page_idx_r_array is array (natural range <>) of f_max_page_idx_r_type;
    variable f_max_page_idx_r : f_max_page_idx_r_array(0 to 0)
        := (others => F_MAX_PAGE_IDX_R_RESET);

    -- Private declarations for field cycle_count: Number of cycles taken by the
    -- last command.
    type f_cycle_count_r_type is record
      d : std_logic_vector(31 downto 0);
      v : std_logic;
    end record;
    constant F_CYCLE_COUNT_R_RESET : f_cycle_count_r_type := (
      d => (others => '0'),
      v => '0'
    );
    type f_cycle_count_r_array is array (natural range <>) of f_cycle_count_r_type;
    variable f_cycle_count_r : f_cycle_count_r_array(0 to 0)
        := (others => F_CYCLE_COUNT_R_RESET);

    -- Temporary variables for the field templates.
    variable tmp_data    : std_logic;
    variable tmp_strb    : std_logic;
    variable tmp_data5   : std_logic_vector(4 downto 0);
    variable tmp_strb5   : std_logic_vector(4 downto 0);
    variable tmp_data8   : std_logic_vector(7 downto 0);
    variable tmp_strb8   : std_logic_vector(7 downto 0);
    variable tmp_data16  : std_logic_vector(15 downto 0);
    variable tmp_strb16  : std_logic_vector(15 downto 0);
    variable tmp_data20  : std_logic_vector(19 downto 0);
    variable tmp_strb20  : std_logic_vector(19 downto 0);
    variable tmp_data32  : std_logic_vector(31 downto 0);
    variable tmp_strb32  : std_logic_vector(31 downto 0);
    variable tmp_data64  : std_logic_vector(63 downto 0);
    variable tmp_strb64  : std_logic_vector(63 downto 0);

    -- Private declarations for internal signal start.
    variable intsigr_start : std_logic := '0';
    variable intsigs_start : std_logic := '0';

    -- Private declarations for internal signal done.
    variable intsigr_done : std_logic := '0';
    variable intsigs_done : std_logic := '0';

    -- Private declarations for internal signal starting.
    variable intsigr_starting : std_logic := '0';
    variable intsigs_starting : std_logic := '0';

    -- Private declarations for internal signal gier.
    variable intsig_gier : std_logic := '0';

    -- Private declarations for internal signal iier_done.
    variable intsig_iier_done : std_logic := '0';

    -- Private declarations for internal signal interrupt.
    variable intsigr_interrupt : std_logic := '0';
    variable intsigs_interrupt : std_logic := '0';

  begin
    if rising_edge(clk) then

      -- Reset variables that shouldn't become registers to default values.
      w_req   := false;
      r_req   := false;
      w_lreq  := false;
      r_lreq  := false;
      w_addr  := (others => '0');
      w_data  := (others => '0');
      w_strb  := (others => '0');
      r_addr  := (others => '0');
      w_block := false;
      r_block := false;
      w_nack  := false;
      r_nack  := false;
      w_ack   := false;
      r_ack   := false;
      r_data  := (others => '0');

      -------------------------------------------------------------------------
      -- Finish up the previous cycle
      -------------------------------------------------------------------------
      -- Invalidate responses that were acknowledged by the master in the
      -- previous cycle.
      if mmio_bready = '1' then
        bus_v.b.valid := '0';
      end if;
      if mmio_rready = '1' then
        bus_v.r.valid := '0';
      end if;

      -- If we indicated to the master that we were ready for a transaction on
      -- any of the incoming channels, we must latch any incoming requests. If
      -- we're ready but there is no incoming request this becomes don't-care.
      if bus_v.aw.ready = '1' then
        awl.valid := mmio_awvalid;
        awl.addr  := mmio_awaddr;
        awl.prot  := mmio_awprot;
      end if;
      if bus_v.w.ready = '1' then
        wl.valid := mmio_wvalid;
        wl.data  := mmio_wdata;
        wl.strb  := mmio_wstrb;
      end if;
      if bus_v.ar.ready = '1' then
        arl.valid := mmio_arvalid;
        arl.addr  := mmio_araddr;
        arl.prot  := mmio_arprot;
      end if;

      -------------------------------------------------------------------------
      -- Connect internal signal input/strobe ports
      -------------------------------------------------------------------------

      -- Logic for strobe port for internal signal starting.
      intsigs_starting := intsigs_starting or s_starting;

      -- Logic for strobe port for internal signal done.
      intsigs_done := intsigs_done or s_done;

      -------------------------------------------------------------------------
      -- Handle interrupts
      -------------------------------------------------------------------------
      -- No incoming interrupts; request signal is always released.
      bus_v.u.irq := '0';

      -------------------------------------------------------------------------
      -- Handle MMIO fields
      -------------------------------------------------------------------------
      -- We're ready for a write/read when all the respective channels (or
      -- their holding registers) are ready/waiting for us.
      if awl.valid = '1' and wl.valid = '1' then
        if bus_v.b.valid = '0' then
          w_req := true; -- Request valid and response register empty.
        else
          w_lreq := true; -- Request valid, but response register is busy.
        end if;
      end if;
      if arl.valid = '1' then
        if bus_v.r.valid = '0' then
          r_req := true; -- Request valid and response register empty.
        else
          r_lreq := true; -- Request valid, but response register is busy.
        end if;
      end if;

      -- Capture request inputs into more consistently named variables.
      w_addr := awl.addr;
      for b in w_strb'range loop
        w_strb(b) := wl.strb(b / 8);
      end loop;
      w_data := wl.data and w_strb;
      r_addr := arl.addr;

      -------------------------------------------------------------------------
      -- Generated field logic
      -------------------------------------------------------------------------

      -- Pre-bus logic for field start: start signal.

      if intsigr_done = '1' then
        f_start_r((0)).busy := '0';
      end if;

      -- Pre-bus logic for field done: done signal.

      if intsigr_done = '1' then
        f_done_r((0)).done_reg := '1';
      end if;

      -- Pre-bus logic for field idle: idle signal.

      if intsigr_starting = '1' then
        f_idle_r((0)).busy := '1';
      end if;
      if intsigr_done = '1' then
        f_idle_r((0)).busy := '0';
      end if;

      -- Pre-bus logic for field iisr_done: interrupt flag for kernel
      -- completion.

      if intsig_iier_done = '1' and intsigr_done = '1' then
        f_iisr_done_r((0)).flag := '1';
      end if;
      if f_iisr_done_r((0)).flag = '1' and intsig_iier_done = '1' then
        intsigs_interrupt := '1';
      end if;

      -- Pre-bus logic for field num_word_matches: Number of times that the word
      -- occured in the dataset.

      -- Handle hardware write for field num_word_matches: status.
      f_num_word_matches_r((0)).d := g_stat_i.f_num_word_matches_write_data;
      f_num_word_matches_r((0)).v := '1';

      -- Pre-bus logic for field num_page_matches: Number of pages that contain
      -- the specified word at least as many times as requested by `min_match`.

      -- Handle hardware write for field num_page_matches: status.
      f_num_page_matches_r((0)).d := g_stat_i.f_num_page_matches_write_data;
      f_num_page_matches_r((0)).v := '1';

      -- Pre-bus logic for field max_word_matches: Maximum number of matches in
      -- any single page.

      -- Handle hardware write for field max_word_matches: status.
      f_max_word_matches_r((0)).d := g_stat_i.f_max_word_matches_write_data;
      f_max_word_matches_r((0)).v := '1';

      -- Pre-bus logic for field max_page_idx: Index of the page with the most
      -- matches, relative to `first_idx` in the command registers.

      -- Handle hardware write for field max_page_idx: status.
      f_max_page_idx_r((0)).d := g_stat_i.f_max_page_idx_write_data;
      f_max_page_idx_r((0)).v := '1';

      -- Pre-bus logic for field cycle_count: Number of cycles taken by the last
      -- command.

      -- Handle hardware write for field cycle_count: status.
      f_cycle_count_r((0)).d := g_stat_i.f_cycle_count_write_data;
      f_cycle_count_r((0)).v := '1';

      -------------------------------------------------------------------------
      -- Bus read logic
      -------------------------------------------------------------------------

      -- Construct the subaddresses for read mode.
      subaddr_none(0) := '0';

      -- Read address decoder.
      case r_addr(7 downto 2) is
        when "000000" =>
          -- r_addr = 000000000000000000000000000000--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field start: start signal.

          if r_req then
            tmp_data := r_hold(0);
          end if;
          if r_req then

            -- Regular access logic.
            tmp_data := f_start_r((0)).busy;
            r_ack := true;

          end if;
          if r_req then
            r_hold(0) := tmp_data;
          end if;

          -- Read logic for field done: done signal.

          if r_req then
            tmp_data := r_hold(1);
          end if;
          if r_req then

            -- Regular access logic.
            tmp_data := f_done_r((0)).done_reg;
            r_ack := true;
            f_done_r((0)).done_reg := '0';

          end if;
          if r_req then
            r_hold(1) := tmp_data;
          end if;

          -- Read logic for field idle: idle signal.

          if r_req then
            tmp_data := r_hold(2);
          end if;
          if r_req then

            -- Regular access logic.
            tmp_data := not f_idle_r((0)).busy;
            r_ack := true;

          end if;
          if r_req then
            r_hold(2) := tmp_data;
          end if;

          -- Read logic for block ctrl: block containing bits 31..0 of register
          -- `ctrl` (`CTRL`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "000001" =>
          -- r_addr = 000000000000000000000000000001--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field gier: global interrupt enable register.

          if r_req then
            tmp_data := r_hold(0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data := f_gier_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(0) := tmp_data;
          end if;

          -- Read logic for block gier_reg: block containing bits 31..0 of
          -- register `gier_reg` (`GIER_REG`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "000010" =>
          -- r_addr = 000000000000000000000000000010--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field iier_done: selects whether kernel completion
          -- triggers an interrupt.

          if r_req then
            tmp_data := r_hold(0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data := f_iier_done_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(0) := tmp_data;
          end if;

          -- Read logic for block iier: block containing bits 31..0 of register
          -- `iier` (`IIER`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "000011" =>
          -- r_addr = 000000000000000000000000000011--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field iisr_done: interrupt flag for kernel
          -- completion.

          if r_req then
            tmp_data := r_hold(0);
          end if;
          if r_req then

            -- Regular access logic.
            tmp_data := f_iisr_done_r((0)).flag;
            r_ack := true;

          end if;
          if r_req then
            r_hold(0) := tmp_data;
          end if;

          -- Read logic for block iisr: block containing bits 31..0 of register
          -- `iisr` (`IISR`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "000100" =>
          -- r_addr = 000000000000000000000000000100--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field title_offs_addr: Address for the article title
          -- offset buffer.

          if r_req then
            tmp_data64 := r_hold(63 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data64 := f_title_offs_addr_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(63 downto 0) := tmp_data64;
          end if;

          -- Read logic for block title_offs_addr_reg_low: block containing bits
          -- 31..0 of register `title_offs_addr_reg` (`TITLE_OFFS_ADDR`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '1';

          end if;

        when "000101" =>
          -- r_addr = 000000000000000000000000000101--

          -- Read logic for block title_offs_addr_reg_high: block containing
          -- bits 63..32 of register `title_offs_addr_reg` (`TITLE_OFFS_ADDR`).
          if r_req then

            r_data := r_hold(63 downto 32);
            if r_multi = '1' then
              r_ack := true;
            else
              r_nack := true;
            end if;
            r_multi := '0';

          end if;

        when "000110" =>
          -- r_addr = 000000000000000000000000000110--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field title_val_addr: Address for the article title
          -- value buffer.

          if r_req then
            tmp_data64 := r_hold(63 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data64 := f_title_val_addr_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(63 downto 0) := tmp_data64;
          end if;

          -- Read logic for block title_val_addr_reg_low: block containing bits
          -- 31..0 of register `title_val_addr_reg` (`TITLE_VAL_ADDR`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '1';

          end if;

        when "000111" =>
          -- r_addr = 000000000000000000000000000111--

          -- Read logic for block title_val_addr_reg_high: block containing bits
          -- 63..32 of register `title_val_addr_reg` (`TITLE_VAL_ADDR`).
          if r_req then

            r_data := r_hold(63 downto 32);
            if r_multi = '1' then
              r_ack := true;
            else
              r_nack := true;
            end if;
            r_multi := '0';

          end if;

        when "001000" =>
          -- r_addr = 000000000000000000000000001000--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field text_offs_addr: Address for the compressed
          -- article data offset buffer.

          if r_req then
            tmp_data64 := r_hold(63 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data64 := f_text_offs_addr_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(63 downto 0) := tmp_data64;
          end if;

          -- Read logic for block text_offs_addr_reg_low: block containing bits
          -- 31..0 of register `text_offs_addr_reg` (`TEXT_OFFS_ADDR`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '1';

          end if;

        when "001001" =>
          -- r_addr = 000000000000000000000000001001--

          -- Read logic for block text_offs_addr_reg_high: block containing bits
          -- 63..32 of register `text_offs_addr_reg` (`TEXT_OFFS_ADDR`).
          if r_req then

            r_data := r_hold(63 downto 32);
            if r_multi = '1' then
              r_ack := true;
            else
              r_nack := true;
            end if;
            r_multi := '0';

          end if;

        when "001010" =>
          -- r_addr = 000000000000000000000000001010--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field text_val_addr: Address for the compressed
          -- article data value buffer.

          if r_req then
            tmp_data64 := r_hold(63 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data64 := f_text_val_addr_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(63 downto 0) := tmp_data64;
          end if;

          -- Read logic for block text_val_addr_reg_low: block containing bits
          -- 31..0 of register `text_val_addr_reg` (`TEXT_VAL_ADDR`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '1';

          end if;

        when "001011" =>
          -- r_addr = 000000000000000000000000001011--

          -- Read logic for block text_val_addr_reg_high: block containing bits
          -- 63..32 of register `text_val_addr_reg` (`TEXT_VAL_ADDR`).
          if r_req then

            r_data := r_hold(63 downto 32);
            if r_multi = '1' then
              r_ack := true;
            else
              r_nack := true;
            end if;
            r_multi := '0';

          end if;

        when "001100" =>
          -- r_addr = 000000000000000000000000001100--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field index0: input dataset indices.

          if r_req then
            tmp_data20 := r_hold(19 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data20 := f_index_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(19 downto 0) := tmp_data20;
          end if;

          -- Read logic for block index0_reg: block containing bits 31..0 of
          -- register `index0_reg` (`INDEX0`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "001101" =>
          -- r_addr = 000000000000000000000000001101--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field index1: input dataset indices.

          if r_req then
            tmp_data20 := r_hold(19 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data20 := f_index_r((1)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(19 downto 0) := tmp_data20;
          end if;

          -- Read logic for block index1_reg: block containing bits 31..0 of
          -- register `index1_reg` (`INDEX1`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "001110" =>
          -- r_addr = 000000000000000000000000001110--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field index2: input dataset indices.

          if r_req then
            tmp_data20 := r_hold(19 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data20 := f_index_r((2)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(19 downto 0) := tmp_data20;
          end if;

          -- Read logic for block index2_reg: block containing bits 31..0 of
          -- register `index2_reg` (`INDEX2`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "001111" =>
          -- r_addr = 000000000000000000000000001111--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field index3: input dataset indices.

          if r_req then
            tmp_data20 := r_hold(19 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data20 := f_index_r((3)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(19 downto 0) := tmp_data20;
          end if;

          -- Read logic for block index3_reg: block containing bits 31..0 of
          -- register `index3_reg` (`INDEX3`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "010000" =>
          -- r_addr = 000000000000000000000000010000--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field index4: input dataset indices.

          if r_req then
            tmp_data20 := r_hold(19 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data20 := f_index_r((4)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(19 downto 0) := tmp_data20;
          end if;

          -- Read logic for block index4_reg: block containing bits 31..0 of
          -- register `index4_reg` (`INDEX4`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "010100" =>
          -- r_addr = 000000000000000000000000010100--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field res_title_offs_addr: Address for the matched
          -- article title offset buffer.

          if r_req then
            tmp_data64 := r_hold(63 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data64 := f_res_title_offs_addr_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(63 downto 0) := tmp_data64;
          end if;

          -- Read logic for block res_title_offs_addr_reg_low: block containing
          -- bits 31..0 of register `res_title_offs_addr_reg`
          -- (`RES_TITLE_OFFS_ADDR`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '1';

          end if;

        when "010101" =>
          -- r_addr = 000000000000000000000000010101--

          -- Read logic for block res_title_offs_addr_reg_high: block containing
          -- bits 63..32 of register `res_title_offs_addr_reg`
          -- (`RES_TITLE_OFFS_ADDR`).
          if r_req then

            r_data := r_hold(63 downto 32);
            if r_multi = '1' then
              r_ack := true;
            else
              r_nack := true;
            end if;
            r_multi := '0';

          end if;

        when "010110" =>
          -- r_addr = 000000000000000000000000010110--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field res_title_val_addr: Address for the matched
          -- article title value buffer.

          if r_req then
            tmp_data64 := r_hold(63 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data64 := f_res_title_val_addr_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(63 downto 0) := tmp_data64;
          end if;

          -- Read logic for block res_title_val_addr_reg_low: block containing
          -- bits 31..0 of register `res_title_val_addr_reg`
          -- (`RES_TITLE_VAL_ADDR`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '1';

          end if;

        when "010111" =>
          -- r_addr = 000000000000000000000000010111--

          -- Read logic for block res_title_val_addr_reg_high: block containing
          -- bits 63..32 of register `res_title_val_addr_reg`
          -- (`RES_TITLE_VAL_ADDR`).
          if r_req then

            r_data := r_hold(63 downto 32);
            if r_multi = '1' then
              r_ack := true;
            else
              r_nack := true;
            end if;
            r_multi := '0';

          end if;

        when "011000" =>
          -- r_addr = 000000000000000000000000011000--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field res_match_addr: Address for the match count
          -- value buffer.

          if r_req then
            tmp_data64 := r_hold(63 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data64 := f_res_match_addr_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(63 downto 0) := tmp_data64;
          end if;

          -- Read logic for block res_match_addr_reg_low: block containing bits
          -- 31..0 of register `res_match_addr_reg` (`RES_MATCH_ADDR`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '1';

          end if;

        when "011001" =>
          -- r_addr = 000000000000000000000000011001--

          -- Read logic for block res_match_addr_reg_high: block containing bits
          -- 63..32 of register `res_match_addr_reg` (`RES_MATCH_ADDR`).
          if r_req then

            r_data := r_hold(63 downto 32);
            if r_multi = '1' then
              r_ack := true;
            else
              r_nack := true;
            end if;
            r_multi := '0';

          end if;

        when "011010" =>
          -- r_addr = 000000000000000000000000011010--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field res_stats_addr: Address for the statistics
          -- buffer.

          if r_req then
            tmp_data64 := r_hold(63 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data64 := f_res_stats_addr_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(63 downto 0) := tmp_data64;
          end if;

          -- Read logic for block res_stats_addr_reg_low: block containing bits
          -- 31..0 of register `res_stats_addr_reg` (`RES_STATS_ADDR`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '1';

          end if;

        when "011011" =>
          -- r_addr = 000000000000000000000000011011--

          -- Read logic for block res_stats_addr_reg_high: block containing bits
          -- 63..32 of register `res_stats_addr_reg` (`RES_STATS_ADDR`).
          if r_req then

            r_data := r_hold(63 downto 32);
            if r_multi = '1' then
              r_ack := true;
            else
              r_nack := true;
            end if;
            r_multi := '0';

          end if;

        when "011100" =>
          -- r_addr = 000000000000000000000000011100--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field search_data0: The word to match. The length is
          -- set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The
          -- character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(7 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(7 downto 0) := tmp_data8;
          end if;

          -- Read logic for field search_data1: The word to match. The length is
          -- set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The
          -- character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(15 downto 8);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((1)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(15 downto 8) := tmp_data8;
          end if;

          -- Read logic for field search_data2: The word to match. The length is
          -- set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The
          -- character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(23 downto 16);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((2)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(23 downto 16) := tmp_data8;
          end if;

          -- Read logic for field search_data3: The word to match. The length is
          -- set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The
          -- character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(31 downto 24);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((3)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 24) := tmp_data8;
          end if;

          -- Read logic for block search_data0_reg: block containing bits 31..0
          -- of register `search_data0_reg` (`SEARCH_DATA0`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "011101" =>
          -- r_addr = 000000000000000000000000011101--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field search_data4: The word to match. The length is
          -- set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The
          -- character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(7 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((4)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(7 downto 0) := tmp_data8;
          end if;

          -- Read logic for field search_data5: The word to match. The length is
          -- set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The
          -- character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(15 downto 8);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((5)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(15 downto 8) := tmp_data8;
          end if;

          -- Read logic for field search_data6: The word to match. The length is
          -- set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The
          -- character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(23 downto 16);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((6)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(23 downto 16) := tmp_data8;
          end if;

          -- Read logic for field search_data7: The word to match. The length is
          -- set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The
          -- character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(31 downto 24);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((7)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 24) := tmp_data8;
          end if;

          -- Read logic for block search_data4_reg: block containing bits 31..0
          -- of register `search_data4_reg` (`SEARCH_DATA4`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "011110" =>
          -- r_addr = 000000000000000000000000011110--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field search_data8: The word to match. The length is
          -- set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The
          -- character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(7 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((8)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(7 downto 0) := tmp_data8;
          end if;

          -- Read logic for field search_data9: The word to match. The length is
          -- set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED. The
          -- character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(15 downto 8);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((9)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(15 downto 8) := tmp_data8;
          end if;

          -- Read logic for field search_data10: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(23 downto 16);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((10)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(23 downto 16) := tmp_data8;
          end if;

          -- Read logic for field search_data11: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(31 downto 24);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((11)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 24) := tmp_data8;
          end if;

          -- Read logic for block search_data8_reg: block containing bits 31..0
          -- of register `search_data8_reg` (`SEARCH_DATA8`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "011111" =>
          -- r_addr = 000000000000000000000000011111--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field search_data12: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(7 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((12)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(7 downto 0) := tmp_data8;
          end if;

          -- Read logic for field search_data13: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(15 downto 8);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((13)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(15 downto 8) := tmp_data8;
          end if;

          -- Read logic for field search_data14: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(23 downto 16);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((14)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(23 downto 16) := tmp_data8;
          end if;

          -- Read logic for field search_data15: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(31 downto 24);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((15)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 24) := tmp_data8;
          end if;

          -- Read logic for block search_data12_reg: block containing bits 31..0
          -- of register `search_data12_reg` (`SEARCH_DATA12`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "100000" =>
          -- r_addr = 000000000000000000000000100000--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field search_data16: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(7 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((16)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(7 downto 0) := tmp_data8;
          end if;

          -- Read logic for field search_data17: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(15 downto 8);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((17)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(15 downto 8) := tmp_data8;
          end if;

          -- Read logic for field search_data18: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(23 downto 16);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((18)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(23 downto 16) := tmp_data8;
          end if;

          -- Read logic for field search_data19: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(31 downto 24);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((19)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 24) := tmp_data8;
          end if;

          -- Read logic for block search_data16_reg: block containing bits 31..0
          -- of register `search_data16_reg` (`SEARCH_DATA16`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "100001" =>
          -- r_addr = 000000000000000000000000100001--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field search_data20: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(7 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((20)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(7 downto 0) := tmp_data8;
          end if;

          -- Read logic for field search_data21: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(15 downto 8);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((21)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(15 downto 8) := tmp_data8;
          end if;

          -- Read logic for field search_data22: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(23 downto 16);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((22)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(23 downto 16) := tmp_data8;
          end if;

          -- Read logic for field search_data23: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(31 downto 24);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((23)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 24) := tmp_data8;
          end if;

          -- Read logic for block search_data20_reg: block containing bits 31..0
          -- of register `search_data20_reg` (`SEARCH_DATA20`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "100010" =>
          -- r_addr = 000000000000000000000000100010--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field search_data24: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(7 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((24)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(7 downto 0) := tmp_data8;
          end if;

          -- Read logic for field search_data25: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(15 downto 8);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((25)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(15 downto 8) := tmp_data8;
          end if;

          -- Read logic for field search_data26: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(23 downto 16);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((26)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(23 downto 16) := tmp_data8;
          end if;

          -- Read logic for field search_data27: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(31 downto 24);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((27)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 24) := tmp_data8;
          end if;

          -- Read logic for block search_data24_reg: block containing bits 31..0
          -- of register `search_data24_reg` (`SEARCH_DATA24`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "100011" =>
          -- r_addr = 000000000000000000000000100011--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field search_data28: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(7 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((28)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(7 downto 0) := tmp_data8;
          end if;

          -- Read logic for field search_data29: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(15 downto 8);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((29)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(15 downto 8) := tmp_data8;
          end if;

          -- Read logic for field search_data30: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(23 downto 16);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((30)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(23 downto 16) := tmp_data8;
          end if;

          -- Read logic for field search_data31: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          if r_req then
            tmp_data8 := r_hold(31 downto 24);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data8 := f_search_data_r((31)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 24) := tmp_data8;
          end if;

          -- Read logic for block search_data28_reg: block containing bits 31..0
          -- of register `search_data28_reg` (`SEARCH_DATA28`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "100100" =>
          -- r_addr = 000000000000000000000000100100--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field search_first: Index of the first valid
          -- character in `search_data`.

          if r_req then
            tmp_data5 := r_hold(4 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data5 := f_search_first_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(4 downto 0) := tmp_data5;
          end if;

          -- Read logic for field whole_words: selects between whole-words and
          -- regular pattern matching.

          if r_req then
            tmp_data := r_hold(8);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data := f_whole_words_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(8) := tmp_data;
          end if;

          -- Read logic for field min_matches: Minimum number of times that the
          -- word needs to occur in the article text for the page to be
          -- considered to match.

          if r_req then
            tmp_data16 := r_hold(31 downto 16);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data16 := f_min_matches_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 16) := tmp_data16;
          end if;

          -- Read logic for block search_cfg: block containing bits 31..0 of
          -- register `search_cfg` (`SEARCH_CFG`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "100101" =>
          -- r_addr = 000000000000000000000000100101--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field result_size: Number of matches to return. The
          -- kernel will always write this many match records; it'll just pad
          -- with empty title strings and 0 for the match count when less
          -- articles match than this value implies, and it'll void any matches
          -- it doesn't have room for.

          if r_req then
            tmp_data32 := r_hold(31 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data32 := f_result_size_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 0) := tmp_data32;
          end if;

          -- Read logic for block result_size_reg: block containing bits 31..0
          -- of register `result_size_reg` (`RESULT_SIZE`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "100110" =>
          -- r_addr = 000000000000000000000000100110--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field deadcode: magic number used to test MMIO
          -- access.

          if r_req then
            tmp_data32 := r_hold(31 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data32 := f_deadcode_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 0) := tmp_data32;
          end if;

          -- Read logic for block deadcode_reg: block containing bits 31..0 of
          -- register `deadcode_reg` (`DEADCODE`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "100111" =>
          -- r_addr = 000000000000000000000000100111--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field num_word_matches: Number of times that the
          -- word occured in the dataset.

          if r_req then
            tmp_data32 := r_hold(31 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data32 := f_num_word_matches_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 0) := tmp_data32;
          end if;

          -- Read logic for block num_word_matches_reg: block containing bits
          -- 31..0 of register `num_word_matches_reg` (`NUM_WORD_MATCHES`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "101000" =>
          -- r_addr = 000000000000000000000000101000--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field num_page_matches: Number of pages that contain
          -- the specified word at least as many times as requested by
          -- `min_match`.

          if r_req then
            tmp_data32 := r_hold(31 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data32 := f_num_page_matches_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 0) := tmp_data32;
          end if;

          -- Read logic for block num_page_matches_reg: block containing bits
          -- 31..0 of register `num_page_matches_reg` (`NUM_PAGE_MATCHES`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "101001" =>
          -- r_addr = 000000000000000000000000101001--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field max_word_matches: Maximum number of matches in
          -- any single page.

          if r_req then
            tmp_data16 := r_hold(15 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data16 := f_max_word_matches_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(15 downto 0) := tmp_data16;
          end if;

          -- Read logic for block max_word_matches_reg: block containing bits
          -- 31..0 of register `max_word_matches_reg` (`MAX_WORD_MATCHES`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when "101010" =>
          -- r_addr = 000000000000000000000000101010--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field max_page_idx: Index of the page with the most
          -- matches, relative to `first_idx` in the command registers.

          if r_req then
            tmp_data20 := r_hold(19 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data20 := f_max_page_idx_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(19 downto 0) := tmp_data20;
          end if;

          -- Read logic for block max_page_idx_reg: block containing bits 31..0
          -- of register `max_page_idx_reg` (`MAX_PAGE_IDX`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

        when others => -- "101011"
          -- r_addr = 000000000000000000000000101011--

          if r_req then

            -- Clear holding register location prior to read.
            r_hold := (others => '0');

          end if;

          -- Read logic for field cycle_count: Number of cycles taken by the
          -- last command.

          if r_req then
            tmp_data32 := r_hold(31 downto 0);
          end if;
          if r_req then

            -- Regular access logic. Read mode: enabled.
            tmp_data32 := f_cycle_count_r((0)).d;
            r_ack := true;

          end if;
          if r_req then
            r_hold(31 downto 0) := tmp_data32;
          end if;

          -- Read logic for block cycle_count_reg: block containing bits 31..0
          -- of register `cycle_count_reg` (`CYCLE_COUNT`).
          if r_req then

            r_data := r_hold(31 downto 0);
            r_multi := '0';

          end if;

      end case;

      -------------------------------------------------------------------------
      -- Bus write logic
      -------------------------------------------------------------------------

      -- Construct the subaddresses for write mode.
      subaddr_none(0) := '0';

      -- Write address decoder.
      case w_addr(7 downto 2) is
        when "000000" =>
          -- w_addr = 000000000000000000000000000000--

          -- Write logic for block ctrl: block containing bits 31..0 of register
          -- `ctrl` (`CTRL`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field start: start signal.

          tmp_data := w_hold(0);
          tmp_strb := w_hstb(0);
          if w_req then

            -- Regular access logic.
            if tmp_data = '1' then
              f_start_r((0)).busy := '1';
              intsigs_start := '1';
            end if;
            w_ack := true;

          end if;

        when "000001" =>
          -- w_addr = 000000000000000000000000000001--

          -- Write logic for block gier_reg: block containing bits 31..0 of
          -- register `gier_reg` (`GIER_REG`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field gier: global interrupt enable register.

          tmp_data := w_hold(0);
          tmp_strb := w_hstb(0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_gier_r((0)).d := (f_gier_r((0)).d and not tmp_strb) or tmp_data;
            w_ack := true;

          end if;

        when "000010" =>
          -- w_addr = 000000000000000000000000000010--

          -- Write logic for block iier: block containing bits 31..0 of register
          -- `iier` (`IIER`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field iier_done: selects whether kernel completion
          -- triggers an interrupt.

          tmp_data := w_hold(0);
          tmp_strb := w_hstb(0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_iier_done_r((0)).d := (f_iier_done_r((0)).d and not tmp_strb)
                or tmp_data;
            w_ack := true;

          end if;

        when "000011" =>
          -- w_addr = 000000000000000000000000000011--

          -- Write logic for block iisr: block containing bits 31..0 of register
          -- `iisr` (`IISR`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field iisr_done: interrupt flag for kernel
          -- completion.

          tmp_data := w_hold(0);
          tmp_strb := w_hstb(0);
          if w_req then

            -- Regular access logic.
            f_iisr_done_r((0)).flag := f_iisr_done_r((0)).flag xor tmp_data;
            w_ack := true;

          end if;

        when "000100" =>
          -- w_addr = 000000000000000000000000000100--

          -- Write logic for block title_offs_addr_reg_low: block containing
          -- bits 31..0 of register `title_offs_addr_reg` (`TITLE_OFFS_ADDR`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '1';
          end if;
          if w_req then
            w_ack := true;
          end if;

        when "000101" =>
          -- w_addr = 000000000000000000000000000101--

          -- Write logic for block title_offs_addr_reg_high: block containing
          -- bits 63..32 of register `title_offs_addr_reg` (`TITLE_OFFS_ADDR`).
          if w_req or w_lreq then
            w_hold(63 downto 32) := w_data;
            w_hstb(63 downto 32) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field title_offs_addr: Address for the article
          -- title offset buffer.

          tmp_data64 := w_hold(63 downto 0);
          tmp_strb64 := w_hstb(63 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_title_offs_addr_r((0)).d
                := (f_title_offs_addr_r((0)).d and not tmp_strb64)
                or tmp_data64;
            w_ack := true;

          end if;

        when "000110" =>
          -- w_addr = 000000000000000000000000000110--

          -- Write logic for block title_val_addr_reg_low: block containing bits
          -- 31..0 of register `title_val_addr_reg` (`TITLE_VAL_ADDR`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '1';
          end if;
          if w_req then
            w_ack := true;
          end if;

        when "000111" =>
          -- w_addr = 000000000000000000000000000111--

          -- Write logic for block title_val_addr_reg_high: block containing
          -- bits 63..32 of register `title_val_addr_reg` (`TITLE_VAL_ADDR`).
          if w_req or w_lreq then
            w_hold(63 downto 32) := w_data;
            w_hstb(63 downto 32) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field title_val_addr: Address for the article title
          -- value buffer.

          tmp_data64 := w_hold(63 downto 0);
          tmp_strb64 := w_hstb(63 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_title_val_addr_r((0)).d
                := (f_title_val_addr_r((0)).d and not tmp_strb64) or tmp_data64;
            w_ack := true;

          end if;

        when "001000" =>
          -- w_addr = 000000000000000000000000001000--

          -- Write logic for block text_offs_addr_reg_low: block containing bits
          -- 31..0 of register `text_offs_addr_reg` (`TEXT_OFFS_ADDR`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '1';
          end if;
          if w_req then
            w_ack := true;
          end if;

        when "001001" =>
          -- w_addr = 000000000000000000000000001001--

          -- Write logic for block text_offs_addr_reg_high: block containing
          -- bits 63..32 of register `text_offs_addr_reg` (`TEXT_OFFS_ADDR`).
          if w_req or w_lreq then
            w_hold(63 downto 32) := w_data;
            w_hstb(63 downto 32) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field text_offs_addr: Address for the compressed
          -- article data offset buffer.

          tmp_data64 := w_hold(63 downto 0);
          tmp_strb64 := w_hstb(63 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_text_offs_addr_r((0)).d
                := (f_text_offs_addr_r((0)).d and not tmp_strb64) or tmp_data64;
            w_ack := true;

          end if;

        when "001010" =>
          -- w_addr = 000000000000000000000000001010--

          -- Write logic for block text_val_addr_reg_low: block containing bits
          -- 31..0 of register `text_val_addr_reg` (`TEXT_VAL_ADDR`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '1';
          end if;
          if w_req then
            w_ack := true;
          end if;

        when "001011" =>
          -- w_addr = 000000000000000000000000001011--

          -- Write logic for block text_val_addr_reg_high: block containing bits
          -- 63..32 of register `text_val_addr_reg` (`TEXT_VAL_ADDR`).
          if w_req or w_lreq then
            w_hold(63 downto 32) := w_data;
            w_hstb(63 downto 32) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field text_val_addr: Address for the compressed
          -- article data value buffer.

          tmp_data64 := w_hold(63 downto 0);
          tmp_strb64 := w_hstb(63 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_text_val_addr_r((0)).d
                := (f_text_val_addr_r((0)).d and not tmp_strb64) or tmp_data64;
            w_ack := true;

          end if;

        when "001100" =>
          -- w_addr = 000000000000000000000000001100--

          -- Write logic for block index0_reg: block containing bits 31..0 of
          -- register `index0_reg` (`INDEX0`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field index0: input dataset indices.

          tmp_data20 := w_hold(19 downto 0);
          tmp_strb20 := w_hstb(19 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_index_r((0)).d := (f_index_r((0)).d and not tmp_strb20)
                or tmp_data20;
            w_ack := true;

          end if;

        when "001101" =>
          -- w_addr = 000000000000000000000000001101--

          -- Write logic for block index1_reg: block containing bits 31..0 of
          -- register `index1_reg` (`INDEX1`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field index1: input dataset indices.

          tmp_data20 := w_hold(19 downto 0);
          tmp_strb20 := w_hstb(19 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_index_r((1)).d := (f_index_r((1)).d and not tmp_strb20)
                or tmp_data20;
            w_ack := true;

          end if;

        when "001110" =>
          -- w_addr = 000000000000000000000000001110--

          -- Write logic for block index2_reg: block containing bits 31..0 of
          -- register `index2_reg` (`INDEX2`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field index2: input dataset indices.

          tmp_data20 := w_hold(19 downto 0);
          tmp_strb20 := w_hstb(19 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_index_r((2)).d := (f_index_r((2)).d and not tmp_strb20)
                or tmp_data20;
            w_ack := true;

          end if;

        when "001111" =>
          -- w_addr = 000000000000000000000000001111--

          -- Write logic for block index3_reg: block containing bits 31..0 of
          -- register `index3_reg` (`INDEX3`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field index3: input dataset indices.

          tmp_data20 := w_hold(19 downto 0);
          tmp_strb20 := w_hstb(19 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_index_r((3)).d := (f_index_r((3)).d and not tmp_strb20)
                or tmp_data20;
            w_ack := true;

          end if;

        when "010000" =>
          -- w_addr = 000000000000000000000000010000--

          -- Write logic for block index4_reg: block containing bits 31..0 of
          -- register `index4_reg` (`INDEX4`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field index4: input dataset indices.

          tmp_data20 := w_hold(19 downto 0);
          tmp_strb20 := w_hstb(19 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_index_r((4)).d := (f_index_r((4)).d and not tmp_strb20)
                or tmp_data20;
            w_ack := true;

          end if;

        when "010100" =>
          -- w_addr = 000000000000000000000000010100--

          -- Write logic for block res_title_offs_addr_reg_low: block containing
          -- bits 31..0 of register `res_title_offs_addr_reg`
          -- (`RES_TITLE_OFFS_ADDR`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '1';
          end if;
          if w_req then
            w_ack := true;
          end if;

        when "010101" =>
          -- w_addr = 000000000000000000000000010101--

          -- Write logic for block res_title_offs_addr_reg_high: block
          -- containing bits 63..32 of register `res_title_offs_addr_reg`
          -- (`RES_TITLE_OFFS_ADDR`).
          if w_req or w_lreq then
            w_hold(63 downto 32) := w_data;
            w_hstb(63 downto 32) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field res_title_offs_addr: Address for the matched
          -- article title offset buffer.

          tmp_data64 := w_hold(63 downto 0);
          tmp_strb64 := w_hstb(63 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_res_title_offs_addr_r((0)).d
                := (f_res_title_offs_addr_r((0)).d and not tmp_strb64)
                or tmp_data64;
            w_ack := true;

          end if;

        when "010110" =>
          -- w_addr = 000000000000000000000000010110--

          -- Write logic for block res_title_val_addr_reg_low: block containing
          -- bits 31..0 of register `res_title_val_addr_reg`
          -- (`RES_TITLE_VAL_ADDR`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '1';
          end if;
          if w_req then
            w_ack := true;
          end if;

        when "010111" =>
          -- w_addr = 000000000000000000000000010111--

          -- Write logic for block res_title_val_addr_reg_high: block containing
          -- bits 63..32 of register `res_title_val_addr_reg`
          -- (`RES_TITLE_VAL_ADDR`).
          if w_req or w_lreq then
            w_hold(63 downto 32) := w_data;
            w_hstb(63 downto 32) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field res_title_val_addr: Address for the matched
          -- article title value buffer.

          tmp_data64 := w_hold(63 downto 0);
          tmp_strb64 := w_hstb(63 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_res_title_val_addr_r((0)).d
                := (f_res_title_val_addr_r((0)).d and not tmp_strb64)
                or tmp_data64;
            w_ack := true;

          end if;

        when "011000" =>
          -- w_addr = 000000000000000000000000011000--

          -- Write logic for block res_match_addr_reg_low: block containing bits
          -- 31..0 of register `res_match_addr_reg` (`RES_MATCH_ADDR`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '1';
          end if;
          if w_req then
            w_ack := true;
          end if;

        when "011001" =>
          -- w_addr = 000000000000000000000000011001--

          -- Write logic for block res_match_addr_reg_high: block containing
          -- bits 63..32 of register `res_match_addr_reg` (`RES_MATCH_ADDR`).
          if w_req or w_lreq then
            w_hold(63 downto 32) := w_data;
            w_hstb(63 downto 32) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field res_match_addr: Address for the match count
          -- value buffer.

          tmp_data64 := w_hold(63 downto 0);
          tmp_strb64 := w_hstb(63 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_res_match_addr_r((0)).d
                := (f_res_match_addr_r((0)).d and not tmp_strb64) or tmp_data64;
            w_ack := true;

          end if;

        when "011010" =>
          -- w_addr = 000000000000000000000000011010--

          -- Write logic for block res_stats_addr_reg_low: block containing bits
          -- 31..0 of register `res_stats_addr_reg` (`RES_STATS_ADDR`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '1';
          end if;
          if w_req then
            w_ack := true;
          end if;

        when "011011" =>
          -- w_addr = 000000000000000000000000011011--

          -- Write logic for block res_stats_addr_reg_high: block containing
          -- bits 63..32 of register `res_stats_addr_reg` (`RES_STATS_ADDR`).
          if w_req or w_lreq then
            w_hold(63 downto 32) := w_data;
            w_hstb(63 downto 32) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field res_stats_addr: Address for the statistics
          -- buffer.

          tmp_data64 := w_hold(63 downto 0);
          tmp_strb64 := w_hstb(63 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_res_stats_addr_r((0)).d
                := (f_res_stats_addr_r((0)).d and not tmp_strb64) or tmp_data64;
            w_ack := true;

          end if;

        when "011100" =>
          -- w_addr = 000000000000000000000000011100--

          -- Write logic for block search_data0_reg: block containing bits 31..0
          -- of register `search_data0_reg` (`SEARCH_DATA0`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field search_data0: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(7 downto 0);
          tmp_strb8 := w_hstb(7 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((0)).d := (f_search_data_r((0)).d and not tmp_strb8)
                or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data1: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(15 downto 8);
          tmp_strb8 := w_hstb(15 downto 8);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((1)).d := (f_search_data_r((1)).d and not tmp_strb8)
                or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data2: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(23 downto 16);
          tmp_strb8 := w_hstb(23 downto 16);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((2)).d := (f_search_data_r((2)).d and not tmp_strb8)
                or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data3: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(31 downto 24);
          tmp_strb8 := w_hstb(31 downto 24);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((3)).d := (f_search_data_r((3)).d and not tmp_strb8)
                or tmp_data8;
            w_ack := true;

          end if;

        when "011101" =>
          -- w_addr = 000000000000000000000000011101--

          -- Write logic for block search_data4_reg: block containing bits 31..0
          -- of register `search_data4_reg` (`SEARCH_DATA4`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field search_data4: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(7 downto 0);
          tmp_strb8 := w_hstb(7 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((4)).d := (f_search_data_r((4)).d and not tmp_strb8)
                or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data5: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(15 downto 8);
          tmp_strb8 := w_hstb(15 downto 8);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((5)).d := (f_search_data_r((5)).d and not tmp_strb8)
                or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data6: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(23 downto 16);
          tmp_strb8 := w_hstb(23 downto 16);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((6)).d := (f_search_data_r((6)).d and not tmp_strb8)
                or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data7: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(31 downto 24);
          tmp_strb8 := w_hstb(31 downto 24);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((7)).d := (f_search_data_r((7)).d and not tmp_strb8)
                or tmp_data8;
            w_ack := true;

          end if;

        when "011110" =>
          -- w_addr = 000000000000000000000000011110--

          -- Write logic for block search_data8_reg: block containing bits 31..0
          -- of register `search_data8_reg` (`SEARCH_DATA8`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field search_data8: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(7 downto 0);
          tmp_strb8 := w_hstb(7 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((8)).d := (f_search_data_r((8)).d and not tmp_strb8)
                or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data9: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(15 downto 8);
          tmp_strb8 := w_hstb(15 downto 8);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((9)).d := (f_search_data_r((9)).d and not tmp_strb8)
                or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data10: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(23 downto 16);
          tmp_strb8 := w_hstb(23 downto 16);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((10)).d
                := (f_search_data_r((10)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data11: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(31 downto 24);
          tmp_strb8 := w_hstb(31 downto 24);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((11)).d
                := (f_search_data_r((11)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

        when "011111" =>
          -- w_addr = 000000000000000000000000011111--

          -- Write logic for block search_data12_reg: block containing bits
          -- 31..0 of register `search_data12_reg` (`SEARCH_DATA12`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field search_data12: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(7 downto 0);
          tmp_strb8 := w_hstb(7 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((12)).d
                := (f_search_data_r((12)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data13: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(15 downto 8);
          tmp_strb8 := w_hstb(15 downto 8);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((13)).d
                := (f_search_data_r((13)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data14: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(23 downto 16);
          tmp_strb8 := w_hstb(23 downto 16);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((14)).d
                := (f_search_data_r((14)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data15: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(31 downto 24);
          tmp_strb8 := w_hstb(31 downto 24);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((15)).d
                := (f_search_data_r((15)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

        when "100000" =>
          -- w_addr = 000000000000000000000000100000--

          -- Write logic for block search_data16_reg: block containing bits
          -- 31..0 of register `search_data16_reg` (`SEARCH_DATA16`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field search_data16: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(7 downto 0);
          tmp_strb8 := w_hstb(7 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((16)).d
                := (f_search_data_r((16)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data17: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(15 downto 8);
          tmp_strb8 := w_hstb(15 downto 8);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((17)).d
                := (f_search_data_r((17)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data18: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(23 downto 16);
          tmp_strb8 := w_hstb(23 downto 16);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((18)).d
                := (f_search_data_r((18)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data19: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(31 downto 24);
          tmp_strb8 := w_hstb(31 downto 24);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((19)).d
                := (f_search_data_r((19)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

        when "100001" =>
          -- w_addr = 000000000000000000000000100001--

          -- Write logic for block search_data20_reg: block containing bits
          -- 31..0 of register `search_data20_reg` (`SEARCH_DATA20`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field search_data20: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(7 downto 0);
          tmp_strb8 := w_hstb(7 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((20)).d
                := (f_search_data_r((20)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data21: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(15 downto 8);
          tmp_strb8 := w_hstb(15 downto 8);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((21)).d
                := (f_search_data_r((21)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data22: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(23 downto 16);
          tmp_strb8 := w_hstb(23 downto 16);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((22)).d
                := (f_search_data_r((22)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data23: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(31 downto 24);
          tmp_strb8 := w_hstb(31 downto 24);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((23)).d
                := (f_search_data_r((23)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

        when "100010" =>
          -- w_addr = 000000000000000000000000100010--

          -- Write logic for block search_data24_reg: block containing bits
          -- 31..0 of register `search_data24_reg` (`SEARCH_DATA24`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field search_data24: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(7 downto 0);
          tmp_strb8 := w_hstb(7 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((24)).d
                := (f_search_data_r((24)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data25: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(15 downto 8);
          tmp_strb8 := w_hstb(15 downto 8);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((25)).d
                := (f_search_data_r((25)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data26: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(23 downto 16);
          tmp_strb8 := w_hstb(23 downto 16);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((26)).d
                := (f_search_data_r((26)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data27: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(31 downto 24);
          tmp_strb8 := w_hstb(31 downto 24);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((27)).d
                := (f_search_data_r((27)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

        when "100011" =>
          -- w_addr = 000000000000000000000000100011--

          -- Write logic for block search_data28_reg: block containing bits
          -- 31..0 of register `search_data28_reg` (`SEARCH_DATA28`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field search_data28: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(7 downto 0);
          tmp_strb8 := w_hstb(7 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((28)).d
                := (f_search_data_r((28)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data29: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(15 downto 8);
          tmp_strb8 := w_hstb(15 downto 8);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((29)).d
                := (f_search_data_r((29)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data30: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(23 downto 16);
          tmp_strb8 := w_hstb(23 downto 16);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((30)).d
                := (f_search_data_r((30)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

          -- Write logic for field search_data31: The word to match. The length
          -- is set by `search_first`; that is, THE WORD MUST BE RIGHT-ALIGNED.
          -- The character used to pad the unused bytes before the word is don't
          -- care.

          tmp_data8 := w_hold(31 downto 24);
          tmp_strb8 := w_hstb(31 downto 24);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_data_r((31)).d
                := (f_search_data_r((31)).d and not tmp_strb8) or tmp_data8;
            w_ack := true;

          end if;

        when "100100" =>
          -- w_addr = 000000000000000000000000100100--

          -- Write logic for block search_cfg: block containing bits 31..0 of
          -- register `search_cfg` (`SEARCH_CFG`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field search_first: Index of the first valid
          -- character in `search_data`.

          tmp_data5 := w_hold(4 downto 0);
          tmp_strb5 := w_hstb(4 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_search_first_r((0)).d
                := (f_search_first_r((0)).d and not tmp_strb5) or tmp_data5;
            w_ack := true;

          end if;

          -- Write logic for field whole_words: selects between whole-words and
          -- regular pattern matching.

          tmp_data := w_hold(8);
          tmp_strb := w_hstb(8);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_whole_words_r((0)).d := (f_whole_words_r((0)).d and not tmp_strb)
                or tmp_data;
            w_ack := true;

          end if;

          -- Write logic for field min_matches: Minimum number of times that the
          -- word needs to occur in the article text for the page to be
          -- considered to match.

          tmp_data16 := w_hold(31 downto 16);
          tmp_strb16 := w_hstb(31 downto 16);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_min_matches_r((0)).d
                := (f_min_matches_r((0)).d and not tmp_strb16) or tmp_data16;
            w_ack := true;

          end if;

        when others => -- "100101"
          -- w_addr = 000000000000000000000000100101--

          -- Write logic for block result_size_reg: block containing bits 31..0
          -- of register `result_size_reg` (`RESULT_SIZE`).
          if w_req or w_lreq then
            w_hold(31 downto 0) := w_data;
            w_hstb(31 downto 0) := w_strb;
            w_multi := '0';
          end if;

          -- Write logic for field result_size: Number of matches to return. The
          -- kernel will always write this many match records; it'll just pad
          -- with empty title strings and 0 for the match count when less
          -- articles match than this value implies, and it'll void any matches
          -- it doesn't have room for.

          tmp_data32 := w_hold(31 downto 0);
          tmp_strb32 := w_hstb(31 downto 0);
          if w_req then

            -- Regular access logic. Write mode: masked.

            f_result_size_r((0)).d
                := (f_result_size_r((0)).d and not tmp_strb32) or tmp_data32;
            w_ack := true;

          end if;

      end case;

      -------------------------------------------------------------------------
      -- Generated field logic
      -------------------------------------------------------------------------

      -- Post-bus logic for field start: start signal.

      if reset = '1' then
        f_start_r((0)).busy := '0';
      end if;

      -- Post-bus logic for field done: done signal.

      if reset = '1' then
        f_done_r((0)).done_reg := '0';
      end if;

      -- Post-bus logic for field idle: idle signal.

      if reset = '1' then
        f_idle_r((0)).busy := '0';
      end if;

      -- Post-bus logic for field gier: global interrupt enable register.

      -- Handle reset for field gier.
      if reset = '1' then
        f_gier_r((0)).d := '0';
        f_gier_r((0)).v := '1';
      end if;
      -- Assign the internal signal for field gier.
      intsig_gier := f_gier_r((0)).d;

      -- Post-bus logic for field iier_done: selects whether kernel completion
      -- triggers an interrupt.

      -- Handle reset for field iier_done.
      if reset = '1' then
        f_iier_done_r((0)).d := '0';
        f_iier_done_r((0)).v := '1';
      end if;
      -- Assign the internal signal for field iier_done.
      intsig_iier_done := f_iier_done_r((0)).d;

      -- Post-bus logic for field iisr_done: interrupt flag for kernel
      -- completion.

      if reset = '1' then
        f_iisr_done_r((0)).flag := '0';
      end if;

      -- Post-bus logic for field title_offs_addr: Address for the article title
      -- offset buffer.

      -- Handle reset for field title_offs_addr.
      if reset = '1' then
        f_title_offs_addr_r((0)).d := (others => '0');
        f_title_offs_addr_r((0)).v := '0';
      end if;
      -- Assign the read outputs for field title_offs_addr.
      g_filt_o.f_title_offs_addr_data <= f_title_offs_addr_r((0)).d;

      -- Post-bus logic for field title_val_addr: Address for the article title
      -- value buffer.

      -- Handle reset for field title_val_addr.
      if reset = '1' then
        f_title_val_addr_r((0)).d := (others => '0');
        f_title_val_addr_r((0)).v := '0';
      end if;
      -- Assign the read outputs for field title_val_addr.
      g_filt_o.f_title_val_addr_data <= f_title_val_addr_r((0)).d;

      -- Post-bus logic for field text_offs_addr: Address for the compressed
      -- article data offset buffer.

      -- Handle reset for field text_offs_addr.
      if reset = '1' then
        f_text_offs_addr_r((0)).d := (others => '0');
        f_text_offs_addr_r((0)).v := '0';
      end if;
      -- Assign the read outputs for field text_offs_addr.
      g_cmd_o.f_text_offs_addr_data <= f_text_offs_addr_r((0)).d;

      -- Post-bus logic for field text_val_addr: Address for the compressed
      -- article data value buffer.

      -- Handle reset for field text_val_addr.
      if reset = '1' then
        f_text_val_addr_r((0)).d := (others => '0');
        f_text_val_addr_r((0)).v := '0';
      end if;
      -- Assign the read outputs for field text_val_addr.
      g_cmd_o.f_text_val_addr_data <= f_text_val_addr_r((0)).d;

      -- Post-bus logic for field group index: input dataset indices.
      for i in 0 to 4 loop

        -- Handle reset for field index.
        if reset = '1' then
          f_index_r((i)).d := (others => '0');
          f_index_r((i)).v := '0';
        end if;
        -- Assign the read outputs for field index.
        g_cmd_o.f_index_data((i)) <= f_index_r((i)).d;

      end loop;

      -- Post-bus logic for field res_title_offs_addr: Address for the matched
      -- article title offset buffer.

      -- Handle reset for field res_title_offs_addr.
      if reset = '1' then
        f_res_title_offs_addr_r((0)).d := (others => '0');
        f_res_title_offs_addr_r((0)).v := '0';
      end if;
      -- Assign the read outputs for field res_title_offs_addr.
      g_cmd_o.f_res_title_offs_addr_data <= f_res_title_offs_addr_r((0)).d;

      -- Post-bus logic for field res_title_val_addr: Address for the matched
      -- article title value buffer.

      -- Handle reset for field res_title_val_addr.
      if reset = '1' then
        f_res_title_val_addr_r((0)).d := (others => '0');
        f_res_title_val_addr_r((0)).v := '0';
      end if;
      -- Assign the read outputs for field res_title_val_addr.
      g_cmd_o.f_res_title_val_addr_data <= f_res_title_val_addr_r((0)).d;

      -- Post-bus logic for field res_match_addr: Address for the match count
      -- value buffer.

      -- Handle reset for field res_match_addr.
      if reset = '1' then
        f_res_match_addr_r((0)).d := (others => '0');
        f_res_match_addr_r((0)).v := '0';
      end if;
      -- Assign the read outputs for field res_match_addr.
      g_cmd_o.f_res_match_addr_data <= f_res_match_addr_r((0)).d;

      -- Post-bus logic for field res_stats_addr: Address for the statistics
      -- buffer.

      -- Handle reset for field res_stats_addr.
      if reset = '1' then
        f_res_stats_addr_r((0)).d := (others => '0');
        f_res_stats_addr_r((0)).v := '0';
      end if;
      -- Assign the read outputs for field res_stats_addr.
      g_cmd_o.f_res_stats_addr_data <= f_res_stats_addr_r((0)).d;

      -- Post-bus logic for field group search_data: The word to match. The
      -- length is set by `search_first`; that is, THE WORD MUST BE
      -- RIGHT-ALIGNED. The character used to pad the unused bytes before the
      -- word is don't care.
      for i in 0 to 31 loop

        -- Handle reset for field search_data.
        if reset = '1' then
          f_search_data_r((i)).d := (others => '0');
          f_search_data_r((i)).v := '0';
        end if;
        -- Assign the read outputs for field search_data.
        g_cfg_o.f_search_data_data((i)) <= f_search_data_r((i)).d;

      end loop;

      -- Post-bus logic for field search_first: Index of the first valid
      -- character in `search_data`.

      -- Handle reset for field search_first.
      if reset = '1' then
        f_search_first_r((0)).d := (others => '0');
        f_search_first_r((0)).v := '0';
      end if;
      -- Assign the read outputs for field search_first.
      g_cfg_o.f_search_first_data <= f_search_first_r((0)).d;

      -- Post-bus logic for field whole_words: selects between whole-words and
      -- regular pattern matching.

      -- Handle reset for field whole_words.
      if reset = '1' then
        f_whole_words_r((0)).d := '0';
        f_whole_words_r((0)).v := '0';
      end if;
      -- Assign the read outputs for field whole_words.
      g_cfg_o.f_whole_words_data <= f_whole_words_r((0)).d;

      -- Post-bus logic for field min_matches: Minimum number of times that the
      -- word needs to occur in the article text for the page to be considered
      -- to match.

      -- Handle reset for field min_matches.
      if reset = '1' then
        f_min_matches_r((0)).d := (others => '0');
        f_min_matches_r((0)).v := '0';
      end if;
      -- Assign the read outputs for field min_matches.
      g_filt_o.f_min_matches_data <= f_min_matches_r((0)).d;

      -- Post-bus logic for field result_size: Number of matches to return. The
      -- kernel will always write this many match records; it'll just pad with
      -- empty title strings and 0 for the match count when less articles match
      -- than this value implies, and it'll void any matches it doesn't have
      -- room for.

      -- Handle reset for field result_size.
      if reset = '1' then
        f_result_size_r((0)).d := (others => '0');
        f_result_size_r((0)).v := '0';
      end if;
      -- Assign the read outputs for field result_size.
      g_filt_o.f_result_size_data <= f_result_size_r((0)).d;

      -- Post-bus logic for field deadcode: magic number used to test MMIO
      -- access.

      -- Handle reset for field deadcode.
      if reset = '1' then
        f_deadcode_r((0)).d := "11011110101011011100000011011110";
        f_deadcode_r((0)).v := '1';
      end if;

      -------------------------------------------------------------------------
      -- Boilerplate bus access logic
      -------------------------------------------------------------------------
      -- Perform the write action dictated by the field logic.
      if w_req and not w_block then

        -- Accept write requests by invalidating the request holding
        -- registers.
        awl.valid := '0';
        wl.valid := '0';

        -- Send the appropriate write response.
        bus_v.b.valid := '1';
        if w_nack then
          bus_v.b.resp := AXI4L_RESP_SLVERR;
        elsif w_ack then
          bus_v.b.resp := AXI4L_RESP_OKAY;
        else
          bus_v.b.resp := AXI4L_RESP_DECERR;
        end if;

      end if;

      -- Perform the read action dictated by the field logic.
      if r_req and not r_block then

        -- Accept read requests by invalidating the request holding
        -- registers.
        arl.valid := '0';

        -- Send the appropriate read response.
        bus_v.r.valid := '1';
        if r_nack then
          bus_v.r.resp := AXI4L_RESP_SLVERR;
        elsif r_ack then
          bus_v.r.resp := AXI4L_RESP_OKAY;
          bus_v.r.data := r_data;
        else
          bus_v.r.resp := AXI4L_RESP_DECERR;
        end if;

      end if;

      -- If we're at the end of a multi-word write, clear the write strobe
      -- holding register to prevent previously written data from leaking into
      -- later partial writes.
      if w_multi = '0' then
        w_hstb := (others => '0');
      end if;

      -- Mark the incoming channels as ready when their respective holding
      -- registers are empty.
      bus_v.aw.ready := not awl.valid;
      bus_v.w.ready := not wl.valid;
      bus_v.ar.ready := not arl.valid;

      -------------------------------------------------------------------------
      -- Internal signal logic
      -------------------------------------------------------------------------

      -- Logic for internal signal start.
      intsigr_start := intsigs_start;
      intsigs_start := '0';
      if reset = '1' then
        intsigr_start := '0';
      end if;

      -- Logic for internal signal done.
      intsigr_done := intsigs_done;
      intsigs_done := '0';
      if reset = '1' then
        intsigr_done := '0';
      end if;

      -- Logic for internal signal starting.
      intsigr_starting := intsigs_starting;
      intsigs_starting := '0';
      if reset = '1' then
        intsigr_starting := '0';
      end if;

      -- Logic for internal signal gier.
      if reset = '1' then
        intsig_gier := '0';
      end if;

      -- Logic for internal signal iier_done.
      if reset = '1' then
        intsig_iier_done := '0';
      end if;

      -- Logic for internal signal interrupt.
      intsigr_interrupt := intsigs_interrupt;
      intsigs_interrupt := '0';
      if reset = '1' then
        intsigr_interrupt := '0';
      end if;

      -- Logic for output port for internal signal start.
      s_start <= intsigr_start;

      -- Logic for output port for internal signal interrupt.
      s_interrupt <= intsigr_interrupt;

      -------------------------------------------------------------------------
      -- Handle AXI4-lite bus reset
      -------------------------------------------------------------------------
      -- Reset overrides everything, so it comes last. Note that field
      -- registers are *not* reset here; this would complicate code generation.
      -- Instead, the generated field logic blocks include reset logic for the
      -- field-specific registers.
      if reset = '1' then
        bus_v      := AXI4L32_S2M_RESET;
        awl        := AXI4LA_RESET;
        wl         := AXI4LW32_RESET;
        arl        := AXI4LA_RESET;
        w_hstb     := (others => '0');
        w_hold     := (others => '0');
        w_multi    := '0';
        r_multi    := '0';
        r_hold     := (others => '0');
      end if;

      mmio_awready <= bus_v.aw.ready;
      mmio_wready  <= bus_v.w.ready;
      mmio_bvalid  <= bus_v.b.valid;
      mmio_bresp   <= bus_v.b.resp;
      mmio_arready <= bus_v.ar.ready;
      mmio_rvalid  <= bus_v.r.valid;
      mmio_rdata   <= bus_v.r.data;
      mmio_rresp   <= bus_v.r.resp;
      mmio_uirq    <= bus_v.u.irq;

    end if;
  end process;
end behavioral;
