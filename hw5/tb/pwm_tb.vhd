--------------------------------------------------------------------------------
--
--  pwm_tb.vhd - testbench for pwm.vhd (EE 119a HW5)
--
--  Description:
--      Runs two copies of the player:
--        uut_full (CNT_BITS = 12) - real timing; checks the sample period,
--                                   pipelining and PWM pulse widths
--        uut_fast (CNT_BITS = 8)  - 256 clocks per sample so a whole message
--                                   simulates quickly; checks end and repeat
--      The EPROM model outputs 'X' for 120 ns after each address change, then
--      data = low address byte xor A5, so reading too early gives bad pulses.
--      Any failed check prints a message; no messages means it passed.
--      The simulation stops on its own at about 263 ms.
--
--  Tests:
--      1. idle after power-up: no output, no address change
--      2. full, SW2: loads 58000, silent first period of 4096 clocks,
--         16 pulses of 165 clocks (A5), then next sample (A4 = 164 clocks)
--      3. fast, SW1 pressed and released: loads 7C000, steps 4000 (hex)
--         times to 80000 (wraps to 40000), then goes idle
--      4. fast, SW1 held through the end: reloads 7C000 (repeats)
--
--  Revision History:
--      11/07/26  Aadi   Initial revision
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm_tb is
end entity pwm_tb;


architecture tb of pwm_tb is

    constant T_CLK    : time := 31.25 ns;       -- 32 MHz
    constant T_ACC    : time := 120 ns;         -- eprom access time
    constant T_SAMPLE : time := 256 * T_CLK;    -- uut_fast sample period

    signal CLK   : std_logic := '0';
    signal done  : boolean   := false;

    signal swA   : std_logic_vector(1 to 4) := "1111";   -- uut_full sw1..sw4
    signal dataA : std_logic_vector(7 downto 0);
    signal addrA : std_logic_vector(18 downto 0);
    signal pwmA  : std_logic;

    signal swB   : std_logic_vector(1 to 4) := "1111";   -- uut_fast sw1..sw4
    signal dataB : std_logic_vector(7 downto 0);
    signal addrB : std_logic_vector(18 downto 0);
    signal pwmB  : std_logic;

begin

    -- 32 mhz clock, stops when done
    clk_gen: process
    begin
        while not done loop
            CLK <= '0';
            wait for T_CLK / 2;
            CLK <= '1';
            wait for T_CLK / 2;
        end loop;
        wait;
    end process clk_gen;

    -- eprom models: 'X' during access, then low address byte xor A5
    dataA <= (others => 'X'), addrA(7 downto 0) xor x"A5" after T_ACC;
    dataB <= (others => 'X'), addrB(7 downto 0) xor x"A5" after T_ACC;

    uut_full: entity work.pwm
        generic map (CNT_BITS => 12)
        port map (CLK => CLK,
                  SW1 => swA(1), SW2 => swA(2), SW3 => swA(3), SW4 => swA(4),
                  AudioData => dataA, AudioAddr => addrA, AudioPWMOut => pwmA);

    uut_fast: entity work.pwm
        generic map (CNT_BITS => 8)
        port map (CLK => CLK,
                  SW1 => swB(1), SW2 => swB(2), SW3 => swB(3), SW4 => swB(4),
                  AudioData => dataB, AudioAddr => addrB, AudioPWMOut => pwmB);

    -- drive switches and check outputs
    stim: process
        variable t0, t1 : time;
        variable steps  : natural;
    begin

        -- test 1: idle after power-up
        wait for 1 ns;                              -- skip time-0 init events
        wait until pwmA = '1' or pwmB = '1' or addrA'event or addrB'event
            for 300 us;
        assert now >= 300 us report "output or address changed while idle";

        -- test 2: uut_full plays sw2 message (58000)
        swA(2) <= '0';
        wait until unsigned(addrA) = 16#58000# for 300 us;
        assert unsigned(addrA) = 16#58000# report "sw2 did not load 58000";
        t0 := now;
        swA(2) <= '1';

        wait until pwmA = '1' or unsigned(addrA) = 16#58001# for 200 us;
        assert pwmA = '0' report "output during first (fetch) period";
        assert now - t0 = 4096 * T_CLK report "sample period is not 4096 clocks";

        for i in 1 to 16 loop
            wait until pwmA = '1';
            t1 := now;
            wait until pwmA = '0';
            assert now - t1 = 165 * T_CLK report "pulse of sample A5 is not 165 clocks";
        end loop;

        wait until pwmA = '1';
        t1 := now;
        wait until pwmA = '0';
        assert now - t1 = 164 * T_CLK report "17th pulse is not next sample (164 clocks)";

        -- test 3: uut_fast plays sw1 message once (7C000-7FFFF)
        swB(1) <= '0';
        wait until unsigned(addrB) = 16#7C000# for 2 * T_SAMPLE;
        assert unsigned(addrB) = 16#7C000# report "sw1 did not load 7C000";
        swB(1) <= '1';

        steps := 0;
        while unsigned(addrB) /= 16#40000# loop
            wait on addrB for 2 * T_SAMPLE;
            exit when not addrB'event;              -- address stopped early
            steps := steps + 1;
        end loop;
        assert steps = 16#4000# report "sw1 message is not 4000 (hex) samples long";

        wait for 2 * T_CLK;
        wait until pwmB = '1' or addrB'event for 10 * T_SAMPLE;
        assert pwmB = '0' and unsigned(addrB) = 16#40000#
            report "not idle after message ended";

        -- test 4: uut_fast, sw1 held through the end -> repeats
        swB(1) <= '0';
        wait until unsigned(addrB) = 16#7C000# for 2 * T_SAMPLE;
        wait until unsigned(addrB) = 16#40000# for 16#4001# * T_SAMPLE;
        assert unsigned(addrB) = 16#40000# report "sw1 message did not reach its end";
        wait on addrB for 2 * T_SAMPLE;
        assert unsigned(addrB) = 16#7C000# report "held switch did not repeat message";
        swB(1) <= '1';

        done <= true;
        wait;
    end process stim;

end architecture tb;
