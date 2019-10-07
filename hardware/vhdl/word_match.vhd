library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.vhsnunzip_pkg.all;
use work.vhdmmio_pkg.all;
use work.mmio_pkg.all;

entity word_match is
  generic (
    BUS_ADDR_WIDTH            : integer := 64
  );
  port (
    kcd_clk                   : in  std_logic;
    kcd_reset                 : in  std_logic;

    ---------------------------------------------------------------------------
    -- AXI-lite MMIO control interface
    ---------------------------------------------------------------------------
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
    mmio_rresp                : out std_logic_vector(1 downto 0);

    ---------------------------------------------------------------------------
    -- Article title input interface
    ---------------------------------------------------------------------------
    -- Length stream. last flag relates to command. count is unused.
    pages_title_valid         : in  std_logic;
    pages_title_ready         : out std_logic;
    pages_title_dvalid        : in  std_logic;
    pages_title_last          : in  std_logic;
    pages_title_length        : in  std_logic_vector(31 downto 0);
    pages_title_count         : in  std_logic_vector(0 downto 0);

    -- Character stream. last flag relates to the end of the title string.
    -- count is unused.
    pages_title_chars_valid   : in  std_logic;
    pages_title_chars_ready   : out std_logic;
    pages_title_chars_dvalid  : in  std_logic;
    pages_title_chars_last    : in  std_logic;
    pages_title_chars_data    : in  std_logic_vector(7 downto 0);
    pages_title_chars_count   : in  std_logic_vector(0 downto 0);

    -- Command stream.
    pages_title_cmd_valid     : out std_logic;
    pages_title_cmd_ready     : in  std_logic;
    pages_title_cmd_firstIdx  : out std_logic_vector(31 downto 0);
    pages_title_cmd_lastidx   : out std_logic_vector(31 downto 0);
    pages_title_cmd_ctrl      : out std_logic_vector(2*BUS_ADDR_WIDTH-1 downto 0);
    pages_title_cmd_tag       : out std_logic_vector(0 downto 0);

    -- Unlock stream.
    pages_title_unl_valid     : in  std_logic;
    pages_title_unl_ready     : out std_logic;
    pages_title_unl_tag       : in  std_logic_vector(0 downto 0);

    ---------------------------------------------------------------------------
    -- Compressed article text input interface
    ---------------------------------------------------------------------------
    -- Length stream. last flag relates to command. count is unused.
    pages_text_valid          : in  std_logic;
    pages_text_ready          : out std_logic;
    pages_text_dvalid         : in  std_logic;
    pages_text_last           : in  std_logic;
    pages_text_length         : in  std_logic_vector(31 downto 0);
    pages_text_count          : in  std_logic_vector(0 downto 0);

    -- Snappy data bytestream. last flag relates to the end of the compressed
    -- article text. count is used to signal how many bytes are valid. The
    -- stream is assumed to be normalized.
    pages_text_bytes_valid    : in  std_logic;
    pages_text_bytes_ready    : out std_logic;
    pages_text_bytes_dvalid   : in  std_logic;
    pages_text_bytes_last     : in  std_logic;
    pages_text_bytes_data     : in  std_logic_vector(63 downto 0);
    pages_text_bytes_count    : in  std_logic_vector(3 downto 0);

    -- Command stream.
    pages_text_cmd_valid      : out std_logic;
    pages_text_cmd_ready      : in  std_logic;
    pages_text_cmd_firstIdx   : out std_logic_vector(31 downto 0);
    pages_text_cmd_lastidx    : out std_logic_vector(31 downto 0);
    pages_text_cmd_ctrl       : out std_logic_vector(2*BUS_ADDR_WIDTH-1 downto 0);
    pages_text_cmd_tag        : out std_logic_vector(0 downto 0);

    -- Unlock stream.
    pages_text_unl_valid      : in  std_logic;
    pages_text_unl_ready      : out std_logic;
    pages_text_unl_tag        : in  std_logic_vector(0 downto 0);

    ---------------------------------------------------------------------------
    -- Match result output interface for title column
    ---------------------------------------------------------------------------
    -- Length stream. last flag relates to command. count is unused.
    result_title_valid        : out std_logic;
    result_title_ready        : in  std_logic;
    result_title_dvalid       : out std_logic;
    result_title_last         : out std_logic;
    result_title_length       : out std_logic_vector(31 downto 0);
    result_title_count        : out std_logic_vector(0 downto 0);

    -- Character stream. last flag relates to the end of the title string.
    -- count is unused.
    result_title_chars_valid  : out std_logic;
    result_title_chars_ready  : in  std_logic;
    result_title_chars_dvalid : out std_logic;
    result_title_chars_last   : out std_logic;
    result_title_chars_data   : out std_logic_vector(7 downto 0);
    result_title_chars_count  : out std_logic_vector(0 downto 0);

    -- Command stream.
    result_title_cmd_valid    : out std_logic;
    result_title_cmd_ready    : in  std_logic;
    result_title_cmd_firstIdx : out std_logic_vector(31 downto 0);
    result_title_cmd_lastidx  : out std_logic_vector(31 downto 0);
    result_title_cmd_ctrl     : out std_logic_vector(2*BUS_ADDR_WIDTH-1 downto 0);
    result_title_cmd_tag      : out std_logic_vector(0 downto 0);

    -- Unlock stream.
    result_title_unl_valid    : in  std_logic;
    result_title_unl_ready    : out std_logic;
    result_title_unl_tag      : in  std_logic_vector(0 downto 0);

    ---------------------------------------------------------------------------
    -- Match result output interface for match count column
    ---------------------------------------------------------------------------
    -- Data stream.
    result_count_valid        : out std_logic;
    result_count_ready        : in  std_logic;
    result_count_dvalid       : out std_logic;
    result_count_last         : out std_logic;
    result_count              : out std_logic_vector(31 downto 0);

    -- Command stream.
    result_count_cmd_valid    : out std_logic;
    result_count_cmd_ready    : in  std_logic;
    result_count_cmd_firstIdx : out std_logic_vector(31 downto 0);
    result_count_cmd_lastidx  : out std_logic_vector(31 downto 0);
    result_count_cmd_ctrl     : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    result_count_cmd_tag      : out std_logic_vector(0 downto 0);

    -- Unlock stream.
    result_count_unl_valid    : in  std_logic;
    result_count_unl_ready    : out std_logic;
    result_count_unl_tag      : in  std_logic_vector(0 downto 0);

    ---------------------------------------------------------------------------
    -- Statistic data output interface
    ---------------------------------------------------------------------------
    -- Data stream.
    stats_stats_valid         : out std_logic;
    stats_stats_ready         : in  std_logic;
    stats_stats_dvalid        : out std_logic;
    stats_stats_last          : out std_logic;
    stats_stats               : out std_logic_vector(31 downto 0);

    -- Command stream.
    stats_stats_cmd_valid     : out std_logic;
    stats_stats_cmd_ready     : in  std_logic;
    stats_stats_cmd_firstIdx  : out std_logic_vector(31 downto 0);
    stats_stats_cmd_lastidx   : out std_logic_vector(31 downto 0);
    stats_stats_cmd_ctrl      : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    stats_stats_cmd_tag       : out std_logic_vector(0 downto 0);

    -- Unlock stream.
    stats_stats_unl_valid     : in  std_logic;
    stats_stats_unl_ready     : out std_logic;
    stats_stats_unl_tag       : in  std_logic_vector(0 downto 0);

    ---------------------------------------------------------------------------
    -- Memory bus status
    ---------------------------------------------------------------------------
    -- Whether a write transaction is currently in progress. Blocks the
    -- signalling of done.
    write_busy                : in  std_logic

  );
end entity;

architecture Implementation of word_match is

  -- High-level MMIO register interface provided by vhdMMIO.
  signal mmio_cmd               : mmio_g_cmd_o_type;
  signal mmio_stat              : mmio_g_stat_i_type;
  signal mmio_result            : mmio_g_result_i_type;
  signal mmio_cfg               : mmio_g_cfg_o_type;

  -- Decompressed article text stream.
  signal pages_text_chars_valid : std_logic;
  signal pages_text_chars_ready : std_logic;
  signal pages_text_chars_dvalid: std_logic;
  signal pages_text_chars_last  : std_logic;
  signal pages_text_chars_data  : std_logic_vector(63 downto 0);
  signal pages_text_chars_count : std_logic_vector(3 downto 0);

  -- Stream of pattern match counts for each article.
  signal match_count_valid      : std_logic;
  signal match_count_ready      : std_logic;
  signal match_count_amount     : std_logic_vector(15 downto 0);

  -- Command signal to the filter unit to indicate how many result records
  -- are expected.
  signal filter_result_valid    : std_logic;
  signal filter_result_count    : std_logic_vector(15 downto 0);

begin

  -- Instantiate the VHDmmio register file.
  mmio_inst: mmio
    port map (
      clk                       => kcd_clk,
      reset                     => kcd_reset,
      g_cmd_o                   => mmio_cmd,
      g_stat_i                  => mmio_stat,
      g_result_i                => mmio_result,
      g_cfg_o                   => mmio_cfg,
      mmio_awvalid              => mmio_awvalid,
      mmio_awready              => mmio_awready,
      mmio_awaddr               => mmio_awaddr,
      mmio_wvalid               => mmio_wvalid,
      mmio_wready               => mmio_wready,
      mmio_wdata                => mmio_wdata,
      mmio_wstrb                => mmio_wstrb,
      mmio_bvalid               => mmio_bvalid,
      mmio_bready               => mmio_bready,
      mmio_bresp                => mmio_bresp,
      mmio_arvalid              => mmio_arvalid,
      mmio_arready              => mmio_arready,
      mmio_araddr               => mmio_araddr,
      mmio_rvalid               => mmio_rvalid,
      mmio_rready               => mmio_rready,
      mmio_rdata                => mmio_rdata,
      mmio_rresp                => mmio_rresp
    );

  -- Instantiate the command generator.
  cmd_gen_inst: entity work.word_match_cmd_gen
    generic map (
      BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH
    )
    port map (
      clk                       => kcd_clk,
      reset                     => kcd_reset,
      mmio_cmd                  => mmio_cmd,
      mmio_stat                 => mmio_stat,
      filter_result_valid       => filter_result_valid,
      filter_result_count       => filter_result_count,
      pages_title_cmd_valid     => pages_title_cmd_valid,
      pages_title_cmd_ready     => pages_title_cmd_ready,
      pages_title_cmd_firstIdx  => pages_title_cmd_firstIdx,
      pages_title_cmd_lastidx   => pages_title_cmd_lastidx,
      pages_title_cmd_ctrl      => pages_title_cmd_ctrl,
      pages_title_cmd_tag       => pages_title_cmd_tag,
      pages_title_unl_valid     => pages_title_unl_valid,
      pages_title_unl_ready     => pages_title_unl_ready,
      pages_title_unl_tag       => pages_title_unl_tag,
      pages_text_cmd_valid      => pages_text_cmd_valid,
      pages_text_cmd_ready      => pages_text_cmd_ready,
      pages_text_cmd_firstIdx   => pages_text_cmd_firstIdx,
      pages_text_cmd_lastidx    => pages_text_cmd_lastidx,
      pages_text_cmd_ctrl       => pages_text_cmd_ctrl,
      pages_text_cmd_tag        => pages_text_cmd_tag,
      pages_text_unl_valid      => pages_text_unl_valid,
      pages_text_unl_ready      => pages_text_unl_ready,
      pages_text_unl_tag        => pages_text_unl_tag,
      result_title_cmd_valid    => result_title_cmd_valid,
      result_title_cmd_ready    => result_title_cmd_ready,
      result_title_cmd_firstIdx => result_title_cmd_firstIdx,
      result_title_cmd_lastidx  => result_title_cmd_lastidx,
      result_title_cmd_ctrl     => result_title_cmd_ctrl,
      result_title_cmd_tag      => result_title_cmd_tag,
      result_title_unl_valid    => result_title_unl_valid,
      result_title_unl_ready    => result_title_unl_ready,
      result_title_unl_tag      => result_title_unl_tag,
      result_count_cmd_valid    => result_count_cmd_valid,
      result_count_cmd_ready    => result_count_cmd_ready,
      result_count_cmd_firstIdx => result_count_cmd_firstIdx,
      result_count_cmd_lastidx  => result_count_cmd_lastidx,
      result_count_cmd_ctrl     => result_count_cmd_ctrl,
      result_count_cmd_tag      => result_count_cmd_tag,
      result_count_unl_valid    => result_count_unl_valid,
      result_count_unl_ready    => result_count_unl_ready,
      result_count_unl_tag      => result_count_unl_tag,
      stats_stats_cmd_valid     => stats_stats_cmd_valid,
      stats_stats_cmd_ready     => stats_stats_cmd_ready,
      stats_stats_cmd_firstIdx  => stats_stats_cmd_firstIdx,
      stats_stats_cmd_lastidx   => stats_stats_cmd_lastidx,
      stats_stats_cmd_ctrl      => stats_stats_cmd_ctrl,
      stats_stats_cmd_tag       => stats_stats_cmd_tag,
      stats_stats_unl_valid     => stats_stats_unl_valid,
      stats_stats_unl_ready     => stats_stats_unl_ready,
      stats_stats_unl_tag       => stats_stats_unl_tag,
      write_busy                => write_busy
    );

  -- Void the article text length stream; we don't need it.
  pages_text_ready <= '1';

  -- Decompress the article text.
  vhsnunzip_inst: vhsnunzip_unbuffered
    generic map (
      RAM_STYLE                 => "URAM"
    )
    port map (
      clk                       => kcd_clk,
      reset                     => kcd_reset,
      co_valid                  => pages_text_bytes_valid,
      co_ready                  => pages_text_bytes_ready,
      co_data                   => pages_text_bytes_data,
      co_cnt                    => pages_text_bytes_count(2 downto 0),
      co_last                   => pages_text_bytes_last,
      de_valid                  => pages_text_chars_valid,
      de_ready                  => pages_text_chars_ready,
      de_dvalid                 => pages_text_chars_dvalid,
      de_data                   => pages_text_chars_data,
      de_cnt                    => pages_text_chars_count,
      de_last                   => pages_text_chars_last
    );

  -- Match decompressed article text against the search pattern.
  matcher_inst: entity work.word_match_matcher
    port map (
      clk                       => kcd_clk,
      reset                     => kcd_reset,
      mmio_cfg                  => mmio_cfg,
      pages_text_chars_valid    => pages_text_chars_valid,
      pages_text_chars_ready    => pages_text_chars_ready,
      pages_text_chars_dvalid   => pages_text_chars_dvalid,
      pages_text_chars_last     => pages_text_chars_last,
      pages_text_chars_data     => pages_text_chars_data,
      pages_text_chars_count    => pages_text_chars_count,
      match_count_valid         => match_count_valid,
      match_count_ready         => match_count_ready,
      match_count_amount        => match_count_amount
    );

  -- Instantiate the filter and statistics-gathering engine.
  filter_inst: entity work.word_match_filter
    port map (
      clk                       => kcd_clk,
      reset                     => kcd_reset,
      mmio_start                => mmio_cmd.s_start,
      mmio_cfg                  => mmio_cfg,
      mmio_result               => mmio_result,
      filter_result_valid       => filter_result_valid,
      filter_result_count       => filter_result_count,
      pages_title_valid         => pages_title_valid,
      pages_title_ready         => pages_title_ready,
      pages_title_dvalid        => pages_title_dvalid,
      pages_title_last          => pages_title_last,
      pages_title_length        => pages_title_length,
      pages_title_count         => pages_title_count,
      pages_title_chars_valid   => pages_title_chars_valid,
      pages_title_chars_ready   => pages_title_chars_ready,
      pages_title_chars_dvalid  => pages_title_chars_dvalid,
      pages_title_chars_last    => pages_title_chars_last,
      pages_title_chars_data    => pages_title_chars_data,
      pages_title_chars_count   => pages_title_chars_count,
      match_count_valid         => match_count_valid,
      match_count_ready         => match_count_ready,
      match_count_amount        => match_count_amount,
      result_title_valid        => result_title_valid,
      result_title_ready        => result_title_ready,
      result_title_dvalid       => result_title_dvalid,
      result_title_last         => result_title_last,
      result_title_length       => result_title_length,
      result_title_count        => result_title_count,
      result_title_chars_valid  => result_title_chars_valid,
      result_title_chars_ready  => result_title_chars_ready,
      result_title_chars_dvalid => result_title_chars_dvalid,
      result_title_chars_last   => result_title_chars_last,
      result_title_chars_data   => result_title_chars_data,
      result_title_chars_count  => result_title_chars_count,
      result_count_valid        => result_count_valid,
      result_count_ready        => result_count_ready,
      result_count_dvalid       => result_count_dvalid,
      result_count_last         => result_count_last,
      result_count              => result_count,
      stats_stats_valid         => stats_stats_valid,
      stats_stats_ready         => stats_stats_ready,
      stats_stats_dvalid        => stats_stats_dvalid,
      stats_stats_last          => stats_stats_last,
      stats_stats               => stats_stats
    );

end architecture;
