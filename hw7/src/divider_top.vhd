------------------------------------------------------------------------------
-- divider_top.vhd
--
-- description:
--   top level for the serial divider on the ispMACH4128ZE (LC4128ZE, 100
--   TQFP) board. just breaks the SerialDivider buses out into one port per
--   pin and pins everything with LOC attributes, taken off the
--   DIVIDER8.SCH (rev 3.1) schematic. set THIS as the top level in ispLEVER.
--
--   board notes:
--     - pull JP2 (segment decoder) and JP1 (digit decoder) so the 16V8 and
--       29M16 let go of the segment/digit lines
--     - the 74C923 has to be out of the way (it scans the same keypad lines)
--     - keypad: cpld drives the 4 COLUMN lines (C1-C4) low one at a time and
--       reads the 4 ROW lines (R1-R4, pulled up by RP2)
--     - segments go through a ULN2003 with 150 ohm pull ups, so a '0' from
--       the cpld lights a segment (SEG_ON = '0' in divider.vhd)
--     - digits go through ULN2003s, '1' turns a digit on
--
-- inputs:
--   CLK        - pin 89 (I/CLK0), board oscillator
--   Calculate  - pin 93 (A4), push button, low when pressed
--   DivSwitch  - pin 94 (A6), slide switch, low when closed
--   KeyR1..4   - pins 6, 5, 4, 3 (B6, B4, B2, B0), keypad rows
--
-- outputs:
--   KeyC1..4   - pins 8, 9, 10, 11 (B8, B10, B12, B13), keypad columns
--   SegA..G    - pins 41, 42, 43, 44, 49, 50, 53 (E0 E2 E4 E6 E12 E14 F0)
--   Dig0..11   - see the LOC list, Dig0-3 top display (dividend),
--                Dig4-7 middle (divisor), Dig8-11 bottom (quotient or
--                remainder), Dig0 of each display is its leftmost digit
--
-- edits:
--   11/15/26  aadi  pinned it from the schematic
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity DividerTop is
    port(
        CLK       : in  std_logic;
        Calculate : in  std_logic;
        DivSwitch : in  std_logic;
        KeyR1, KeyR2, KeyR3, KeyR4 : in  std_logic;
        KeyC1, KeyC2, KeyC3, KeyC4 : out std_logic;
        SegA, SegB, SegC, SegD, SegE, SegF, SegG : out std_logic;
        Dig0, Dig1, Dig2,  Dig3  : out std_logic;
        Dig4, Dig5, Dig6,  Dig7  : out std_logic;
        Dig8, Dig9, Dig10, Dig11 : out std_logic
    );

    attribute LOC : string;
    -- inputs
    attribute LOC of CLK       : signal is "P89";   -- I/CLK0
    attribute LOC of Calculate : signal is "P93";   -- A4
    attribute LOC of DivSwitch : signal is "P94";   -- A6
    attribute LOC of KeyR1     : signal is "P6";    -- B6
    attribute LOC of KeyR2     : signal is "P5";    -- B4
    attribute LOC of KeyR3     : signal is "P4";    -- B2
    attribute LOC of KeyR4     : signal is "P3";    -- B0
    -- keypad column drives
    attribute LOC of KeyC1     : signal is "P8";    -- B8
    attribute LOC of KeyC2     : signal is "P9";    -- B10
    attribute LOC of KeyC3     : signal is "P10";   -- B12
    attribute LOC of KeyC4     : signal is "P11";   -- B13
    -- segments (through U4)
    attribute LOC of SegA      : signal is "P41";   -- E0
    attribute LOC of SegB      : signal is "P42";   -- E2
    attribute LOC of SegC      : signal is "P43";   -- E4
    attribute LOC of SegD      : signal is "P44";   -- E6
    attribute LOC of SegE      : signal is "P49";   -- E12
    attribute LOC of SegF      : signal is "P50";   -- E14
    attribute LOC of SegG      : signal is "P53";   -- F0
    -- digits (through U5/U6)
    attribute LOC of Dig0      : signal is "P67";   -- G8,  LED2 CC1
    attribute LOC of Dig1      : signal is "P65";   -- G12, LED2 CC2
    attribute LOC of Dig2      : signal is "P61";   -- F13, LED2 CC3
    attribute LOC of Dig3      : signal is "P59";   -- F10, LED2 CC4
    attribute LOC of Dig4      : signal is "P58";   -- F8,  LED3 CC1
    attribute LOC of Dig5      : signal is "P60";   -- F12, LED3 CC2
    attribute LOC of Dig6      : signal is "P64";   -- G14, LED3 CC3
    attribute LOC of Dig7      : signal is "P66";   -- G10, LED3 CC4
    attribute LOC of Dig8      : signal is "P69";   -- G6,  LED4 CC1
    attribute LOC of Dig9      : signal is "P70";   -- G5,  LED4 CC2
    attribute LOC of Dig10     : signal is "P71";   -- G4,  LED4 CC3
    attribute LOC of Dig11     : signal is "P72";   -- G2,  LED4 CC4
end DividerTop;


architecture structural of DividerTop is

    signal Sense, Scan : std_logic_vector(3 downto 0);
    signal Seg         : std_logic_vector(6 downto 0);
    signal Dig         : std_logic_vector(11 downto 0);

begin

    core : entity work.SerialDivider
        port map(
            clk        => CLK,
            DivisorSel => DivSwitch,
            nCalc      => Calculate,
            KeyCol     => Sense,        -- sensed lines (board rows)
            KeyRow     => Scan,         -- driven lines (board columns)
            Segment    => Seg,
            Digit      => Dig
        );

    Sense <= KeyR4 & KeyR3 & KeyR2 & KeyR1;
    KeyC1 <= Scan(0);  KeyC2 <= Scan(1);  KeyC3 <= Scan(2);  KeyC4 <= Scan(3);

    SegA <= Seg(6);  SegB <= Seg(5);  SegC <= Seg(4);  SegD <= Seg(3);
    SegE <= Seg(2);  SegF <= Seg(1);  SegG <= Seg(0);

    Dig0  <= Dig(0);   Dig1  <= Dig(1);   Dig2  <= Dig(2);   Dig3  <= Dig(3);
    Dig4  <= Dig(4);   Dig5  <= Dig(5);   Dig6  <= Dig(6);   Dig7  <= Dig(7);
    Dig8  <= Dig(8);   Dig9  <= Dig(9);   Dig10 <= Dig(10);  Dig11 <= Dig(11);

end structural;
