library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.vhdmmio_pkg.all;
use work.WordMatch_MMIO_pkg.all;

entity WordMatch_ResultWriter is
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic;

    -- Write command input stream.
    write_cmd_valid             : in  std_logic;
    write_cmd_ready             : out std_logic;
    write_cmd_titlePass         : in  std_logic; -- pass through title from reader to writer
    write_cmd_titleDummy        : in  std_logic; -- write zero-length title
    write_cmd_titleTerm         : in  std_logic; -- terminate string writer by sending null character with last flag
    write_cmd_intEnable         : in  std_logic; -- enable integer stream (match count or statistic)
    write_cmd_intData           : in  std_logic_vector(31 downto 0); -- integer to write
    write_cmd_last              : in  std_logic; -- last signal for the title length and integer streams

    -- Page title input data streams.
    pages_title_valid           : in  std_logic;
    pages_title_ready           : out std_logic;
    pages_title_dvalid          : in  std_logic;
    pages_title_last            : in  std_logic;
    pages_title_length          : in  std_logic_vector(31 downto 0);
    pages_title_count           : in  std_logic_vector(0 downto 0);
    pages_title_chars_valid     : in  std_logic;
    pages_title_chars_ready     : out std_logic;
    pages_title_chars_dvalid    : in  std_logic;
    pages_title_chars_last      : in  std_logic;
    pages_title_chars_data      : in  std_logic_vector(7 downto 0);
    pages_title_chars_count     : in  std_logic_vector(0 downto 0);

    -- Result title output data streams.
    result_title_valid          : out std_logic;
    result_title_ready          : in  std_logic;
    result_title_dvalid         : out std_logic;
    result_title_last           : out std_logic;
    result_title_length         : out std_logic_vector(31 downto 0);
    result_title_count          : out std_logic_vector(0 downto 0);
    result_title_chars_valid    : out std_logic;
    result_title_chars_ready    : in  std_logic;
    result_title_chars_dvalid   : out std_logic;
    result_title_chars_last     : out std_logic;
    result_title_chars_data     : out std_logic_vector(7 downto 0);
    result_title_chars_count    : out std_logic_vector(0 downto 0);

    -- Result match count & stats output data stream.
    result_count_stats_valid    : out std_logic;
    result_count_stats_ready    : in  std_logic;
    result_count_stats_data     : out std_logic_vector(31 downto 0);
    result_count_stats_dvalid   : out std_logic;
    result_count_stats_last     : out std_logic

  );
end entity;

architecture Implementation of WordMatch_ResultWriter is
begin
  proc: process (clk) is

    -- Stream holding registers.
    variable wc_valid           : std_logic := '0';
    variable wc_titlePass       : std_logic;
    variable wc_titleDummy      : std_logic;
    variable wc_titleTerm       : std_logic;
    variable wc_intEnable       : std_logic;
    variable wc_intData         : std_logic_vector(31 downto 0);
    variable wc_last            : std_logic;
    variable pt_valid           : std_logic := '0';
    variable pt_length          : std_logic_vector(31 downto 0);
    variable ptc_valid          : std_logic := '0';
    variable ptc_last           : std_logic;
    variable ptc_data           : std_logic_vector(7 downto 0);
    variable rt_valid           : std_logic := '0';
    variable rt_last            : std_logic;
    variable rt_length          : std_logic_vector(31 downto 0);
    variable rtc_valid          : std_logic := '0';
    variable rtc_dvalid         : std_logic;
    variable rtc_last           : std_logic;
    variable rtc_data           : std_logic_vector(7 downto 0);
    variable rcs_valid          : std_logic := '0';
    variable rcs_data           : std_logic_vector(31 downto 0);
    variable rcs_last           : std_logic;

    -- State variables.
    variable val_xfer           : std_logic := '0';
    variable len_xfer           : std_logic := '0';
    variable len_last           : std_logic;

  begin
    if rising_edge(clk) then

      -- Handle stream handshake signals.
      if wc_valid = '0' then
        wc_valid := write_cmd_valid;
        wc_titlePass := write_cmd_titlePass;
        wc_titleDummy := write_cmd_titleDummy;
        wc_titleTerm := write_cmd_titleTerm;
        wc_intEnable := write_cmd_intEnable;
        wc_intData := write_cmd_intData;
        wc_last := write_cmd_last;
      end if;
      if pt_valid = '0' then
        pt_valid := pages_title_valid;
        pt_length := pages_title_length;
      end if;
      if ptc_valid = '0' then
        ptc_valid := pages_title_chars_valid;
        ptc_last := pages_title_chars_last;
        ptc_data := pages_title_chars_data;
      end if;
      if result_title_ready = '1' then
        rt_valid := '0';
      end if;
      if result_title_chars_ready = '1' then
        rtc_valid := '0';
      end if;
      if result_count_stats_ready = '1' then
        rcs_valid := '0';
      end if;

      -- Handle incoming commands.
      if wc_valid = '1' and len_xfer = '0' and val_xfer = '0' then
        if rt_valid = '0' and rtc_valid = '0' and rcs_valid = '0' then
          wc_valid := '0';

          -- Queue title passthrough if requested.
          val_xfer := wc_titlePass;
          len_xfer := wc_titlePass;
          len_last := wc_last;

          -- Send dummy title if requested.
          if wc_titleDummy = '1' then
            rt_valid := '1';
            rt_last := wc_last;
            rt_length := X"00000000";
          end if;

          -- Send title values buffer termination command if requested.
          if wc_titleTerm = '1' then
            rtc_valid := '1';
            rtc_dvalid := '0';
            rtc_last := '1';
            rtc_data := X"00";
          end if;

          -- Send integer data if requested.
          if wc_intEnable = '1' then
            rcs_valid := '1';
            rcs_data := wc_intData;
            rcs_last := wc_last;
          end if;

        end if;
      end if;

      -- Handle queued title character transfers.
      if val_xfer = '1' and ptc_valid = '1' and rtc_valid = '0' then
        ptc_valid := '0';
        rtc_valid := '1';
        rtc_dvalid := '1';
        rtc_last := '0';
        rtc_data := ptc_data;
        val_xfer := not ptc_last;
      end if;

      -- Handle queued length transfers.
      if len_xfer = '1' and pt_valid = '1' and rt_valid = '0' then
        pt_valid := '0';
        rt_valid := '1';
        rt_last := len_last;
        rt_length := pt_length;
        len_xfer := '0';
      end if;

      -- Handle reset.
      if reset = '1' then
        wc_valid := '0';
        pt_valid := '0';
        ptc_valid := '0';
        rt_valid := '0';
        rtc_valid := '0';
        rcs_valid := '0';
        val_xfer := '0';
        len_xfer := '0';
      end if;

      -- Assign output signals.
      write_cmd_ready <= not wc_valid;
      pages_title_ready <= not pt_valid;
      pages_title_chars_ready <= not ptc_valid;
      result_title_valid <= rt_valid;
      result_title_dvalid <= '1';
      result_title_last <= rt_last;
      result_title_length <= rt_length;
      result_title_count <= "1";
      result_title_chars_valid <= rtc_valid;
      result_title_chars_dvalid <= rtc_dvalid;
      result_title_chars_last <= rtc_last;
      result_title_chars_data <= rtc_data;
      result_title_chars_count <= "1";
      result_count_stats_valid <= rcs_valid;
      result_count_stats_data <= rcs_data;
      result_count_stats_dvalid <= '1';
      result_count_stats_last <= rcs_last;

    end if;
  end process;
end architecture;
