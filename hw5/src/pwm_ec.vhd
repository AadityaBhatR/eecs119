--------------------------------------------------------------------------------
--
--  pwm_ec.vhd - PWM Audio Player, extra credit (EE 119a HW5, XC9572-PC44)
--
--  Description:
--      Plays message 1 (EPROM 40000-47FFF) using one of three PWM methods,
--      chosen by the switches, so they can be compared by ear:
--
--          SW4  normal       - 16x oversampled: 16 pulses per sample,
--                              output high while cnt(7 downto 0) < sample
--          SW3  no oversamp. - one pulse per sample, sample*16 clocks wide:
--                              output high while cnt(11 downto 4) < sample
--          SW2  lfsr         - no oversampling, but compares the sample with
--                              an 8-bit LFSR stepped every 16 clocks, so the
--                              high time is scattered randomly in the period
--          SW1  unused
--
--      Pressing a mode switch selects that mode immediately (also while
--      playing) and starts the message if idle. The message repeats if a
--      mode switch is held at the end, otherwise the player goes idle.
--      Sample timing and pipelining are the same as pwm.vhd.
--
--  Inputs:
--      CLK          - 32 MHz clock
--      SW1..SW4     - switches, active high (pressed = '1')
--      AudioData    - EPROM data
--
--  Outputs:
--      AudioAddr    - EPROM address (A18 is always '1')
--      AudioPWMOut  - PWM audio output
--
--  Internal constants:
--      IDLE, PLAY   - FSM states (one bit, IDLE = '0' = power-up state)
--      MSG_START    - message start address, low 18 bits (0x40000)
--      MSG_END      - message end address (exclusive), low 18 bits (0x48000)
--
--  Internal signals:
--      cnt          - 12-bit sample counter
--      tick         - '1' on the last clock of each sample period
--      pressed      - synced switches, active high (bit 0 = SW4 ... 3 = SW1)
--      state        - FSM state
--      mode         - PWM method: 00 normal, 01 no oversampling, 10 lfsr
--      addr         - EPROM address bits 17..0
--      sample       - audio byte being output
--      lfsr         - 8-bit xnor LFSR (255 states, never all ones)
--      pwm_norm     - normal comparator output
--      pwm_noos     - no-oversampling comparator output
--      pwm_lfsr     - lfsr comparator output
--      pwm_out      - registered PWM output
--
--  Revision History:
--      11/06/26  Aadi   Initial revision
--      11/06/26  Aadi   Lint Pass
--      11/07/26  Aadi   TB Pass
--      11/07/26  Aadi   Documentation Carry Over
--      11/07/26  Aadi   Switches are active high (fixed polarity)
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm_ec is
    port (
        CLK         : in  std_logic;
        SW1         : in  std_logic;
        SW2         : in  std_logic;
        SW3         : in  std_logic;
        SW4         : in  std_logic;
        AudioData   : in  std_logic_vector(7 downto 0);
        AudioAddr   : out std_logic_vector(18 downto 0);
        AudioPWMOut : out std_logic
    );
end entity pwm_ec;


architecture rtl of pwm_ec is

    constant IDLE      : std_logic := '0';
    constant PLAY      : std_logic := '1';
    constant MSG_START : unsigned(17 downto 0) := to_unsigned(16#00000#, 18);
    constant MSG_END   : unsigned(17 downto 0) := to_unsigned(16#08000#, 18);

    signal cnt      : unsigned(11 downto 0)        := (others => '0');
    signal tick     : std_logic;
    signal pressed  : std_logic_vector(3 downto 0) := (others => '0');
    signal state    : std_logic                    := IDLE;
    signal mode     : std_logic_vector(1 downto 0) := "00";
    signal addr     : unsigned(17 downto 0)        := (others => '0');
    signal sample   : unsigned(7 downto 0)         := (others => '0');
    signal lfsr     : unsigned(7 downto 0)         := (others => '0');
    signal pwm_norm : std_logic;
    signal pwm_noos : std_logic;
    signal pwm_lfsr : std_logic;
    signal pwm_out  : std_logic                    := '0';

begin

    -- sample counter increments on clock and wraps every 4096 clocks
    counter: process(CLK)
    begin
        if rising_edge(CLK) then
            cnt <= cnt + 1;
        end if;
    end process counter;

    -- last clock of sample period
    tick <= '1' when cnt = 4095 else '0';

    -- sync switches (active high) b0 = sw4 ... b3 = sw1
    sync_switches: process(CLK)
    begin
        if rising_edge(CLK) then
            pressed <= SW1 & SW2 & SW3 & SW4;
        end if;
    end process sync_switches;

    -- lfsr steps every 16 clocks w/ xnor feedback so all zeros should b fine
    lfsr_gen: process(CLK)
    begin
        if rising_edge(CLK) then
            if cnt(3 downto 0) = "1111" then
                lfsr <= lfsr(6 downto 0) &
                        not (lfsr(7) xor lfsr(5) xor lfsr(4) xor lfsr(3));
            end if;
        end if;
    end process lfsr_gen;

    -- player fsm that only acts on ticks
    control: process(CLK)
    begin
        if rising_edge(CLK) then
            if tick = '1' then

                -- any mode switch pressed selects mode sw4 still prio
                if    pressed(0) = '1' then mode <= "00";
                elsif pressed(1) = '1' then mode <= "01";
                elsif pressed(2) = '1' then mode <= "10";
                end if;

                if state = IDLE then
                    -- mode switch pressed -> start the message,sample init 0
                    -- same as last
                    if pressed(2 downto 0) /= "000" then
                        addr   <= MSG_START;
                        sample <= (others => '0');
                        state  <= PLAY;
                    end if;

                elsif addr = MSG_END then
                    -- EOM - repeat if a mode switch is held, else idle
                    if pressed(2 downto 0) /= "000" then
                        addr  <= MSG_START;
                    else
                        state <= IDLE;
                    end if;

                else
                    -- latch byte at addr then fetch the next
                    sample <= unsigned(AudioData);
                    addr   <= addr + 1;
                end if;

            end if;
        end if;
    end process control;

    -- the three pwm comparators
    pwm_norm <= '1' when cnt(7 downto 0)  < sample else '0';
    pwm_noos <= '1' when cnt(11 downto 4) < sample else '0';
    pwm_lfsr <= '1' when lfsr             < sample else '0';

    -- pick the comparator for the current mode and low when idle
    pwm_gen: process(CLK)
    begin
        if rising_edge(CLK) then
            if state = IDLE then
                pwm_out <= '0';
            elsif mode = "01" then
                pwm_out <= pwm_noos;
            elsif mode = "10" then
                pwm_out <= pwm_lfsr;
            else
                pwm_out <= pwm_norm;
            end if;
        end if;
    end process pwm_gen;

    -- outputs
    AudioAddr   <= '1' & std_logic_vector(addr);
    AudioPWMOut <= pwm_out;

end architecture rtl;
