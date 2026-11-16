------------------------------------------------------------------------------
-- divider.vhd
--
-- description:
--   16 bit / 16 bit serial divider for the ispMACH4128ZE board, built to
--   squeeze in all the extra credit. restoring shift-subtract division done
--   bit serially (one 1-bit subtractor + borrow flop), 2 passes per round
--   (compare, then subtract only if it fits). the counter that times the
--   display is reused as the bit/round counter while dividing.
--
--   extra credit in here:
--     - keypad scanning + debounce in the cpld (74C923 not used)
--     - keypad remap (KEYMAP table)
--     - segment decoding in the cpld (16V8 not used)
--     - digit decoding in the cpld (29M16 not used), digits are a one-hot ring
--     - dividend + divisor preserved, all shown with the quotient
--     - remainder, slide switch picks quotient or remainder on digits 8-11
--     - divide by zero shows ---- on digits 8-11
--     - display only blanks for the ~1 ms the divide takes
--
--   display: digits 0-3 dividend, 4-7 divisor, 8-11 quotient/remainder,
--   digit 0 of each group is the most significant nibble. ~1 ms per digit,
--   ~12 ms refresh.
--
-- inputs:
--   clk        - 1 MHz board clock
--   DivisorSel - slide switch, '1' = enter divisor / show remainder,
--                '0' = enter dividend / show quotient
--   nCalc      - calculate push button, active low
--   KeyCol     - keypad columns, pulled up, '0' = key down in active row
--
-- outputs:
--   KeyRow     - keypad rows, active row driven '0', the rest 'Z'
--   Segment    - segments a..g (Segment(6) = a, Segment(0) = g)
--   Digit      - one-hot digit enables, Digit(0) = digit 0
--
-- edits:
--   11/15/26  aadi  first version, all extra credit, sims clean
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SerialDivider is
    port(
        clk        : in  std_logic;                     -- 1 MHz clock
        DivisorSel : in  std_logic;                     -- slide switch
        nCalc      : in  std_logic;                     -- calc button, active low
        KeyCol     : in  std_logic_vector(3 downto 0);  -- keypad columns
        KeyRow     : out std_logic_vector(3 downto 0);  -- keypad rows
        Segment    : out std_logic_vector(6 downto 0);  -- a..g
        Digit      : out std_logic_vector(11 downto 0)  -- digit enables
    );
end SerialDivider;


architecture behavioral of SerialDivider is

    -- polarity of the outputs, CHECK THESE against the board
    --   (segdec.pds / dec412.pds or just flip them if the display is inverted)
    constant SEG_ON : std_logic := '1';     -- level that lights a segment
    constant DIG_ON : std_logic := '1';     -- level that turns a digit on

    -- keypad remap: index is row*4 + col of the key, value is the hex digit
    --   it should enter. identity right now, fill in the natural layout
    type keymap_t is array (0 to 15) of std_logic_vector(3 downto 0);
    constant KEYMAP : keymap_t := (
        x"0", x"1", x"2", x"3",
        x"4", x"5", x"6", x"7",
        x"8", x"9", x"A", x"B",
        x"C", x"D", x"E", x"F");

    -- 7 seg patterns, bits are a b c d e f g
    type segtab_t is array (0 to 15) of std_logic_vector(6 downto 0);
    constant HEX7 : segtab_t := (
        "1111110", "0110000", "1101101", "1111001",     -- 0 1 2 3
        "0110011", "1011011", "1011111", "1110000",     -- 4 5 6 7
        "1111111", "1111011", "1110111", "0011111",     -- 8 9 A b
        "1001110", "0111101", "1001111", "1000111");    -- C d E F
    constant DASH  : std_logic_vector(6 downto 0) := "0000001";
    constant BLANK : std_logic_vector(6 downto 0) := "0000000";

    -- the 4 value registers
    signal N : std_logic_vector(15 downto 0) := (others => '0');   -- dividend
    signal D : std_logic_vector(15 downto 0) := (others => '0');   -- divisor
    signal Q : std_logic_vector(15 downto 0) := (others => '0');   -- quotient
    signal R : std_logic_vector(15 downto 0) := (others => '0');   -- remainder

    signal Borrow : std_logic := '0';       -- serial subtractor borrow

    -- shared counter: display prescaler when idle, bit/round counter when
    --   dividing. bits 5..0 = clock within a round, bits 9..6 = round
    signal Pre  : unsigned(9 downto 0) := (others => '0');
    signal Busy : std_logic := '0';         -- dividing

    signal Ring : std_logic_vector(11 downto 0) := (others => '0'); -- digit ring
    signal Lat  : std_logic_vector(3 downto 0)  := (others => '0'); -- shown nibble

    signal DivZero : std_logic := '0';      -- last divide was by zero
    signal CalcS   : std_logic := '0';      -- calc button last sample
    signal KeyDown : std_logic := '0';      -- a key is being held
    signal Seen    : std_logic := '0';      -- key seen during this scan
    signal Quiet   : unsigned(1 downto 0) := "00";  -- scans with no key

    -- combinational stuff
    signal Tick     : std_logic;            -- end of a digit time
    signal Cyc      : integer range 0 to 63;-- clock within a round
    signal RowSel   : std_logic_vector(3 downto 0);
    signal Hit      : std_logic;
    signal KeyCode  : std_logic_vector(3 downto 0);
    signal Diff     : std_logic;
    signal BorrowNx : std_logic;
    signal Fit      : std_logic;
    signal NextNib  : std_logic_vector(3 downto 0);
    signal Grp2     : std_logic;

begin

    -- digit time ends every 1024 clocks, only when not dividing
    Tick <= '1' when Busy = '0' and Pre = 1023 else '0';
    Cyc  <= to_integer(Pre(5 downto 0));

    -- serial subtractor, R - D one bit per clock, lsb first
    Diff     <= R(0) xor D(0) xor Borrow;
    BorrowNx <= ((not R(0)) and D(0)) or ((not R(0)) and Borrow) or
                (D(0) and Borrow);
    Fit      <= not Borrow;             -- divisor fits if no borrow out
                                        -- (no 17th R bit needed: for 16/16
                                        --  unsigned, R < 2^k after round k,
                                        --  so 2R + bit never overflows)

    -- keypad: each digit time scans one row (row = digit mod 4)
    RowSel(0) <= Ring(0) or Ring(4) or Ring(8);
    RowSel(1) <= Ring(1) or Ring(5) or Ring(9);
    RowSel(2) <= Ring(2) or Ring(6) or Ring(10);
    RowSel(3) <= Ring(3) or Ring(7) or Ring(11);

    rowdrv : for i in 0 to 3 generate
        KeyRow(i) <= '0' when RowSel(i) = '1' else 'Z';
    end generate rowdrv;

    Hit <= '1' when KeyCol /= "1111" else '0';

    -- row/col -> hex digit through the remap table
    keyenc : process(RowSel, KeyCol)
        variable row, col : integer range 0 to 3;
    begin
        row := 0;
        for i in 0 to 3 loop
            if RowSel(i) = '1' then row := i; end if;
        end loop;
        col := 0;
        for i in 3 downto 0 loop            -- lowest column wins
            if KeyCol(i) = '0' then col := i; end if;
        end loop;
        KeyCode <= KEYMAP(row*4 + col);
    end process keyenc;

    -- nibble for the NEXT digit (the latch loads as the ring advances)
    --   ring bit p on -> load nibble for digit p+1
    nibmux : process(Ring, N, D, Q, R, DivisorSel)
        variable nib : std_logic_vector(3 downto 0);
        variable val : std_logic_vector(15 downto 0);
        variable dq  : integer range 0 to 11;
        variable lo  : integer range 0 to 12;
    begin
        nib := "0000";
        for p in 0 to 11 loop
            dq := (p + 1) mod 12;           -- digit this ring bit loads for
            if dq < 4 then
                val := N;
            elsif dq < 8 then
                val := D;
            elsif DivisorSel = '1' then
                val := R;
            else
                val := Q;
            end if;
            lo := 4*(3 - (dq mod 4));       -- digit 0 of a group = top nibble
            if Ring(p) = '1' then
                nib := nib or val(lo + 3 downto lo);
            end if;
        end loop;
        NextNib <= nib;
    end process nibmux;

    Grp2 <= Ring(8) or Ring(9) or Ring(10) or Ring(11);

    -- segment decode, blank while dividing, dashes for divide by zero
    segdec : process(Busy, DivZero, Grp2, Lat)
        variable s : std_logic_vector(6 downto 0);
    begin
        if Busy = '1' then
            s := BLANK;
        elsif DivZero = '1' and Grp2 = '1' then
            s := DASH;
        else
            s := HEX7(to_integer(unsigned(Lat)));
        end if;
        if SEG_ON = '1' then
            Segment <= s;
        else
            Segment <= not s;
        end if;
    end process segdec;

    Digit <= Ring when DIG_ON = '1' else not Ring;


    main : process(clk)
    begin
        if rising_edge(clk) then

            Pre <= Pre + 1;                 -- always counting

            if Busy = '1' then
                -- dividing, 16 rounds of 64 clocks
                if Cyc = 0 then             -- shift R:N left, Q left
                    R    <= R(14 downto 0) & N(15);
                    N    <= N(14 downto 0) & N(15);     -- rotate, comes back
                    Q    <= Q(14 downto 0) & '0';
                    Borrow <= '0';

                elsif Cyc <= 16 then        -- pass A: compare R - D
                    R      <= R(0) & R(15 downto 1);    -- rotate, unchanged
                    D      <= D(0) & D(15 downto 1);
                    Borrow <= BorrowNx;
                    if D(0) = '1' then
                        DivZero <= '0';     -- divisor has a 1 somewhere
                    end if;

                elsif Cyc = 17 then         -- store quotient bit
                    Q(0)   <= Fit;
                    Borrow <= '0';

                elsif Cyc <= 33 then        -- pass B: subtract if it fit
                    if Q(0) = '1' then
                        R <= Diff & R(15 downto 1);
                    else
                        R <= R(0) & R(15 downto 1);
                    end if;
                    D      <= D(0) & D(15 downto 1);
                    Borrow <= BorrowNx;
                end if;

                if Pre = 1023 then          -- last round done
                    Busy <= '0';
                end if;

            elsif Tick = '1' then
                -- display: next digit
                Lat <= NextNib;
                if Ring = "000000000000" then   -- self start
                    Ring <= "000000000001";
                else
                    Ring <= Ring(10 downto 0) & Ring(11);
                end if;

                -- keypad: new key press shifts a nibble in
                if Hit = '1' and KeyDown = '0' then
                    KeyDown <= '1';
                    if DivisorSel = '1' then
                        D <= D(11 downto 0) & KeyCode;
                    else
                        N <= N(11 downto 0) & KeyCode;
                    end if;
                end if;

                -- keypad: release after 2 full scans with nothing pressed
                if RowSel(3) = '1' then     -- end of a full scan
                    Seen <= '0';
                    if (Seen or Hit) = '1' then
                        Quiet <= "00";
                    else
                        if Quiet /= "11" then
                            Quiet <= Quiet + 1;
                        end if;
                        if Quiet = "01" then
                            KeyDown <= '0';
                        end if;
                    end if;
                else
                    Seen <= Seen or Hit;
                end if;

                -- calc button, sampled once a digit time so bounce is
                --   ignored, divide on the press
                CalcS <= not nCalc;
                if nCalc = '0' and CalcS = '0' then
                    Busy    <= '1';
                    R       <= (others => '0');
                    Borrow  <= '0';
                    DivZero <= '1';
                end if;
            end if;

        end if;
    end process main;

end behavioral;
