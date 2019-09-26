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

    -- Command signal to the filter unit to indicate how many result records
    -- are expected.
    filter_result_valid       : out std_logic;
    filter_result_count       : out std_logic_vector(15 downto 0);

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
  proc: process (clk) is

    -- State variables.
    variable busy_r             : std_logic;
    variable pages_title_wait   : std_logic;
    variable pages_text_wait    : std_logic;
    variable result_title_wait  : std_logic;
    variable result_count_wait  : std_logic;
    variable stats_wait         : std_logic;

    -- Temporary variables.
    variable busy               : std_logic;

  begin
    if rising_edge(clk) then
      filter_result_valid <= '0';
      filter_result_count <= mmio_cmd.f_result_size_data(15 downto 0);

      -- Handle article title command & unlock stream.
      if pages_title_cmd_ready = '1' then
        pages_title_cmd_valid <= '0';
      end if;
      if pages_title_unl_valid = '1' then
        pages_title_wait := '0';
      end if;

      -- Handle article text command & unlock stream.
      if pages_text_cmd_ready = '1' then
        pages_text_cmd_valid <= '0';
      end if;
      if pages_text_unl_valid = '1' then
        pages_text_wait := '0';
      end if;

      -- Handle match result output command & unlock stream for title column.
      if result_title_cmd_ready = '1' then
        result_title_cmd_valid <= '0';
      end if;
      if result_title_unl_valid = '1' then
        result_title_wait := '0';
      end if;

      -- Handle match result output command & unlock stream for count column.
      if result_count_cmd_ready = '1' then
        result_count_cmd_valid <= '0';
      end if;
      if result_count_unl_valid = '1' then
        result_count_wait := '0';
      end if;

      -- Handle statistics write command & unlock stream.
      if stats_stats_cmd_ready = '1' then
        stats_stats_cmd_valid <= '0';
      end if;
      if stats_stats_unl_valid = '1' then
        stats_wait := '0';
      end if;

      -- We're busy if we're waiting for anything.
      busy := pages_title_wait
           or pages_text_wait
           or result_title_wait
           or result_count_wait
           or stats_wait;

      -- Handle the start command.
      if busy = '0' and mmio_cmd.s_start = '1' then

        -- Send article title input command.
        pages_title_cmd_valid       <= '1';
        pages_title_cmd_firstIdx    <= mmio_cmd.f_first_idx_data;
        pages_title_cmd_lastidx     <= mmio_cmd.f_last_idx_data;
        pages_title_cmd_ctrl        <= mmio_cmd.f_title_val_addr_data
                                     & mmio_cmd.f_title_offs_addr_data;
        pages_title_cmd_tag         <= "0";
        pages_title_wait            := '1';

        -- Send article text input command.
        pages_text_cmd_valid        <= '1';
        pages_text_cmd_firstIdx     <= mmio_cmd.f_first_idx_data;
        pages_text_cmd_lastidx      <= mmio_cmd.f_last_idx_data;
        pages_text_cmd_ctrl         <= mmio_cmd.f_text_val_addr_data
                                     & mmio_cmd.f_text_offs_addr_data;
        pages_text_cmd_tag          <= "0";
        pages_text_wait             := '1';

        if mmio_cmd.f_result_size_data(15 downto 0) /= X"0000" then

          -- Send match result output command for title column.
          result_title_cmd_valid    <= '1';
          result_title_cmd_firstIdx <= X"00000000";
          result_title_cmd_lastidx  <= X"0000" & mmio_cmd.f_result_size_data(15 downto 0);
          result_title_cmd_ctrl     <= mmio_cmd.f_res_title_val_addr_data
                                    & mmio_cmd.f_res_title_offs_addr_data;
          result_title_cmd_tag      <= "0";
          result_title_wait         := '1';

          -- Send match result output command for count column.
          result_count_cmd_valid    <= '1';
          result_count_cmd_firstIdx <= X"00000000";
          result_count_cmd_lastidx  <= X"0000" & mmio_cmd.f_result_size_data(15 downto 0);
          result_count_cmd_ctrl     <= mmio_cmd.f_res_match_addr_data;
          result_count_cmd_tag      <= "0";
          result_count_wait         := '1';

          -- Indicate to the filter FSM that the writers are expecting the
          -- given amount of transfers.
          filter_result_valid       <= '1';
          filter_result_count       <= mmio_cmd.f_result_size_data(15 downto 0);

        end if;

        -- Send statistics write command.
        stats_stats_cmd_valid       <= '1';
        stats_stats_cmd_firstIdx    <= X"00000000";
        stats_stats_cmd_lastidx     <= X"00000001";
        stats_stats_cmd_ctrl        <= mmio_cmd.f_res_stats_addr_data;
        stats_stats_cmd_tag         <= "0";
        stats_wait                  := '1';

      end if;

      -- Handle reset.
      if reset = '1' then
        busy := '0';
        busy_r := '1';
        pages_title_wait   := '0';
        pages_text_wait    := '0';
        result_title_wait  := '0';
        result_count_wait  := '0';
        stats_wait         := '0';
        pages_title_cmd_valid   <= '0';
        pages_text_cmd_valid    <= '0';
        result_title_cmd_valid  <= '0';
        result_count_cmd_valid  <= '0';
        stats_stats_cmd_valid   <= '0';
      end if;

      -- Assign MMIO status register values.
      mmio_stat.s_starting <= '0';
      mmio_stat.s_done <= '0';
      if busy = '1' and busy_r = '0' then
        mmio_stat.s_starting <= '1';
      end if;
      if busy = '0' and busy_r = '1' then
        mmio_stat.s_done <= '1';
      end if;

      -- Assign unlock stream ready signals.
      pages_title_unl_ready   <= pages_title_wait;
      pages_text_unl_ready    <= pages_text_wait;
      result_title_unl_ready  <= result_title_wait;
      result_count_unl_ready  <= result_count_wait;
      stats_stats_unl_ready   <= stats_wait;

      -- Save busy for the next cycle.
      busy_r := busy;

    end if;
  end process;
end architecture;
