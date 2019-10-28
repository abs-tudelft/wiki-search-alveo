library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.vhdmmio_pkg.all;
use work.WordMatch_MMIO_pkg.all;

entity WordMatch_CmdGen is
  generic (
    BUS_ADDR_WIDTH              : integer := 64;
    NUM_SUB                     : natural
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;

    -- MMIO interface.
    mmio_cmd                    : in  wordmatch_mmio_g_cmd_o_type;
    mmio_start                  : in  std_logic;
    mmio_starting               : out std_logic;
    mmio_done                   : out std_logic;

    -- Page text command/unlock streams.
    pages_text_cmd_valid        : out std_logic_vector(NUM_SUB-1 downto 0);
    pages_text_cmd_ready        : in  std_logic_vector(NUM_SUB-1 downto 0);
    pages_text_cmd_idx          : out std_logic_vector(NUM_SUB*32+31 downto 0);
    pages_text_cmd_valuesAddr   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    pages_text_cmd_offsetAddr   : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    pages_text_unl_valid        : in  std_logic_vector(NUM_SUB-1 downto 0);
    pages_text_unl_ready        : out std_logic_vector(NUM_SUB-1 downto 0);

    -- Match count input stream from decompression/match datapath.
    match_count_in_valid        : in  std_logic;
    match_count_in_ready        : out std_logic;
    match_count_in_amount       : in  std_logic_vector(15 downto 0);
    match_count_in_part         : in  std_logic_vector(1 downto 0);

    -- Index-tagged match-per-page output strean.
    match_count_out_valid       : out std_logic;
    match_count_out_ready       : in  std_logic;
    match_count_out_amount      : out std_logic_vector(15 downto 0);
    match_count_out_index       : out std_logic_vector(19 downto 0);
    match_count_out_last        : out std_logic;

    -- Result title command/unlock streams.
    result_title_cmd_valid      : out std_logic;
    result_title_cmd_ready      : in  std_logic;
    result_title_cmd_firstIdx   : out std_logic_vector(31 downto 0);
    result_title_cmd_lastIdx    : out std_logic_vector(31 downto 0);
    result_title_cmd_valuesAddr : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    result_title_cmd_offsetAddr : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    result_title_unl_valid      : in  std_logic;
    result_title_unl_ready      : out std_logic;

    -- Result match count & stats command/unlock stream.
    result_count_stats_cmd_valid    : out std_logic;
    result_count_stats_cmd_ready    : in  std_logic;
    result_count_stats_cmd_firstIdx : out std_logic_vector(31 downto 0);
    result_count_stats_cmd_lastidx  : out std_logic_vector(31 downto 0);
    result_count_stats_cmd_addr     : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    result_count_stats_unl_valid    : in  std_logic;
    result_count_stats_unl_ready    : out std_logic;

    -- AXI write channel busy signal.
    write_busy                : in  std_logic

  );
end entity;

architecture Implementation of WordMatch_CmdGen is
begin
  proc: process (clk) is

    -- Command stream state variables.
    variable ptc_valid_v  : std_logic_vector(NUM_SUB-1 downto 0) := (others => '0');
    variable ptu_wait_v   : std_logic_vector(NUM_SUB-1 downto 0) := (others => '0');
    variable rtc_valid_v  : std_logic := '0';
    variable rtu_wait_v   : std_logic := '0';
    variable rcsc_valid_v : std_logic := '0';
    variable rcsu_wait_v  : std_logic := '0';
    variable send_stat_v  : std_logic := '0';
    variable busy_r       : std_logic := '0';
    variable timer_v      : unsigned(4 downto 0);

    -- Match stream state variables.
    type index_array is array (natural range <>) of unsigned(19 downto 0);
    variable mc_indices   : index_array(0 to NUM_SUB-1) := (others => (others => '0'));
    variable mc_remain    : unsigned(20 downto 0) := (others => '0');
    variable mci_valid    : std_logic := '0';
    variable mci_amount   : std_logic_vector(15 downto 0);
    variable mci_part     : std_logic_vector(1 downto 0);
    variable mco_valid    : std_logic := '0';
    variable mco_amount   : std_logic_vector(15 downto 0);
    variable mco_index    : std_logic_vector(19 downto 0);
    variable mco_last     : std_logic;

    -- Temporary variables.
    variable busy_v       : std_logic;

  begin
    if rising_edge(clk) then

      -- Clear the strobe output signals.
      mmio_done <= '0';
      mmio_starting <= '0';

      -- Compute whether we're busy.
      busy_v := rtc_valid_v or rtu_wait_v or rcsc_valid_v or rcsu_wait_v
             or send_stat_v or write_busy;
      for sub in 0 to NUM_SUB - 1 loop
        busy_v := busy_v or ptc_valid_v(sub) or ptu_wait_v(sub);
      end loop;

      -- There might be latency between the last writer unlocking (busy_v
      -- going low) and the last write even appearing at the periphery of the
      -- kernel, let alone be accepted by the DDR controller or acknowledged,
      -- so we need a short timer to bridge this gap. Once it appears on the
      -- kernel periphery, write_busy will take over.
      if busy_v = '1' then
        timer_v := "01111";
      elsif timer_v(4) = '0' then
        timer_v := timer_v - 1;
        busy_v := '1';
      else
        busy_v := '0';
      end if;
      if busy_r = '1' and busy_v = '0' then
        mmio_done <= '1';
      end if;
      busy_r := busy_v;

      -- Handle the command & unlock stream handshakes.
      ptc_valid_v := ptc_valid_v and not pages_text_cmd_ready;
      ptu_wait_v := ptu_wait_v and not pages_text_unl_valid;
      rtc_valid_v := rtc_valid_v and not result_title_cmd_ready;
      rtu_wait_v := rtu_wait_v and not result_title_unl_valid;
      rcsc_valid_v := rcsc_valid_v and not result_count_stats_cmd_ready;
      rcsu_wait_v := rcsu_wait_v and not result_count_stats_unl_valid;

      -- Handle the match stream handshakes.
      if mci_valid = '0' then
        mci_valid  := match_count_in_valid;
        mci_amount := match_count_in_amount;
        mci_part   := match_count_in_part;
      end if;
      if match_count_out_ready = '1' then
        mco_valid := '0';
      end if;

      -- If we're not busy and the start command is given, start the kernel.
      if busy_v = '0' and mmio_start = '1' then

        -- Send compressed article text input command.
        for idx in 0 to NUM_SUB loop
          pages_text_cmd_idx(idx*32+31 downto idx*32) <= std_logic_vector(resize(unsigned(mmio_cmd.f_index_data(idx)), 32));
        end loop;
        pages_text_cmd_valuesAddr <= std_logic_vector(resize(unsigned(mmio_cmd.f_text_val_addr_data), BUS_ADDR_WIDTH));
        pages_text_cmd_offsetAddr <= std_logic_vector(resize(unsigned(mmio_cmd.f_text_offs_addr_data), BUS_ADDR_WIDTH));
        for sub in 0 to NUM_SUB - 1 loop
          if mmio_cmd.f_index_data(sub) = mmio_cmd.f_index_data(sub + 1) then
            ptc_valid_v(sub) := '0';
            ptu_wait_v(sub) := '0';
          else
            ptc_valid_v(sub) := '1';
            ptu_wait_v(sub) := '1';
          end if;
        end loop;

        -- Initialize the match stream index counters.
        for sub in 0 to NUM_SUB - 1 loop
          mc_indices(sub) := unsigned(mmio_cmd.f_index_data(sub));
        end loop;
        mc_remain := resize(unsigned(mmio_cmd.f_index_data(NUM_SUB)), 21)
                   - resize(unsigned(mmio_cmd.f_index_data(0)), 21)
                   - 2;

        -- Send title result column command.
        result_title_cmd_firstIdx   <= (others => '0');
        result_title_cmd_lastIdx    <= (others => '0');
        result_title_cmd_valuesAddr <= std_logic_vector(resize(unsigned(mmio_cmd.f_res_title_val_addr_data), BUS_ADDR_WIDTH));
        result_title_cmd_offsetAddr <= std_logic_vector(resize(unsigned(mmio_cmd.f_res_title_offs_addr_data), BUS_ADDR_WIDTH));
        rtc_valid_v := '1';
        rtu_wait_v := '1';

        -- Send match count result column command.
        result_count_stats_cmd_firstIdx <= (others => '0');
        result_count_stats_cmd_lastidx  <= (others => '0');
        result_count_stats_cmd_addr <= std_logic_vector(resize(unsigned(mmio_cmd.f_res_match_addr_data), BUS_ADDR_WIDTH));
        rcsc_valid_v := '1';
        rcsu_wait_v := '1';

        -- We re-use the match count result column, so we need to send two
        -- commands. We can't do that in one cycle, so remember that we still
        -- need to do it.
        send_stat_v := '1';

        -- Indicate that we're starting the operation.
        mmio_starting <= '1';

      end if;

      -- Send the second command for the match count/stats writer when this is
      -- pending and the writer is done.
      if rcsc_valid_v = '0' and rcsu_wait_v = '0' and send_stat_v = '1' then

        -- Send stats write command.
        result_count_stats_cmd_firstIdx <= (others => '0');
        result_count_stats_cmd_lastidx  <= (others => '0');
        result_count_stats_cmd_addr     <= std_logic_vector(resize(unsigned(mmio_cmd.f_res_stats_addr_data), BUS_ADDR_WIDTH));
        rcsc_valid_v := '1';
        rcsu_wait_v := '1';

        -- Remember that we've sent it.
        send_stat_v := '0';

      end if;

      -- Handle the match count stream.
      if mci_valid = '1' and mco_valid = '0' then
        mci_valid := '0';
        mco_valid := '1';
        mco_amount := mci_amount;
        for sub in 0 to NUM_SUB - 1 loop
          if to_integer(unsigned(mci_part)) = sub then
            mco_index := std_logic_vector(mc_indices(sub));
            mc_indices(sub) := mc_indices(sub) + 1;
          end if;
        end loop;
        mco_last := mc_remain(20);
        mc_remain := mc_remain - 1;
      end if;

      -- Handle reset.
      if reset = '1' then
        ptc_valid_v   := (others => '0');
        ptu_wait_v    := (others => '0');
        rtc_valid_v   := '0';
        rtu_wait_v    := '0';
        rcsc_valid_v  := '0';
        rcsu_wait_v   := '0';
        send_stat_v   := '0';
        busy_r        := '0';
        timer_v       := "11111";
        mci_valid     := '0';
        mco_valid     := '0';
      end if;

      -- Assign the command & unlock stream handshake output signals.
      pages_text_cmd_valid <= ptc_valid_v;
      pages_text_unl_ready <= ptu_wait_v;
      result_title_cmd_valid <= rtc_valid_v;
      result_title_unl_ready <= rtu_wait_v;
      result_count_stats_cmd_valid <= rcsc_valid_v;
      result_count_stats_unl_ready <= rcsu_wait_v;

      -- Assign the match count stream output signals.
      match_count_in_ready <= not mci_valid;
      match_count_out_valid <= mco_valid;
      match_count_out_amount <= mco_amount;
      match_count_out_index <= mco_index;
      match_count_out_last <= mco_last;

    end if;
  end process;
end architecture;
