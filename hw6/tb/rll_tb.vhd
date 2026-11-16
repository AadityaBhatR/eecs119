----------------------------------------------------------------------------
--
--  Test Bench for RLLEncoder
--
--  This is a test bench for the RLLEncoder entity.  The test bench thoroughly
--  tests the entity by exercising it and checking the outputs through the use
--  of arrays of test inputs (TestInput) and expected results (TestOutput).
--  The test bench entity is called rllencoder8_tb.  It does not include the
--  code to specify a specific architecture of the RLLEncoder entity.
--
--  Revision History:
--      4/11/00  Automated/Active-VHDL    Initial revision.
--      4/11/00  Glen George              Modified to add documentation and
--                                           more extensive testing.
--      4/12/00  Glen George              Added more complete testing.
--      4/16/02  Glen George              Updated comments.
--      4/18/04  Glen George              Updated comments and formatting.
--     11/21/05  Glen George              Updated comments and formatting.
--
----------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity rllencoder_tb is
end rllencoder_tb;

architecture TB_ARCHITECTURE of rllencoder_tb is
    -- Component declaration of the tested unit
    component RLLEncoder
        port(
            DataIn  :  in  std_logic;
            Reset   :  in  std_logic;
            CLK     :  in  std_logic;
            RLLOut  :  out std_logic
        );
    end component;

    -- Stimulus signals - signals mapped to the input and inout ports of tested entity
    signal  DataIn      :  std_logic;
    signal  Reset       :  std_logic;
    signal  CLK         :  std_logic;

    -- Observed signals - signals mapped to the output ports of tested entity
    signal  RLLOut      :  std_logic;

    --Signal used to stop clock signal generators
    signal  END_SIM     :  BOOLEAN := FALSE;

    -- test values
    signal  TestInput   :  std_logic_vector(0 to 540);
    signal  TestOutput  :  std_logic_vector(0 to 1088);


begin

    -- Unit Under Test port map
    UUT : RLLEncoder
        port map(
            DataIn => DataIn,
            Reset => Reset,
            CLK => CLK,
            RLLOut => RLLOut
        );


    -- initialize the test input and expected output
    TestInput  <= "101100001001100100011000110011" &
                  "0000000010000100011000010011100101010110" &
                  "0001101111010011011100100010100001010110" &
                  "1001111110110010010010110111111001001101" &
                  "0100110011000000011000110010100011010010" &
                  "1111111010001011000111010110010110011110" &
                  "0011111011101000001101011011011101100000" &
                  "1011010111110101010100000010100101011110" &
                  "0101110111000000111001110100100111101011" &
                  "1010100010010000110011100001011110110110" &
                  "0110100001110111100001111111110000011110" &
                  "1111100010111001100100000100101001110110" &
                  "1000111100111110011011000101010010001110" &
                  "0011011010101110001001100010001";
    TestOutput <= "-----01001000000100100100001000001001000000100000" &
                  "0100100000001000" &
                  "00010000010000100100000100010000001000000100" &
                  "1001000010000100100100010001001000000100" &
                  "00100000100010001001000010000010000100100100" &
                  "001001000100000100010001001000100100001000" &
                  "10001000001000001001001001001001001000001000" &
                  "1000100000100100001000100100010000100000001000" &
                  "0001000001000010000001001000001001000100" &
                  "0000100010010010010010001000100001000100" &
                  "001001001000000100100001000100100000100100" &
                  "100000001000100000010010001000010010000100" &
                  "010000010000100010010010000010000010000100" &
                  "1000000100001001001000100100100010000100" &
                  "0100010001000100000100001001000100100100" &
                  "010010001000001001001000010010000100000100" &
                  "000010000100001000010001001001000010001000" &
                  "100100100001000100010000100100100100000100" &
                  "1000000010000100000100010010001000001000" &
                  "001000000010001001000001001000010010001000" &
                  "0001000010001000100010000100000100001000" &
                  "1000001000100001000010010010000100001000" &
                  "0010010000010010010010010001000010000100" &
                  "10001001000000100010000000100010000100001000" &
                  "001000000100010001000100100100000010000100" &
                  "0000100000100010010001001000010000100100" &
                  "001000000100010000100100";


    -- now generate the stimulus and test the design
    process

        -- some useful variables
        variable  i  :  integer;        -- general loop index

    begin  -- of stimulus process

        -- initially input is X and encoder is reset (active low)
        Reset  <= '0';
        DataIn <= 'X';

        -- run for a few clocks
        wait for 100 ns;

        -- now remove reset and start applying stimulus
        -- note that inputs change on the inactive clock edge
        --    and the output is checked just after that
        Reset <= '1';

        for  i  in  TestOutput'Range  loop

            -- get the new input value (but don't go past end of vector)
            if  ((i / 2) <= TestInput'High)  then
                -- not past end of vector
                -- remember there are two output bits per input bit
                DataIn <= TestInput(i / 2);
            else
                -- just input zeros to pad at end to get last few bits
                DataIn <= '0';
            end if;

            -- let the inputs propagate
            wait for 5 ns;

            -- check the output (from old input value)
            assert (std_match(RLLOut, TestOutput(i)))
                report  "RLL Output Test Failure"
                severity  ERROR;

            -- now wait for the clock
            wait for 15 ns;

        end loop;

        END_SIM <= TRUE;        -- end of stimulus events
        wait;                   -- wait for simulation to end

    end process; -- end of stimulus process


    CLOCK_CLK : process

    begin

        -- this process generates a 20 ns period, 50% duty cycle clock

        -- only generate clock if still simulating

        if END_SIM = FALSE then
            CLK <= '0';
            wait for 10 ns;
        else
            wait;
        end if;

        if END_SIM = FALSE then
            CLK <= '1';
            wait for 10 ns;
        else
            wait;
        end if;

    end process;


end TB_ARCHITECTURE;