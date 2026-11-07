--------------------------------------------------------------------------------
--
--  pwm_ec_tb.vhd - testbench for pwm_ec.vhd (EE 119a HW5 extra credit)
--
--  Description:
--      The EPROM model outputs 'X' for 120 ns after each address change, then
--      a constant A5 (165), so every sample has the same value. A monitor
--      counts, for each sample period, the clocks the output is high and the
--      number of pulses. For sample 165:
--          normal (SW4)          - 2640 high clocks (16 x 165) in 16 pulses
--          no oversampling (SW3) - 2640 high clocks (165 x 16) in 1 pulse
--          lfsr (SW2)            - ~2640 high clocks (16 x 165 or 166),
--                                  scattered in many pulses
--      Any failed check prints a message; no messages means it passed.
--      The simulation stops on its own at about 1.2 ms.
--
--  Revision History:
--      11/07/26  Aadi   Initial revision
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm_ec_tb is
end entity pwm_ec_tb;


architecture tb of pwm_ec_tb is

    constant T_CLK : time := 31.25 ns;          -- 32 MHz
    constant T_ACC : time := 120 ns;            -- eprom access time

    signal CLK    : std_logic := '0';
    signal done   : boolean   := false;
    signal sw     : std_logic_vector(1 to 4) := "1111";     -- sw1..sw4
    signal data   : std_logic_vector(7 downto 0);
    signal addr   : std_logic_vector(18 downto 0);
    signal pwm    : std_logic;

    signal highs  : natural := 0;               -- high clocks, last period
    signal pulses : natural := 0;               -- pulses, last period

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

    -- eprom model: 'X' during access, then constant A5
    data <= (others => 'X'), x"A5" after T_ACC;

    uut: entity work.pwm_ec
        port map (CLK => CLK,
                  SW1 => sw(1), SW2 => sw(2), SW3 => sw(3), SW4 => sw(4),
                  AudioData => data, AudioAddr => addr, AudioPWMOut => pwm);

    -- count high clocks and pulses per sample period (period ends when
    -- the address changes; results are published one clock later)
    monitor: process(CLK)
        variable h, p      : natural := 0;
        variable last_pwm  : std_logic := '0';
        variable last_addr : std_logic_vector(18 downto 0) := (others => '0');
    begin
        if rising_edge(CLK) then
            if pwm = '1' then
                h := h + 1;
                if last_pwm = '0' then
                    p := p + 1;
                end if;
            end if;
            last_pwm := pwm;
            if addr /= last_addr then
                highs  <= h;
                pulses <= p;
                h := 0;
                p := 0;
                last_addr := addr;
            end if;
        end if;
    end process monitor;

    -- press each mode switch and check the period after it takes effect
    stim: process
    begin

        -- idle after power up
        wait until pwm = '1' for 300 us;
        assert pwm = '0' report "output while idle";

        -- sw4 normal: silent first period, then 16 pulses of 165
        sw(4) <= '0';
        wait on addr;                               -- end of first period
        sw(4) <= '1';
        wait for 2 * T_CLK;
        assert highs = 0 report "first (fetch) period not silent";
        wait on addr;
        wait for 2 * T_CLK;
        assert highs = 2640 and pulses = 16 report "normal mode wrong";

        -- sw3 no oversampling now one pulse of 165 * 16 clocks
        sw(3) <= '0';
        wait on addr;                               -- mode changes here
        sw(3) <= '1';
        wait on addr;
        wait for 2 * T_CLK;
        assert highs = 2640 and pulses = 1 report "no-oversampling mode wrong";

      
        sw(2) <= '0';
        wait on addr;
        sw(2) <= '1';
        wait on addr;
        wait for 2 * T_CLK;
        assert highs >= 2640 and highs <= 2656 and pulses > 16
            report "lfsr mode wrong";

        done <= true;
        wait;
    end process stim;

end architecture tb;
