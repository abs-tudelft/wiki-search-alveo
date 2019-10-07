library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.vhsnunzip_pkg.all;
use work.vhdmmio_pkg.all;
use work.mmio_pkg.all;

entity word_match_filter is
  port (
    clk                       : in  std_logic;
    reset                     : in  std_logic;

    ---------------------------------------------------------------------------
    -- MMIO interface
    ---------------------------------------------------------------------------
    mmio_start                : in  std_logic;
    mmio_cfg                  : in  mmio_g_cfg_o_type;
    mmio_result               : out mmio_g_result_i_type;

    ---------------------------------------------------------------------------
    -- Command generator interface.
    ---------------------------------------------------------------------------
    filter_result_valid       : in  std_logic;
    filter_result_count       : in  std_logic_vector(15 downto 0);

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

    ---------------------------------------------------------------------------
    -- Stream with number of pattern matches in article text
    ---------------------------------------------------------------------------
    match_count_valid         : in  std_logic;
    match_count_ready         : out std_logic;
    match_count_amount        : in  std_logic_vector(15 downto 0);

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

    ---------------------------------------------------------------------------
    -- Match result output interface for match count column
    ---------------------------------------------------------------------------
    -- Data stream.
    result_count_valid        : out std_logic;
    result_count_ready        : in  std_logic;
    result_count_dvalid       : out std_logic;
    result_count_last         : out std_logic;
    result_count              : out std_logic_vector(31 downto 0);

    ---------------------------------------------------------------------------
    -- Statistic data output interface
    ---------------------------------------------------------------------------
    -- Data stream.
    stats_stats_valid         : out std_logic;
    stats_stats_ready         : in  std_logic;
    stats_stats_dvalid        : out std_logic;
    stats_stats_last          : out std_logic;
    stats_stats               : out std_logic_vector(31 downto 0)

  );
end entity;

architecture Implementation of word_match_filter is
begin
  proc: process (clk) is

    -- Stream slice holding registers.
    variable pt_valid   : std_logic;
    variable pt_dvalid  : std_logic;
    variable pt_last    : std_logic;
    variable pt_length  : std_logic_vector(31 downto 0);
    variable pt_count   : std_logic_vector(0 downto 0);
    variable ptc_valid  : std_logic;
    variable ptc_dvalid : std_logic;
    variable ptc_last   : std_logic;
    variable ptc_data   : std_logic_vector(7 downto 0);
    variable ptc_count  : std_logic_vector(0 downto 0);
    variable mc_valid   : std_logic;
    variable mc_amount  : std_logic_vector(15 downto 0);
    variable rt_valid   : std_logic;
    variable rt_dvalid  : std_logic;
    variable rt_last    : std_logic;
    variable rt_length  : std_logic_vector(31 downto 0);
    variable rt_count   : std_logic_vector(0 downto 0);
    variable rtc_valid  : std_logic;
    variable rtc_dvalid : std_logic;
    variable rtc_last   : std_logic;
    variable rtc_data   : std_logic_vector(7 downto 0);
    variable rtc_count  : std_logic_vector(0 downto 0);
    variable rc_valid   : std_logic;
    variable rc_dvalid  : std_logic;
    variable rc_last    : std_logic;
    variable rc_data    : std_logic_vector(31 downto 0);
    variable st_valid   : std_logic;
    variable st_dvalid  : std_logic;
    variable st_last    : std_logic;
    variable st_data    : std_logic_vector(31 downto 0);

    -- Title character stream command:
    --   0-: block input
    --   10: drop input
    --   11: pass input through
    variable title_cmd  : std_logic_vector(1 downto 0);

    -- Number of result records remaining, diminished-two.
    variable r_rem_d2   : unsigned(16 downto 0);

    -- Busy flag.
    variable busy       : std_logic;

    -- Whether we've seen and handled the last transfer yet. When set, we flush
    -- any unused result records and write the statistics.
    variable last_seen  : std_logic;

    -- The index of the statistics word that we have to send next.
    variable st_index   : unsigned(1 downto 0);

    -- Statistics counters for the current command.
    variable word_matches : unsigned(31 downto 0);
    variable page_matches : unsigned(31 downto 0);
    variable max_matches  : unsigned(15 downto 0);
    variable max_page_idx : unsigned(19 downto 0);
    variable cur_page_idx : unsigned(19 downto 0);
    variable cycle_count  : unsigned(31 downto 0);

  begin
    if rising_edge(clk) then
      mmio_result.f_num_word_matches_write_enable <= '0';
      mmio_result.f_num_page_matches_write_enable <= '0';

      -- Handle streams.
      if pt_valid = '0' then
        pt_valid  := pages_title_valid;
        pt_dvalid := pages_title_dvalid;
        pt_last   := pages_title_last;
        pt_length := pages_title_length;
        pt_count  := pages_title_count;
      end if;
      if ptc_valid = '0' then
        ptc_valid  := pages_title_chars_valid;
        ptc_dvalid := pages_title_chars_dvalid;
        ptc_last   := pages_title_chars_last;
        ptc_data   := pages_title_chars_data;
        ptc_count  := pages_title_chars_count;
      end if;
      if mc_valid = '0' then
        mc_valid  := match_count_valid;
        mc_amount := match_count_amount;
      end if;
      if result_title_ready = '1' then
        rt_valid := '0';
      end if;
      if result_title_chars_ready = '1' then
        rtc_valid := '0';
      end if;
      if result_count_ready = '1' then
        rc_valid := '0';
      end if;
      if stats_stats_ready = '1' then
        st_valid := '0';
      end if;

      if last_seen = '0' then

        -- Handle match data when all inputs are valid and all (possible) outputs
        -- are ready.
        if pt_valid = '1' and mc_valid = '1' then
          if rt_valid = '0' and rc_valid = '0' and title_cmd = "00" then

            -- Invalidate the inputs and drop the title (by default).
            pt_valid := '0';
            mc_valid := '0';
            title_cmd := "10";

            -- Check if the page has sufficient word matches to be considered a
            -- match.
            if unsigned(mc_amount) >= unsigned(mmio_cfg.f_min_matches_data) then

              -- If there are still result slots remaining, pass the title length
              -- and character streams through instead of dropping it, and write
              -- the match count to the accompanying int stream in the match
              -- record.
              if r_rem_d2(16) = '0' or r_rem_d2(0) = '1' then
                title_cmd := "11";
                rt_valid  := '1';
                rt_dvalid := '1';
                rt_last   := r_rem_d2(16);
                rt_length := pt_length;
                rt_count  := "1";
                rc_valid  := '1';
                rc_dvalid := '1';
                rc_last   := r_rem_d2(16);
                rc_data   := X"0000" & mc_amount;
                r_rem_d2  := r_rem_d2 - 1;
              end if;

              -- Update page match count regardless of the result slot count.
              page_matches := page_matches + 1;

            end if;

            -- Update the maximum number of matches per page.
            if unsigned(mc_amount) >= max_matches then
              max_matches := unsigned(mc_amount);
              max_page_idx := cur_page_idx;
            end if;

            -- Update word match count.
            word_matches := word_matches + unsigned(mc_amount);

            -- Update the current page index.
            cur_page_idx := cur_page_idx + 1;

            -- Pend the statistics write command and flushing of the result
            -- record streams if this was the last transfer.
            last_seen := pt_last;

          end if;
        end if;

      else

        -- If we've seen and handled the last transfer, pad the result streams
        -- with nulls if necessary, and write the statistics.
        if title_cmd = "00" then

          if r_rem_d2(16) = '1' and r_rem_d2(0) = '0' then

            -- Write statistics and terminate values stream.
            if rtc_valid = '0' and st_valid = '0' then

              case st_index is
                when "00" =>

                  -- Write last value for values stream.
                  rtc_valid  := '1';
                  rtc_dvalid := '0';
                  rtc_last   := '1';
                  rtc_data   := X"00";
                  rtc_count  := "0";

                  -- Write first statistics word to shared memory.
                  st_last   := '0';
                  st_data   := std_logic_vector(page_matches);

                when "01" =>

                  -- Write second statistics word to shared memory.
                  st_last   := '0';
                  st_data   := std_logic_vector(word_matches);

                when "10" =>

                  -- Write third statistics word to shared memory.
                  st_last   := '0';
                  st_data(31 downto 20) := std_logic_vector(max_matches(11 downto 0));
                  st_data(19 downto 0) := std_logic_vector(max_page_idx);

                when others =>

                  -- Write fourth statistics word to shared memory.
                  st_last   := '1';
                  st_data   := std_logic_vector(cycle_count);

                  -- Write statistics to MMIO.
                  mmio_result.f_num_word_matches_write_data <= std_logic_vector(word_matches);
                  mmio_result.f_num_word_matches_write_enable <= '1';
                  mmio_result.f_num_page_matches_write_data <= std_logic_vector(page_matches);
                  mmio_result.f_num_page_matches_write_enable <= '1';
                  mmio_result.f_max_word_matches_write_data <= std_logic_vector(max_matches);
                  mmio_result.f_max_word_matches_write_enable <= '1';
                  mmio_result.f_max_page_idx_write_data <= std_logic_vector(max_page_idx);
                  mmio_result.f_max_page_idx_write_enable <= '1';
                  mmio_result.f_cycle_count_write_data <= std_logic_vector(cycle_count);
                  mmio_result.f_cycle_count_write_enable <= '1';

                  -- Reset the relevant state for the next command.
                  busy         := '0';
                  st_index     := "00";
                  last_seen    := '0';
                  page_matches := (others => '0');
                  word_matches := (others => '0');
                  max_matches  := (others => '0');
                  max_page_idx := (others => '0');
                  cur_page_idx := (others => '0');
                  cycle_count  := (others => '0');

              end case;

              st_valid  := '1';
              st_dvalid := '1';
              st_index  := st_index + 1;

            end if;

          else

            -- Write unused result records.
            if rt_valid = '0' and rc_valid = '0' then

              -- Send padding to title length stream.
              rt_valid   := '1';
              rt_dvalid  := '1';
              rt_last    := r_rem_d2(16);
              rt_length  := X"00000000";
              rt_count   := "1";

              -- Send padding to match count stream.
              rc_valid   := '1';
              rc_dvalid  := '1';
              rc_last    := r_rem_d2(16);
              rc_data    := X"00000000";

              -- Update number of match records remaining.
              r_rem_d2   := r_rem_d2 - 1;

            end if;
          end if;
        end if;
      end if;

      -- Handle the title character stream command.
      case title_cmd is
        when "10" => -- drop input
          if ptc_valid = '1' then
            ptc_valid := '0';
            if ptc_last = '1' then
              title_cmd := "00";
            end if;
          end if;
        when "11" => -- passthrough
          if ptc_valid = '1' and rtc_valid = '0' then
            ptc_valid  := '0';
            rtc_valid  := '1';
            rtc_dvalid := ptc_dvalid;
            rtc_last   := '0';
            rtc_data   := ptc_data;
            rtc_count  := ptc_count;
            if ptc_last = '1' then
              title_cmd := "00";
            end if;
          end if;
        when others => -- idle
          null;
      end case;

      -- Initialize the result record remaining counter when the command
      -- generator is sending a new command.
      if filter_result_valid = '1' then
        r_rem_d2 := resize(unsigned(filter_result_count), 17) - 2;
      end if;

      -- Handle the cycle counter.
      if busy = '1' then
        cycle_count := cycle_count + 1;
      end if;
      if mmio_start = '1' then
        busy := '1';
      end if;

      -- Handle reset.
      if reset = '1' then
        pt_valid      := '0';
        ptc_valid     := '0';
        mc_valid      := '0';
        rt_valid      := '0';
        rtc_valid     := '0';
        rc_valid      := '0';
        st_valid      := '0';
        title_cmd     := "00";
        r_rem_d2      := (0 => '0', others => '1');
        st_index      := "00";
        busy          := '0';
        last_seen     := '0';
        word_matches  := (others => '0');
        page_matches  := (others => '0');
        max_matches   := (others => '0');
        max_page_idx  := (others => '0');
        cur_page_idx  := (others => '0');
        cycle_count   := (others => '0');
      end if;

      -- Assign output signals.
      pages_title_ready         <= not pt_valid;
      pages_title_chars_ready   <= not ptc_valid;
      match_count_ready         <= not mc_valid;
      result_title_valid        <= rt_valid;
      result_title_dvalid       <= rt_dvalid;
      result_title_last         <= rt_last;
      result_title_length       <= rt_length;
      result_title_count        <= rt_count;
      result_title_chars_valid  <= rtc_valid;
      result_title_chars_dvalid <= rtc_dvalid;
      result_title_chars_last   <= rtc_last;
      result_title_chars_data   <= rtc_data;
      result_title_chars_count  <= rtc_count;
      result_count_valid        <= rc_valid;
      result_count_dvalid       <= rc_dvalid;
      result_count_last         <= rc_last;
      result_count              <= rc_data;
      stats_stats_valid         <= st_valid;
      stats_stats_dvalid        <= st_dvalid;
      stats_stats_last          <= st_last;
      stats_stats               <= st_data;

    end if;
  end process;
end architecture;
