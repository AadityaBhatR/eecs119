------------------------------------------------------------------------------
-- rll.vhd
--
-- description:
--   rll(2,7) encoder as a state machine. walks the code tree one node per
--   input bit and spits out the 2 bit pair for the bit read 2 steps ago
--   (have to wait that long to know the pair). no shift regs, just states.
--   output lags input by ~5 clks (2 input bits + output reg)
--
-- inputs:
--   DataIn - serial data in, each bit held for 2 clks
--   CLK    - output bit clock
--   Reset  - active low reset
--
-- outputs:
--   RLLOut - rll encoded serial out
--
-- edits:
--   11/12/26  aadi  first version, passes the tb
--   11/14/26  aadi  recommented + added this header
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity RLLEncoder is
    port (
        DataIn : in  std_logic;     -- serial data in
        CLK    : in  std_logic;     -- output bit clock
        Reset  : in  std_logic;     -- active low reset
        RLLOut : out std_logic      -- encoded serial out
    );
end RLLEncoder;


architecture behavioral of RLLEncoder is

    type state_t is (
        Start,      -- just reset, at root, owe filler 00
        At0,        -- new word started at 0, owe 00 from last word
        At1,        -- new word started at 1, owe 00 from last word
        At00,       -- at 00, owe 00
        At01,       -- at 01 or 001 (same thing), owe 10 or 00
                    -- depending on next bit
        Leaf01,     -- hit a leaf so back at root, owe 01
        Leaf10      -- hit a leaf so back at root, owe 10
    );

    signal State    : state_t;
    signal Phase    : std_logic;    -- 0 = left bit of pair, 1 = right bit
    signal RightBit : std_logic;    -- saved right bit for 2nd clk

begin

    encoder : process (CLK, Reset)
    begin
        if Reset = '0' then         -- reset everything
            State    <= Start;
            Phase    <= '0';
            RightBit <= '0';
            RLLOut   <= '0';

        elsif rising_edge(CLK) then

            if Phase = '0' then     -- read bit, step tree, send
                                    -- left bit, save right bit
                Phase <= '1';

                case State is       -- each state is a tree spot + what we owe

                    when Start =>               -- filler 00
                        RLLOut   <= '0';
                        RightBit <= '0';
                        if DataIn = '0' then
                            State <= At0;
                        else
                            State <= At1;
                        end if;

                    when At0 =>                 -- owe 00
                        RLLOut   <= '0';
                        RightBit <= '0';
                        if DataIn = '0' then
                            State <= At00;      -- go to 00
                        else
                            State <= At01;      -- go to 01
                        end if;

                    when At1 =>                 -- owe 00
                        RLLOut   <= '0';
                        RightBit <= '0';
                        if DataIn = '0' then
                            State <= Leaf01;    -- 10, next pair 01
                        else
                            State <= Leaf10;    -- 11, next pair 10
                        end if;

                    when At00 =>                -- owe 00
                        RLLOut   <= '0';
                        RightBit <= '0';
                        if DataIn = '0' then
                            State <= Leaf01;    -- 000, next pair 01
                        else
                            State <= At01;      -- go to 001
                        end if;

                    when At01 =>                -- owe 10 or 00
                        RightBit <= '0';
                        if DataIn = '0' then
                            RLLOut <= '1';      -- 010/0010, send 10
                            State  <= Leaf01;   -- then 01
                        else
                            RLLOut <= '0';      -- 011/0011, send 00
                            State  <= Leaf10;   -- then 10
                        end if;

                    when Leaf01 =>              -- owe 01
                        RLLOut   <= '0';
                        RightBit <= '1';
                        if DataIn = '0' then
                            State <= At0;
                        else
                            State <= At1;
                        end if;

                    when Leaf10 =>              -- owe 10
                        RLLOut   <= '1';
                        RightBit <= '0';
                        if DataIn = '0' then
                            State <= At0;
                        else
                            State <= At1;
                        end if;

                end case;

            else                    -- just send the saved right bit on 2nd clock
                Phase  <= '0';
                RLLOut <= RightBit;
            end if;

        end if;
    end process; -- encoder

end behavioral;
