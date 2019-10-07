-- Copyright 2019 Delft University of Technology
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
use ieee.math_real.all;

library work;
use work.UtilMem64_pkg.all;
use work.UtilInt_pkg.all;
use work.UtilStr_pkg.all;

entity word_match_AxiSlaveMock is
  generic (
    ADDR_WIDTH                  : natural := 32;
    DATA_WIDTH                  : natural := 32;
    ID_WIDTH                    : natural := 8;

    SEED                        : positive := 1;
    AW_STALL_PROB               : real := 0.0;
    W_STALL_PROB                : real := 0.0;
    B_STALL_PROB                : real := 0.0;
    AR_STALL_PROB               : real := 0.0;
    R_STALL_PROB                : real := 0.0;

    DUMP_WRITES                 : boolean := true;
    SREC_FILE_IN                : string := "";
    SREC_FILE_OUT               : string := ""
  );
  port (

    -- Global signals.
    aclk                        : in  std_logic;
    aresetn                     : in  std_logic;

    -- Write address channel.
    awvalid                     : in  std_logic;
    awready                     : out std_logic;
    awid                        : in  std_logic_vector(ID_WIDTH-1 downto 0);
    awaddr                      : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    awlen                       : in  std_logic_vector(7 downto 0);
    awsize                      : in  std_logic_vector(2 downto 0);
    awburst                     : in  std_logic_vector(1 downto 0);

    -- Write data channel.
    wvalid                      : in  std_logic;
    wready                      : out std_logic;
    wid                         : in  std_logic_vector(ID_WIDTH-1 downto 0);
    wdata                       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    wstrb                       : in  std_logic_vector(DATA_WIDTH/8-1 downto 0);
    wlast                       : in  std_logic;

    -- Write response channel.
    bvalid                      : out std_logic;
    bready                      : in  std_logic;
    bid                         : out std_logic_vector(ID_WIDTH-1 downto 0);
    bresp                       : out std_logic_vector(1 downto 0);

    -- Read address channel.
    arvalid                     : in  std_logic;
    arready                     : out std_logic;
    arid                        : in  std_logic_vector(ID_WIDTH-1 downto 0);
    araddr                      : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    arlen                       : in  std_logic_vector(7 downto 0);
    arsize                      : in  std_logic_vector(2 downto 0);
    arburst                     : in  std_logic_vector(1 downto 0);

    -- Read data channel.
    rvalid                      : out std_logic;
    rready                      : in  std_logic;
    rid                         : out std_logic_vector(ID_WIDTH-1 downto 0);
    rdata                       : out std_logic_vector(DATA_WIDTH-1 downto 0);
    rresp                       : out std_logic_vector(1 downto 0);
    rlast                       : out std_logic;

    -- SREC read enable signal; the current state of the memory replaced with
    -- the contents of the file specified by SREC_FILE_IN when this signal is
    -- high during the rising edge of aclk. The memory is also loaded at the
    -- start of the simulation, but survives reset.
    srec_read                   : in  std_logic := '0';

    -- SREC write enable signal; the current state of the memory is written to
    -- the file specified by SREC_FILE_OUT when this signal is high during the
    -- rising edge of aclk and anything in the memory array changed since the
    -- last write.
    srec_write                  : in  std_logic := '1'

  );
end word_match_AxiSlaveMock;

architecture behavior of word_match_AxiSlaveMock is

  constant BUS_SIZE : natural := log2floor(DATA_WIDTH/8);

  type a_type is record
    valid : std_logic;
    id    : std_logic_vector(ID_WIDTH-1 downto 0);
    addr  : std_logic_vector(ADDR_WIDTH-1 downto 0);
    len   : std_logic_vector(7 downto 0);
    size  : std_logic_vector(2 downto 0);
    burst : std_logic_vector(1 downto 0);
    wrap  : natural;
  end record;

  type w_type is record
    valid : std_logic;
    id    : std_logic_vector(ID_WIDTH-1 downto 0);
    data  : std_logic_vector(DATA_WIDTH-1 downto 0);
    strb  : std_logic_vector(DATA_WIDTH/8-1 downto 0);
    last  : std_logic;
  end record;

  type b_type is record
    valid : std_logic;
    id    : std_logic_vector(ID_WIDTH-1 downto 0);
    resp  : std_logic_vector(1 downto 0);
  end record;

  type r_type is record
    valid : std_logic;
    id    : std_logic_vector(ID_WIDTH-1 downto 0);
    data  : std_logic_vector(DATA_WIDTH-1 downto 0);
    resp  : std_logic_vector(1 downto 0);
    last  : std_logic;
  end record;

  type beat_type is record
    valid : std_logic;
    addr  : std_logic_vector(63 downto 0);
    stai  : natural;
    stoi  : natural;
    last  : std_logic;
    id    : std_logic_vector(ID_WIDTH-1 downto 0);
  end record;

begin
  model: process is

    -- Indicates that this is the first loop.
    variable first  : boolean := true;

    -- Memory array state from UtilMem64_pkg.
    variable mem    : mem_state_type;

    -- Whether the memory array contains changes compared to the last time we
    -- wrote the SREC output file.
    variable dirty  : boolean := true;

    -- Holding registers.
    variable awh    : a_type;
    variable wh     : w_type;
    variable bh     : b_type;
    variable arh    : a_type;
    variable rh     : r_type;
    variable beat   : beat_type;

    -- Valid/ready signals actually sent to the master in the previous cycle.
    -- These may differ from what the valid bits in the holding registers imply
    -- if randomized riming is enabled.
    variable awh_x  : std_logic;
    variable wh_x   : std_logic;
    variable bh_x   : std_logic;
    variable arh_x  : std_logic;
    variable rh_x   : std_logic;

    -- Random generator seeds.
    variable seed1  : positive := SEED;
    variable seed2  : positive := 1;

    -- Generates a randomized handshake signal with the given probability.
    procedure random_handshake(
      hold_ready    : in    std_logic;
      stall_prob    : in    real;
      result        : inout std_logic
    ) is
      variable rnd  : real;
    begin
      if hold_ready = '0' then
        result := '0';
      elsif result = '0' then
        uniform(seed1, seed2, rnd);
        if rnd >= stall_prob then
          result := '1';
        end if;
      end if;
    end procedure;

    -- Legalizes the given transaction request.
    procedure legalize_request(
      a             : inout a_type;
      mode          : in    string
    ) is
    begin

      -- Legalize valid bit.
      a.valid := to_X01(a.valid);
      if a.valid = 'X' then
        report "undefined " & mode & " request handshake" severity error;
        a.valid := '0';
      end if;

      if a.valid = '1' then

        -- Legalize address.
        if is_x(a.addr) then
          report "undefined address in " & mode & " transaction" severity error;
          for i in a.addr'range loop
            if is_x(a.addr(i)) then
              a.addr(i) := '0';
            end if;
          end loop;
        end if;
        a.addr := to_x01(a.addr);

        -- Legalize size.
        if is_x(a.size) then
          report "undefined transaction size in " & mode & " transaction" severity error;
          for i in a.size'range loop
            if is_x(a.size(i)) then
              a.size(i) := '0';
            end if;
          end loop;
        end if;
        a.size := to_x01(a.size);
        if to_integer(unsigned(a.size)) > BUS_SIZE then
          a.size := std_logic_vector(to_unsigned(BUS_SIZE, 3));
        end if;

        -- Legalize burst type.
        if is_x(a.burst) then
          report "undefined burst mode in " & mode & " transaction" severity error;
          for i in a.burst'range loop
            if is_x(a.burst(i)) then
              a.burst(i) := '0';
            end if;
          end loop;
        end if;
        a.burst := to_x01(a.burst);
        if a.burst = "11" then
          report "illegal burst mode in " & mode & " transaction" severity error;
          a.burst := "01";
        end if;

        -- Legalize burst length.
        if is_x(a.len) then
          report "undefined burst length in " & mode & " transaction" severity error;
          for i in a.len'range loop
            if is_x(a.len(i)) then
              a.len(i) := '0';
            end if;
          end loop;
        end if;
        a.len := to_x01(a.len);
        if a.burst /= "01" and a.len(7 downto 4) /= "0000" then
          report "illegal burst length in " & mode & " transaction" severity error;
          a.len(7 downto 4) := "0000";
        end if;
        case a.burst is
          when "00" =>
            a.wrap := 0;
          when "01" =>
            a.wrap := 12;
            assert
              to_integer(unsigned(a.addr(11 downto 0)))
              + ((to_integer(unsigned(a.len)) + 1)
                * 2**to_integer(unsigned(a.size)))
              <= 4096
              report "incrementing " & mode & " burst crosses 4kiB boundary" severity error;
          when others =>
            case a.len is
              when X"01" =>
                a.wrap := to_integer(unsigned(a.size)) + 1;
                null;
              when X"03" =>
                a.wrap := to_integer(unsigned(a.size)) + 2;
                null;
              when X"07" =>
                a.wrap := to_integer(unsigned(a.size)) + 3;
                null;
              when X"0F" =>
                a.wrap := to_integer(unsigned(a.size)) + 4;
                null;
              when others =>
                report "illegal burst length in " & mode & " transaction" severity error;
                a.len := X"01";
                a.wrap := to_integer(unsigned(a.size)) + 1;
            end case;
        end case;

      end if;
    end procedure;

    -- Converts the given address channel command to the command for a beat,
    -- agnostic to read/write mode. The state is maintained in the holding
    -- register (a_type). When the last beat is processed, the address
    -- channel holding register is invalidated to make room for the next
    -- command.
    procedure process_beat(
      a             : inout a_type;
      b             : out   beat_type;
      mode          : in    string
    ) is
      variable staa : unsigned(63 downto 0);
      variable stoa : unsigned(63 downto 0);
    begin
      b.valid := a.valid;
      if a.valid = '1' then

        -- Determine start and end address.
        staa := resize(unsigned(a.addr), 64);
        stoa := staa + 2**to_integer(unsigned(a.size));

        -- The end address is always aligned to the transaction size.
        if a.size /= "000" then
          stoa(to_integer(unsigned(a.size)) - 1 downto 0) := (others => '0');
        end if;

        -- Wrap the new address accross the boundary computed in
        -- legalize_request based on the burst type.
        if a.wrap > 0 then
          a.addr(a.wrap - 1 downto 0) := std_logic_vector(resize(stoa, a.wrap));
        end if;

        -- Update the number of beats remaining.
        if a.len = X"00" then
          a.valid := '0';
          b.last := '1';
        else
          a.len := std_logic_vector(unsigned(a.len) - 1);
          b.last := '0';
        end if;

        -- Save the start address in the beat command.
        b.addr := std_logic_vector(staa);

        -- Save the start and stop lane indices in the beat command.
        b.stai := to_integer(staa(BUS_SIZE-1 downto 0));
        b.stoi := to_integer(stoa(BUS_SIZE-1 downto 0));
        if b.stoi = 0 then
          b.stoi := 2**BUS_SIZE;
        end if;

        -- Copy the transaction ID.
        b.id := a.id;

      end if;
    end procedure;

    -- Represents the given write information as a string and prints it to
    -- stdout.
    procedure dump_write(
      addr  : std_logic_vector;
      data  : std_logic_vector;
      strb  : std_logic_vector
    ) is
      variable data_v   : std_logic_vector(data'length-1 downto 0);
      variable strb_v   : std_logic_vector(strb'length-1 downto 0);
      variable data_str : string(1 to strb'length*2);
    begin
      assert strb'length = data'length / 8 severity failure;
      data_v := data;
      strb_v := strb;
      data_str := slvToHexNo0x(data_v);
      for i in 0 to strb'length - 1 loop
        if to_x01(strb_v(i)) = '0' then
          data_str((strb'length - i - 1) * 2 + 1 to (strb'length - i - 1) * 2 + 2) := "//";
        end if;
      end loop;
      println("Write > " & slvToHexNo0x(addr) & " > " & data_str);
    end procedure;

  begin

    while true loop

      -- Handle loading memory.
      if SREC_FILE_IN /= "" and (first or srec_read = '1') then
        mem_clear(mem);
        mem_loadSRec(mem, SREC_FILE_IN);
      end if;

      -- Handle the bus interface.
      if aresetn = '1' and not first then

        -- Handle the stream holding registers.
        if awh_x = '1' then
          awh_x     := not awvalid;
          awh.valid := awvalid;
          awh.id    := awid;
          awh.addr  := awaddr;
          awh.len   := awlen;
          awh.size  := awsize;
          awh.burst := awburst;
          legalize_request(awh, "write");
        end if;

        if wh_x = '1' then
          wh_x      := not wvalid;
          wh.valid  := wvalid;
          wh.id     := wid;
          wh.data   := wdata;
          wh.strb   := wstrb;
          wh.last   := wlast;
        end if;

        assert not is_x(bready)
          report "undefined write response handshake"
          severity error;

        if bh_x = '1' and to_x01(bready) = '1' then
          bh_x      := '0';
          bh.valid  := '0';
          bh.id     := (others => 'U');
          bh.resp   := (others => 'U');
        end if;

        if arh_x = '1' then
          arh_x     := not arvalid;
          arh.valid := arvalid;
          arh.id    := arid;
          arh.addr  := araddr;
          arh.len   := arlen;
          arh.size  := arsize;
          arh.burst := arburst;
          legalize_request(arh, "write");
        end if;

        assert not is_x(rready)
          report "undefined read response handshake"
          severity error;

        if rh_x = '1' and to_x01(rready) = '1' then
          rh_x     := '0';
          rh.valid := '0';
          rh.id    := (others => 'U');
          rh.data  := (others => 'U');
          rh.resp  := (others => 'U');
          rh.last  := 'U';
        end if;

        -- Handle reads.
        if arh.valid = '1' and rh.valid = '0' then

          -- Process the request to get the info for the next beat.
          process_beat(arh, beat, "read");
          assert beat.valid = '1' severity failure;

          -- Read the memory into the read data channel holding register.
          rh.valid := '1';
          rh.id    := beat.id;
          rh.data  := (others => 'U');
          rh.resp  := "00";
          rh.last  := beat.last;
          mem_read(mem, beat.addr, rh.data(8*beat.stoi-1 downto 8*beat.stai));

        end if;

        -- Handle writes.
        if awh.valid = '1' and wh.valid = '1' and bh.valid = '0' then

          -- Process the request to get the info for the next beat.
          process_beat(awh, beat, "write");
          assert beat.valid = '1' severity failure;

          -- Validate the write data channel.
          wh.valid := '0';
          assert wh.id = beat.id
            report "mismatch between write address and data channel ID" severity error;
          assert wh.last = beat.last
            report "received unexpected value for last on write data channel" severity error;
          for i in 0 to beat.stai - 1 loop
            if to_x01(wh.strb(i)) = '1' then
              report "ignoring strb flag set in inactive lane (LSB-side)" severity warning;
              exit;
            end if;
          end loop;
          for i in beat.stai to beat.stoi - 1 loop
            if is_x(wh.strb(i)) then
              report "undefined strb flag in active lane" severity error;
              wh.strb(i) := '1';
              wh.data(i*8+7 downto i*8) := "UUUUUUUU";
            elsif wh.strb(i) = '1' and is_x(wh.data(i*8+7 downto i*8)) then
              report "writing undefined data" severity warning;
            end if;
          end loop;
          for i in beat.stoi to DATA_WIDTH/8 - 1 loop
            if to_x01(wh.strb(i)) = '1' then
              report "ignoring strb flag set in inactive lane (MSB-side)" severity warning;
              exit;
            end if;
          end loop;
          assert not is_x(wh.strb(beat.stoi-1 downto beat.stai))
            report "undefined strb flag in active lane" severity error;

          -- Write the memory.
          if DUMP_WRITES then
            dump_write(beat.addr,
                       wh.data(8*beat.stoi-1 downto 8*beat.stai),
                       wh.strb(beat.stoi-1 downto beat.stai));
          end if;
          mem_write(mem, beat.addr,
                    wh.data(8*beat.stoi-1 downto 8*beat.stai),
                    wh.strb(beat.stoi-1 downto beat.stai));
          dirty := true;

          -- Assign the write response channel when we complete the last beat.
          if beat.last = '1' then
            bh.valid := '1';
            bh.id    := beat.id;
            bh.resp  := "00";
          end if;

        end if;

        -- Handle timing for randomized handshaking.
        random_handshake(not awh.valid, AW_STALL_PROB, awh_x);
        random_handshake(not wh.valid,  W_STALL_PROB,  wh_x);
        random_handshake(    bh.valid,  B_STALL_PROB,  bh_x);
        random_handshake(not arh.valid, AR_STALL_PROB, arh_x);
        random_handshake(    rh.valid,  R_STALL_PROB,  rh_x);

      else

        -- Handle reset.
        awh.valid := '0';
        wh.valid  := '0';
        bh.valid  := '0';
        bh.id     := (others => 'U');
        bh.resp   := (others => 'U');
        arh.valid := '0';
        rh.valid  := '0';
        rh.id     := (others => 'U');
        rh.data   := (others => 'U');
        rh.resp   := (others => 'U');
        rh.last   := 'U';
        awh_x     := '0';
        wh_x      := '0';
        bh_x      := '0';
        arh_x     := '0';
        rh_x      := '0';

      end if;

      -- Handle writing memory.
      if SREC_FILE_OUT /= "" and srec_write = '1' and dirty then
        mem_dumpSRec(mem, SREC_FILE_OUT);
        dirty := false;
      end if;

      -- Assign output signals.
      awready <= awh_x;
      wready  <= wh_x;
      bvalid  <= bh_x;
      arready <= arh_x;
      rvalid  <= rh_x;

      if bh_x = '1' then
        bid     <= bh.id;
        bresp   <= bh.resp;
      else
        bid     <= (others => 'U');
        bresp   <= (others => 'U');
      end if;

      if rh_x = '1' then
        rid     <= rh.id;
        rdata   <= rh.data;
        rresp   <= rh.resp;
        rlast   <= rh.last;
      else
        rid     <= (others => 'U');
        rdata   <= (others => 'U');
        rresp   <= (others => 'U');
        rlast   <= 'U';
      end if;

      -- Wait for the next event.
      first := false;
      wait until rising_edge(aclk) or falling_edge(aresetn);

    end loop;

  end process;
end behavior;
