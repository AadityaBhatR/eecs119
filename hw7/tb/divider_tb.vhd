------------------------------------------------------------------------------
-- divider_tb.vhd
--
-- description:
--   test bench for SerialDivider. models the keypad matrix with bouncing
--   presses and releases and a bouncing calc button, then reads the answer
--   back off the 7 seg display (decodes segments per digit) so it checks the
--   whole thing end to end: scan, debounce, entry, divide, display mux,
--   segment decode, remainder select, divide by zero.
--
-- inputs:  none (generates everything)
-- outputs: none (asserts + a pass/fail report at the end)
--
-- edits:
--   11/15/26  aadi  first version
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity divider_tb is
    generic(PRESERVE : boolean := false);   -- match the design's setting
end divider_tb;

architecture tb of divider_tb is

    signal clk        : std_logic := '0';
    signal DivisorSel : std_logic := '0';
    signal nCalc      : std_logic := '1';
    signal KeyCol     : std_logic_vector(3 downto 0);
    signal KeyRow     : std_logic_vector(3 downto 0);
    signal Segment    : std_logic_vector(6 downto 0);
    signal Digit      : std_logic_vector(11 downto 0);
    signal done       : boolean := false;

    -- keypad model: which key is held and whether the contact is closed
    signal kRow, kCol : integer range 0 to 3 := 0;
    signal contact    : std_logic := '0';

    -- what each digit showed last time it was lit (0-15, 16 dash, 17 blank)
    type shown_t is array (0 to 11) of integer;
    signal shown : shown_t := (others => -1);

    type segtab_t is array (0 to 15) of std_logic_vector(6 downto 0);
    constant HEX7 : segtab_t := (
        "1111110", "0110000", "1101101", "1111001",
        "0110011", "1011011", "1011111", "1110000",
        "1111111", "1111011", "1110111", "0011111",
        "1001110", "0111101", "1001111", "1000111");

    function seg2int(s : std_logic_vector(6 downto 0)) return integer is
    begin
        for i in 0 to 15 loop
            if s = HEX7(i) then return i; end if;
        end loop;
        if s = "0000001" then return 16; end if;
        if s = "0000000" then return 17; end if;
        return -1;
    end function;

    signal errors : integer := 0;

begin

    uut : entity work.SerialDivider
        generic map(SEG_ON => '1', DIG_ON => '1', PRESERVE => PRESERVE)   -- active high for easy decoding
        port map(clk, DivisorSel, nCalc, KeyCol, KeyRow, Segment, Digit);

    clk <= not clk after 500 ns when not done;      -- 1 MHz

    -- keypad matrix: pressed key pulls its column low when its row is driven
    cols : for c in 0 to 3 generate
        KeyCol(c) <= '0' when contact = '1' and kCol = c and KeyRow(kRow) = '0'
                     else '1';
    end generate cols;

    -- read the display: half way through each digit time grab the segments
    mon : process
    begin
        wait until Digit'event;
        wait for 400 us;
        for p in 0 to 11 loop
            if Digit(p) = '1' then
                shown(p) <= seg2int(Segment);
            end if;
        end loop;
    end process mon;

    stim : process

        -- bouncy key press of hex digit k (identity keymap: row k/4, col k%4)
        procedure key(k : integer) is
        begin
            kRow <= k / 4;
            kCol <= k mod 4;
            contact <= '1'; wait for 300 us;        -- press bounce
            contact <= '0'; wait for 500 us;
            contact <= '1'; wait for 400 us;
            contact <= '0'; wait for 200 us;
            contact <= '1'; wait for 15 ms;         -- held
            contact <= '0'; wait for 300 us;        -- release bounce
            contact <= '1'; wait for 200 us;
            contact <= '0'; wait for 400 us;
            contact <= '1'; wait for 300 us;
            contact <= '0'; wait for 20 ms;         -- released
        end procedure;

        procedure enter(v : integer; ndig : integer; sel : std_logic) is
            variable u : unsigned(19 downto 0);
        begin
            DivisorSel <= sel;
            wait for 1 ms;
            u := to_unsigned(v, 20);
            for i in ndig - 1 downto 0 loop
                key(to_integer(u(4*i + 3 downto 4*i)));
            end loop;
        end procedure;

        procedure calc is
        begin
            nCalc <= '0'; wait for 700 us;          -- bouncy button
            nCalc <= '1'; wait for 600 us;
            nCalc <= '0'; wait for 1200 us;
            nCalc <= '1'; wait for 400 us;
            nCalc <= '0'; wait for 30 ms;           -- held a while
            nCalc <= '1'; wait for 500 us;
            nCalc <= '0'; wait for 300 us;
            nCalc <= '1'; wait for 10 ms;
        end procedure;

        function grp(s : shown_t; g : integer) return integer is
            variable v : integer := 0;
        begin
            for i in 0 to 3 loop
                if s(4*g + i) < 0 or s(4*g + i) > 15 then
                    return -s(4*g + i) - 100;       -- not a hex digit
                end if;
                v := v*16 + s(4*g + i);
            end loop;
            return v;
        end function;

        procedure fail(msg : string) is
        begin
            report msg severity error;
            errors <= errors + 1;
            wait for 0 ns;
        end procedure;

        -- quotient/remainder/divisor groups depend on PRESERVE:
        --   PRESERVE:     0 = dividend, 1 = divisor, 2 = quot (sw 0)/rem (sw 1)
        --   not PRESERVE: 0 = quotient, 1 = divisor, 2 = remainder
        procedure check(name : string; n, d : integer) is
            variable qg : integer;
        begin
            if PRESERVE then qg := 2; else qg := 0; end if;
            DivisorSel <= '0'; wait for 30 ms;
            if d = 0 then
                for i in 4*qg to 4*qg + 3 loop
                    if shown(i) /= 16 then
                        fail(name & ": expected ---- for divide by zero");
                        exit;
                    end if;
                end loop;
            elsif grp(shown, qg) /= n / d then
                fail(name & ": quotient shows " & integer'image(grp(shown, qg))
                     & " expected " & integer'image(n / d));
            end if;
            if grp(shown, 1) /= d then
                fail(name & ": divisor shows " & integer'image(grp(shown, 1)));
            end if;
            if PRESERVE and grp(shown, 0) /= n then
                fail(name & ": dividend not preserved, shows "
                     & integer'image(grp(shown, 0)));
            end if;
            if PRESERVE then
                DivisorSel <= '1'; wait for 30 ms;
            end if;
            if d /= 0 and grp(shown, 2) /= n mod d then
                fail(name & ": remainder shows " & integer'image(grp(shown, 2))
                     & " expected " & integer'image(n mod d));
            end if;
            report name & " checked";
        end procedure;

        procedure test(name : string; n, d : integer) is
        begin
            enter(n, 4, '0');
            enter(d, 4, '1');
            calc;
            check(name, n, d);
        end procedure;

    begin
        wait for 5 ms;

        test("1234/0056", 16#1234#, 16#0056#);
        test("FFFF/0001", 16#FFFF#, 16#0001#);
        test("FFFF/FFFF", 16#FFFF#, 16#FFFF#);
        test("0005/0007", 16#0005#, 16#0007#);
        test("8000/0003", 16#8000#, 16#0003#);
        test("ABCD/0000", 16#ABCD#, 16#0000#);
        test("C0DE/00FF", 16#C0DE#, 16#00FF#);
        test("0000/1234", 16#0000#, 16#1234#);
        test("FFFF/8001", 16#FFFF#, 16#8001#);
        test("FFFE/FFFF", 16#FFFE#, 16#FFFF#);
        test("7FFF/8000", 16#7FFF#, 16#8000#);
        test("0001/0001", 16#0001#, 16#0001#);
        test("9C40/0064", 16#9C40#, 16#0064#);
        test("A5CD/0003", 16#A5CD#, 16#0003#);
        test("2516/008A", 16#2516#, 16#008A#);
        test("1DB2/000F", 16#1DB2#, 16#000F#);
        test("2C01/0007", 16#2C01#, 16#0007#);
        test("2E71/0F22", 16#2E71#, 16#0F22#);
        test("3F62/A0A0", 16#3F62#, 16#A0A0#);
        test("1FAC/000A", 16#1FAC#, 16#000A#);
        test("7131/0001", 16#7131#, 16#0001#);
        test("9447/0007", 16#9447#, 16#0007#);
        test("9DF1/0009", 16#9DF1#, 16#0009#);

        -- more than 4 digits: high nibble falls off, 12345 -> 2345
        enter(16#12345#, 5, '0');
        enter(16#00987#, 5, '1');
        calc;
        check("12345/00987 (overflow entry)", 16#2345#, 16#0987#);

        -- recalc: same answer if the dividend is kept, otherwise it divides
        --   the quotient again (2345/0987 = 3, then 3/0987 = 0 r 3)
        calc;
        if PRESERVE then
            check("recalc 2345/0987", 16#2345#, 16#0987#);
        else
            check("recalc 0003/0987", 16#0003#, 16#0987#);
        end if;

        -- blanked while dividing, but not the whole time the button is held
        nCalc <= '0';
        wait for 5 ms;
        if shown(8) = 17 then
            fail("display still blank while calc held");
        end if;
        nCalc <= '1';
        wait for 10 ms;

        if errors = 0 then
            report "ALL TESTS PASSED";
        else
            report integer'image(errors) & " ERRORS" severity error;
        end if;
        done <= true;
        wait;
    end process stim;

end tb;
