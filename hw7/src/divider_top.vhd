------------------------------------------------------------------------------
-- divider_top.vhd
--
-- description:
--   top level for the serial divider on the ispMACH4128ZE (LC4128ZE, 100
--   TQFP) board. port names match the course divider.lct exactly, so that
--   file does the pin locking. set THIS as the top level in ispLEVER.
--
--   board notes:
--     - pull JP2 (segment decoder) and JP1 (digit decoder) so the 16V8 and
--       29M16 let go of the segment/digit lines
--     - the 74C923 has to be out of the way (it scans the same keypad lines)
--     - keypad: cpld drives the 4 KeypadCol lines low one at a time and
--       reads the 4 KeypadRow lines (pulled up by RP2)
--     - segments go through a ULN2003 with 150 ohm pull ups, so a '0' from
--       the cpld lights a segment (SEG_ON = '0' in divider.vhd)
--     - digits go through ULN2003s, '1' turns a digit on
--
-- inputs:
--   CLK          - pin 89, 1 MHz board clock
--   nCalculate   - pin 93, calculate button, low when pressed
--   Divisor      - pin 94, slide switch
--   KeypadRow    - pins 6, 5, 4, 3, keypad sense lines
--
-- outputs:
--   KeypadCol    - pins 8, 9, 10, 11, keypad scan lines
--   segmenta..g  - pins 41, 42, 43, 44, 49, 50, 53
--   Digit(11..0) - one-hot digit enables, Digit 0-3 top display (dividend),
--                  4-7 middle (divisor), 8-11 bottom (quotient/remainder),
--                  digit 0 of each display is its leftmost digit
--
-- edits:
--   11/15/26  aadi  pinned it from the schematic with LOC attributes
--   11/20/26  aadi  renamed ports to match the course divider.lct, pins now
--                   come from that file
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity DividerTop is
    port(
        CLK        : in  std_logic;
        nCalculate : in  std_logic;
        Divisor    : in  std_logic;
        KeypadRow  : in  std_logic_vector(3 downto 0);
        KeypadCol  : out std_logic_vector(3 downto 0);
        segmenta, segmentb, segmentc, segmentd : out std_logic;
        segmente, segmentf, segmentg           : out std_logic;
        Digit      : out std_logic_vector(11 downto 0)
    );
end DividerTop;


architecture structural of DividerTop is

    signal Seg : std_logic_vector(6 downto 0);   -- a..g, Seg(6) = a

begin

    core : entity work.SerialDivider
        port map(
            clk        => CLK,
            DivisorSel => Divisor,
            nCalc      => nCalculate,
            KeyCol     => KeypadRow,    -- sensed lines (board rows)
            KeyRow     => KeypadCol,    -- driven lines (board columns)
            Segment    => Seg,
            Digit      => Digit
        );

    segmenta <= Seg(6);  segmentb <= Seg(5);  segmentc <= Seg(4);
    segmentd <= Seg(3);  segmente <= Seg(2);  segmentf <= Seg(1);
    segmentg <= Seg(0);

end structural;
