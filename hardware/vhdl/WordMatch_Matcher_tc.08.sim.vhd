-- Copyright 2018 Delft University of Technology
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.TestCase_pkg.all;
use work.Stream_pkg.all;
use work.ClockGen_pkg.all;
use work.StreamSource_pkg.all;
use work.StreamSink_pkg.all;
use work.vhdmmio_pkg.all;
use work.WordMatch_MMIO_pkg.all;

entity WordMatch_Matcher_tc is
end WordMatch_Matcher_tc;

architecture test_case of WordMatch_Matcher_tc is

  signal clk        : std_logic;
  signal reset      : std_logic;

  signal mmio_cfg   : wordmatch_mmio_g_cfg_o_type;

  signal in_valid   : std_logic;
  signal in_ready   : std_logic;
  signal in_dvalid  : std_logic;
  signal in_last    : std_logic;
  signal in_data    : std_logic_vector(63 downto 0);
  signal in_count   : std_logic_vector(3 downto 0);

  signal out_valid  : std_logic;
  signal out_ready  : std_logic;
  signal out_amount : std_logic_vector(15 downto 0);

begin

  clkgen: ClockGen_mdl
    port map (
      clk                       => clk,
      reset                     => reset
    );

  in_source: StreamSource_mdl
    generic map (
      NAME                      => "a",
      ELEMENT_WIDTH             => 8,
      COUNT_MAX                 => 8,
      COUNT_WIDTH               => 4
    )
    port map (
      clk                       => clk,
      reset                     => reset,
      valid                     => in_valid,
      ready                     => in_ready,
      dvalid                    => in_dvalid,
      last                      => in_last,
      data                      => in_data,
      count                     => in_count
    );

  uut: entity work.WordMatch_Matcher
    port map (
      clk                       => clk,
      reset                     => reset,
      mmio_cfg                  => mmio_cfg,
      pages_text_chars_valid    => in_valid,
      pages_text_chars_ready    => in_ready,
      pages_text_chars_dvalid   => in_dvalid,
      pages_text_chars_last     => in_last,
      pages_text_chars_data     => in_data,
      pages_text_chars_count    => in_count,
      match_count_valid         => out_valid,
      match_count_ready         => out_ready,
      match_count_amount        => out_amount
    );

  out_sink: StreamSink_mdl
    generic map (
      NAME                      => "b",
      ELEMENT_WIDTH             => 16
    )
    port map (
      clk                       => clk,
      reset                     => reset,
      valid                     => out_valid,
      ready                     => out_ready,
      data                      => out_amount
    );

  random_tc: process is
    variable a        : streamsource_type;
    variable b        : streamsink_type;

    procedure configure(pattern: string; whole_words: boolean) is
      variable j : natural;
    begin
      mmio_cfg.f_search_data_data <= (others => X"00");
      j := 32;
      for i in pattern'high downto pattern'low loop
        j := j - 1;
        mmio_cfg.f_search_data_data(j) <= std_logic_vector(to_unsigned(character'pos(pattern(i)), 8));
      end loop;
      mmio_cfg.f_search_first_data <= std_logic_vector(to_unsigned(j, 5));
      if whole_words then
        mmio_cfg.f_whole_words_data <= '1';
      else
        mmio_cfg.f_whole_words_data <= '0';
      end if;
      mmio_cfg.f_min_matches_data <= (others => '0');
    end procedure;
  begin
    tc_open("WordMatch_Matcher", "tests some corner cases for the word matcher.");
    a.initialize("a");
    b.initialize("b");

    configure("test", true);
    a.push_str("test test one two three four five six seven eight nine ten");
    a.transmit;
    a.push_str("hello test there test test");
    a.transmit;
    a.push_str("hello test there testtest");
    a.transmit;
    b.unblock;

    tc_wait_for(2 us);

    tc_check(b.cq_get_d_nat, 2, "count");
    b.cq_next;
    tc_check(b.cq_get_d_nat, 3, "count");
    b.cq_next;
    tc_check(b.cq_get_d_nat, 1, "count");
    b.cq_next;
    tc_check(b.cq_ready, false);

    configure("test", false);
    a.push_str("test test one two three four five six seven eight nine ten");
    a.transmit;
    a.push_str("hello test there test test");
    a.transmit;
    a.push_str("hello test there testest");
    a.transmit;
    b.unblock;

    tc_wait_for(2 us);

    tc_check(b.cq_get_d_nat, 2, "count");
    b.cq_next;
    tc_check(b.cq_get_d_nat, 3, "count");
    b.cq_next;
    tc_check(b.cq_get_d_nat, 3, "count");
    b.cq_next;
    tc_check(b.cq_ready, false);

    configure("here", false);
    a.push_str("And another line is herehereherehereherehere");
    a.transmit;
    b.unblock;

    tc_wait_for(2 us);

    tc_check(b.cq_get_d_nat, 6, "count");
    b.cq_next;
    tc_check(b.cq_ready, false);

    tc_pass;
    wait;
  end process;

end test_case;

