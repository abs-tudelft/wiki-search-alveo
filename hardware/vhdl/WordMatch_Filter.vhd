library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.vhdmmio_pkg.all;
use work.WordMatch_MMIO_pkg.all;

entity WordMatch_Filter is
  generic (
    BUS_ADDR_WIDTH              : integer := 64
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;

    -- MMIO interface.
    mmio_filt                   : in  wordmatch_mmio_g_filt_o_type;
    mmio_stat                   : out wordmatch_mmio_g_stat_i_type;
    mmio_starting               : in  std_logic;

    -- Match count input stream.
    match_count_valid           : in  std_logic;
    match_count_ready           : out std_logic;
    match_count_amount          : in  std_logic_vector(15 downto 0);
    match_count_index           : in  std_logic_vector(19 downto 0);
    match_count_last            : in  std_logic;

    -- Page title input command/unlock streams.
    pages_title_cmd_valid       : out std_logic;
    pages_title_cmd_ready       : in  std_logic;
    pages_title_cmd_firstIdx    : out std_logic_vector(31 downto 0);
    pages_title_cmd_lastidx     : out std_logic_vector(31 downto 0);
    pages_title_cmd_valuesAddr  : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    pages_title_cmd_offsetAddr  : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    pages_title_unl_valid       : in  std_logic;
    pages_title_unl_ready       : out std_logic;

    -- Write command output stream.
    write_cmd_valid             : out std_logic;
    write_cmd_ready             : in  std_logic;
    write_cmd_titlePass         : out std_logic; -- pass through title from reader to writer
    write_cmd_titleDummy        : out std_logic; -- write zero-length title
    write_cmd_titleTerm         : out std_logic; -- terminate string writer by sending null character with last flag
    write_cmd_intEnable         : out std_logic; -- enable integer stream (match count or statistic)
    write_cmd_intData           : out std_logic_vector(31 downto 0); -- integer to write
    write_cmd_last              : out std_logic -- last signal for the title length and integer streams

  );
end entity;

architecture Implementation of WordMatch_Filter is
begin
  proc: process (clk) is

    -- Stream holding registers.
    variable mc_valid           : std_logic;
    variable mc_amount          : std_logic_vector(15 downto 0);
    variable mc_index           : std_logic_vector(19 downto 0);
    variable mc_last            : std_logic;
    variable ptc_valid          : std_logic;
    variable ptc_firstIdx       : std_logic_vector(31 downto 0);
    variable ptc_lastidx        : std_logic_vector(31 downto 0);
    variable ptc_valuesAddr     : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    variable ptc_offsetAddr     : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    variable wc_valid           : std_logic;
    variable wc_titlePass       : std_logic;
    variable wc_titleDummy      : std_logic;
    variable wc_titleTerm       : std_logic;
    variable wc_intEnable       : std_logic;
    variable wc_intData         : std_logic_vector(31 downto 0);
    variable wc_last            : std_logic;

    -- Number of result records remaining, diminished-two.
    variable r_rem_d2           : unsigned(16 downto 0);

    -- Busy flag.
    variable busy               : std_logic := '0';

    -- Whether we've seen and handled the last transfer yet. When set, we flush
    -- any unused result records and write the statistics.
    variable last_seen          : std_logic;

    -- The index of the statistics word that we have to send next.
    variable st_index           : std_logic_vector(2 downto 0);

    -- Statistics counters for the current command.
    variable word_matches       : unsigned(31 downto 0);
    variable page_matches       : unsigned(31 downto 0);
    variable max_matches        : unsigned(15 downto 0);
    variable max_page_idx       : unsigned(19 downto 0);
    variable cycle_count        : unsigned(31 downto 0);

  begin
    if rising_edge(clk) then

      -- Handle stream handshakes.
      if mc_valid = '0' then
        mc_valid := match_count_valid;
        mc_amount := match_count_amount;
        mc_index := match_count_index;
        mc_last := match_count_last;
      end if;
      if pages_title_cmd_ready = '1' then
        ptc_valid := '0';
      end if;
      if write_cmd_ready = '1' then
        wc_valid := '0';
      end if;

      if busy = '0' then

        -- Wait for the start command. When we get it, initialize.
        if mmio_starting = '1' then
          busy         := '1';
          last_seen    := '0';
          st_index     := "000";
          r_rem_d2     := resize(unsigned(mmio_filt.f_result_size_data), 17) - 2;
          page_matches := (others => '0');
          word_matches := (others => '0');
          max_matches  := (others => '0');
          max_page_idx := (others => '0');
          cycle_count  := (others => '0');
        end if;

      elsif last_seen = '0' then

        -- Phase 1: handle incoming data from the matcher datapath.
        if mc_valid = '1' and ptc_valid = '0' and wc_valid = '0' then
          mc_valid := '0';

          -- Check if the page has sufficient word matches to be considered a
          -- match.
          if unsigned(mc_amount) >= unsigned(mmio_filt.f_min_matches_data) then

            -- If there are still result slots remaining, copy the title of
            -- the current article into the result buffer along with the
            -- number of matches.
            if r_rem_d2(16) = '0' or r_rem_d2(0) = '1' then

              -- Send the title read command.
              ptc_valid := '1';
              ptc_firstIdx := std_logic_vector(resize(unsigned(mc_index), 32));
              ptc_lastidx := std_logic_vector(resize(unsigned(mc_index) + 1, 32));
              ptc_valuesAddr := std_logic_vector(resize(unsigned(mmio_filt.f_title_val_addr_data), BUS_ADDR_WIDTH));
              ptc_offsetAddr := std_logic_vector(resize(unsigned(mmio_filt.f_title_offs_addr_data), BUS_ADDR_WIDTH));

              -- Send the write logic command.
              wc_valid := '1';
              wc_titlePass := '1';
              wc_titleDummy := '0';
              wc_titleTerm := '0';
              wc_intEnable := '1';
              wc_intData := std_logic_vector(resize(unsigned(mc_amount), 32));
              wc_last := r_rem_d2(16);

              -- Update result slot remaining counter.
              r_rem_d2 := r_rem_d2 - 1;

            end if;

            -- Update page match count regardless of the result slot count.
            page_matches := page_matches + 1;

          end if;

          -- Update the maximum number of matches per page.
          if unsigned(mc_amount) >= max_matches then
            max_matches := unsigned(mc_amount);
            max_page_idx := unsigned(mc_index);
          end if;

          -- Update word match count.
          word_matches := word_matches + unsigned(mc_amount);

          -- Pend the statistics write command and flushing of the result
          -- record streams if this was the last transfer.
          last_seen := mc_last;

        end if;

      elsif r_rem_d2(16) = '0' or r_rem_d2(0) = '1' then

        -- Phase 2: write dummy values for unused result records.
        if wc_valid = '0' then

          -- Send the write logic command.
          wc_valid := '1';
          wc_titlePass := '0';
          wc_titleDummy := '1';
          wc_titleTerm := '0';
          wc_intEnable := '1';
          wc_intData := (others => '0');
          wc_last := r_rem_d2(16);

          -- Update result slot remaining counter.
          r_rem_d2 := r_rem_d2 - 1;

        end if;

      else

        -- Phase 3: terminate the title values stream and write statistics.
        if wc_valid = '0' then

          wc_valid := '1';
          wc_titlePass := '0';
          wc_titleDummy := '0';
          wc_titleTerm := '0';
          wc_intEnable := '1';
          wc_last := '0';

          case st_index is
            when "000" =>

              -- Write last value for values stream.
              wc_titleTerm := '1';

              -- Write total number of page matches.
              wc_intData := std_logic_vector(page_matches);

              -- Next state.
              st_index := "001";

            when "001" =>

              -- Write total number of word matches.
              wc_intData := std_logic_vector(word_matches);

              -- Next state.
              st_index := "010";

            when "010" =>

              -- Write max number of word matches per page.
              wc_intData := std_logic_vector(resize(max_matches, 32));

              -- Next state.
              st_index := "011";

            when "011" =>

              -- Write index of the page with the most matches.
              wc_intData := std_logic_vector(resize(max_page_idx, 32));

              -- Next state.
              st_index := "100";

            when others =>

              -- Write the cycle count.
              wc_intData := std_logic_vector(cycle_count);
              wc_last := '1';

              -- Next state.
              busy := '0';

          end case;
        end if;

      end if;

      -- Update the cycle counter.
      if busy = '1' then
        cycle_count := cycle_count + 1;
      end if;

      -- Handle reset.
      if reset = '1' then
        mc_valid := '0';
        ptc_valid := '0';
        wc_valid := '0';
        busy := '0';
      end if;

      -- Assign output signals.
      match_count_ready <= not mc_valid;
      pages_title_cmd_valid <= ptc_valid;
      pages_title_cmd_firstIdx <= ptc_firstIdx;
      pages_title_cmd_lastidx <= ptc_lastidx;
      pages_title_cmd_valuesAddr <= ptc_valuesAddr;
      pages_title_cmd_offsetAddr <= ptc_offsetAddr;
      write_cmd_valid <= wc_valid;
      write_cmd_titlePass <= wc_titlePass;
      write_cmd_titleDummy <= wc_titleDummy;
      write_cmd_titleTerm <= wc_titleTerm;
      write_cmd_intEnable <= wc_intEnable;
      write_cmd_intData <= wc_intData;
      write_cmd_last <= wc_last;

      mmio_stat.f_num_word_matches_write_data <= std_logic_vector(word_matches);
      mmio_stat.f_num_page_matches_write_data <= std_logic_vector(page_matches);
      mmio_stat.f_max_word_matches_write_data <= std_logic_vector(max_matches);
      mmio_stat.f_max_page_idx_write_data <= std_logic_vector(max_page_idx);
      mmio_stat.f_cycle_count_write_data <= std_logic_vector(cycle_count);

    end if;
  end process;

  pages_title_unl_ready <= '1';

end architecture;
