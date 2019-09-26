library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.vhdmmio_pkg.all;
use work.mmio_pkg.all;

entity word_match_matcher is
  port (
    clk                       : in  std_logic;
    reset                     : in  std_logic;

    -- Matcher configuration from MMIO block.
    mmio_cfg                  : in  mmio_g_cfg_o_type;

    -- Incoming article text.
    pages_text_chars_valid    : in  std_logic;
    pages_text_chars_ready    : out std_logic;
    pages_text_chars_dvalid   : in  std_logic;
    pages_text_chars_last     : in  std_logic;
    pages_text_chars_data     : in  std_logic_vector(63 downto 0);
    pages_text_chars_count    : in  std_logic_vector(3 downto 0);

    -- Outgoing match stream. One transfer is produced for each article, i.e.
    -- one last-delimited packet on pages_text_chars.
    match_count_valid         : out std_logic;
    match_count_ready         : in  std_logic;
    match_count_amount        : out std_logic_vector(15 downto 0)

  );
end entity;

architecture Implementation of word_match_matcher is

  -- 1..32 refer to matches with the characters in the match word. 0 and 33
  -- are used for word boundary matching.
  type match_array is array (natural range <>) of std_logic_array(0 to 33);

  -- Generate lookup table for word boundaries.
  function word_boundary_lookup_fn return std_logic_array is
    variable retval : std_logic_array(0 to 255) := (others => '1');
  begin
    for i in 48 to 57 loop -- 0-9
      retval(i) := '0';
    end loop;
    for i in 65 to 90 loop -- A-Z
      retval(i) := '0';
    end loop;
    for i in 97 to 122 loop -- a-z
      retval(i) := '0';
    end loop;
    retval(95) := '0'; -- _
    return retval;
  end function;
  constant WORD_BOUNDARY_LOOKUP : std_logic_array(0 to 255) := word_boundary_lookup_fn;

begin
  proc: process (clk) is

    -- Input holding register.
    variable in_valid     : std_logic;
    variable in_chars     : mmio_f_search_data_data_array(0 to 7);
    variable in_count     : unsigned(3 downto 0);
    variable in_last      : std_logic;

    -- Match data between input character (major index) and character within
    -- the match word/whitespace (minor index).
    variable char_valid   : std_logic;
    variable char_last    : std_logic;
    variable char_chr_mat : match_array(0 to 7);

    -- Character match data convolved with the 8 characters belonging to a
    -- single transfer, such that
    --   conv_win_mat[mi+7-ii] := and_reduce_for_all(char_chr_mat(ii)(mi))
    -- Intuitively, conv_win_mat(i) is set when the full 34-char match window
    -- starting 7-i characters after the start of the current transfer matches
    -- whatever is currently known for the input.
    variable conv_valid   : std_logic;
    variable conv_last    : std_logic;
    variable conv_first   : std_logic;
    variable conv_win_mat : std_logic_array(0 to 40);
    variable conv_win_amt : unsigned(3 downto 0);

    -- Accumulator for the number of matches.
    variable match_amount : unsigned(15 downto 0);

    -- Temporary value for word boundary check.
    variable word_bound   : std_logic;

    -- Output holding register.
    variable out_valid    : std_logic;
    variable out_amount   : unsigned(15 downto 0);

  begin
    if rising_edge(clk) then

      -- Handle output stream.
      if out_valid = '1' and match_count_ready = '1' then
        out_valid := '0';
      end if;

      -- Handle input stream.
      if in_valid = '0' then
        in_valid := pages_text_chars_valid;
        for i in 0 to 7 loop
          in_chars(i) := pages_text_chars_data(i*8+7 downto i*8);
        end loop;
        if pages_text_chars_dvalid = '1' then
          in_count := unsigned(pages_text_chars_count);
        else
          in_count := "0000";
        end if;
        in_last := pages_text_chars_last;
      end if;

      -- NOTE: the "if out_valid = '0' then" blocks below are pipeline stages.
      -- Depending on the order in which they appear in the process, actual
      -- stage registers will or won't be inserted.

      -- Accumulate matches and push output when we get the last transfer.
      if out_valid = '0' then
        if conv_valid = '1' then
          match_amount := match_amount + conv_win_amt;
          out_valid := conv_last;
          if conv_last = '1' then
            out_amount := match_amount;
            match_amount := (others => '0');
          end if;
          conv_valid := '0';
        end if;
      end if;

      -- Convolve the character match matrix.
      if out_valid = '0' then
        conv_valid := char_valid;
        conv_last := char_last;

        -- conv_win_mat and conv_first are state, which we should update only
        -- when the pipeline stage is actually valid.
        if conv_valid = '1' then

          -- Initialize the convolution state such that positions that match
          -- invalid data (i.e. before the start of the data) against valid
          -- characters in the pattern do not match, but everything else does.
          if conv_first = '1' then
            conv_win_mat := (others => '1');
            for ci in 0 to 40 loop
              if ci > unsigned(mmio_cfg.f_search_first_data) then
                conv_win_mat(ci) := '0';
              end if;
            end loop;
          end if;

          -- Shift the convolution window along with the incoming data.
          conv_win_mat(8 to 40) := conv_win_mat(0 to 32);
          conv_win_mat(0 to 7) := X"FF";

          -- Perform the convolution for the next 8 data bytes.
          for ci in 0 to 40 loop
            for ii in 0 to 7 loop
              for mi in 0 to 33 loop
                if ci = mi + 7 - ii then
                  conv_win_mat(ci) := conv_win_mat(ci) and char_chr_mat(ii)(mi);
                end if;
              end loop;
            end loop;
          end loop;

          -- Update first flag, used to initialize the convolution at the
          -- start of each new chunk of data.
          conv_first := conv_last;

          -- Determine how many convolutions completed with a match.
          conv_win_amt := X"0";
          for ci in 33 to 40 loop
            if conv_win_mat(ci) = '1' then
              conv_win_amt := conv_win_amt + 1;
            end if;
          end loop;
          if conv_last = '1' and conv_win_mat(32) = '1' then
            conv_win_amt := conv_win_amt + 1;
          end if;

        end if;

        char_valid := '0';
      end if;

      -- Match all characters in the input against all characters in the match
      -- word and the word boundary pattern.
      if out_valid = '0' then
        char_valid := in_valid;
        char_last := in_last;
        for ii in 0 to 7 loop
          word_bound := WORD_BOUNDARY_LOOKUP(to_integer(unsigned(in_chars(ii))))
                     or not mmio_cfg.f_whole_words_data;
          char_chr_mat(ii) := (others => '1');
          for mi in 0 to 31 loop
            if mi = unsigned(mmio_cfg.f_search_first_data) then
              char_chr_mat(ii)(mi) := word_bound;
            end if;
          end loop;
          for mi in 0 to 31 loop
            if mi >= unsigned(mmio_cfg.f_search_first_data) then
              if ii >= in_count or in_chars(ii) /= mmio_cfg.f_search_data_data(mi) then
                char_chr_mat(ii)(mi+1) := '0';
              end if;
            end if;
          end loop;
          if ii < in_count then
            char_chr_mat(ii)(33) := word_bound;
          end if;
        end loop;
        in_valid := '0';
      end if;

      -- Handle reset.
      if reset = '1' then
        in_valid := '0';
        char_valid := '0';
        conv_valid := '0';
        conv_first := '1';
        match_amount := (others => '0');
        out_valid := '0';
      end if;

      -- Drive output signals.
      pages_text_chars_ready <= not in_valid;
      match_count_valid <= out_valid;
      match_count_amount <= std_logic_vector(out_amount);

    end if;
  end process;
end architecture;
