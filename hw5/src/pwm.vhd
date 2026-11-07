--------------------------------------------------------------------------------
--
--  pwm.vhd - PWM Audio Player (EE 119a HW5, Xilinx XC9572-PC44)
--
--  Description:
--      Plays one of four 8-bit audio messages from the upper half of a 27C040
--      EPROM as a PWM signal. Pressing a switch plays its message in its
--      entirety; if the switch is still held at the end, the message repeats,
--      otherwise the player goes idle (output low). Other switches are
--      ignored while a message plays.
--
--          Switch   Start    Length   End (exclusive)
--          SW4      40000    08000    48000
--          SW3      48000    10000    58000
--          SW2      58000    24000    7C000
--          SW1      7C000    04000    80000 (wraps to 40000)
--
--      A free-running counter wraps every 4096 clocks (one sample period).
--      On each wrap ("tick") the EPROM byte is latched and the address is
--      incremented, so the EPROM has a whole sample period to settle
--      (pipelining). Each sample is output as 16 PWM pulses: the output is
--      set when cnt(7 downto 0) = 0 and cleared when it equals sample.
--
--  Inputs:
--      CLK          - 32 MHz clock
--      SW1..SW4     - message switches, active high (pressed = '1'; normally
--                     closed contact holds the pin low until pressed)
--      AudioData    - EPROM data
--
--  Outputs:
--      AudioAddr    - EPROM address (A18 is always '1')
--      AudioPWMOut  - PWM audio output
--
--  Generics:
--      CNT_BITS     - log2 of clocks per sample (12 for the real board;
--                     the testbench uses 8 to simulate whole messages fast)
--
--  Internal constants:
--      IDLE, PLAY   - FSM states (one bit, IDLE = '0' = power-up state)
--      CNT_MAX      - last count of the sample period
--
--  Internal signals:
--      cnt          - sample counter; low 8 bits are the PWM ramp
--      tick         - '1' on the last clock of each sample period (registered)
--      at_end       - '1' when addr is at the end of the message (registered)
--      pressed      - synced switches, active high (0 = SW4 ... 3 = SW1)
--      sel          - pressed switch with highest priority (0 = SW4 ... 3 = SW1)
--      idx          - lookup table index (sel when idle, msg when playing)
--      msg_start    - start address of message idx (lookup table, low 18 bits)
--      msg_end      - end address of message idx (lookup table, low 18 bits)
--      state        - FSM state
--      msg          - message being played (0 = SW4 ... 3 = SW1)
--      addr         - EPROM address bits 17..0
--      sample       - audio byte being output
--      pwm_out      - registered PWM output
--
--  Revision History:
--      11/05/26  Aadi   Initial file creation
--      11/06/26  Aadi   Entity/Architecture/Process/Logic Initialization
--      11/06/26  Aadi   Successful Lint
--      11/06/26  Aadi   Documentation Updates
--      11/07/26  Aadi   Final TB Check
--      11/07/26  Aadi   Start/end address lookup tables
--      11/07/26  Aadi   Registered tick/at_end, equality pwm to fit XC9572
--      11/07/26  Aadi   Switches are active high (fixed polarity)
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm is
    generic (
        CNT_BITS    : positive := 12
    );
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
end entity pwm;


architecture rtl of pwm is

    constant IDLE    : std_logic := '0';
    constant PLAY    : std_logic := '1';
    constant CNT_MAX : unsigned(CNT_BITS - 1 downto 0) := (others => '1');

    signal cnt       : unsigned(CNT_BITS - 1 downto 0) := (others => '0');
    signal tick      : std_logic                       := '0';
    signal at_end    : std_logic                       := '0';
    signal pressed   : std_logic_vector(3 downto 0)    := (others => '0');
    signal sel       : unsigned(1 downto 0);
    signal idx       : unsigned(1 downto 0);
    signal msg_start : unsigned(17 downto 0);
    signal msg_end   : unsigned(17 downto 0);
    signal state     : std_logic                       := IDLE;
    signal msg       : unsigned(1 downto 0)            := (others => '0');
    signal addr      : unsigned(17 downto 0)           := (others => '0');
    signal sample  : unsigned(7 downto 0)            := (others => '0');
    signal pwm_out : std_logic                       := '0';

begin

    -- sample counter increments on clock that wraps every 2**CNT_BITS clocks
    -- tick is registered (set one count early) so it is one fitter input
    -- instead of a 12-bit compare copied into every equation
    counter: process(CLK)
    begin
        if rising_edge(CLK) then
            cnt <= cnt + 1;
            if cnt = CNT_MAX - 1 then
                tick <= '1';
            else
                tick <= '0';
            end if;
        end if;
    end process counter;

    -- sync switches (active high) b0 = sw4 ... b3 = sw1
    sync_switches: process(CLK)
    begin
        if rising_edge(CLK) then
            pressed <= SW1 & SW2 & SW3 & SW4;
        end if;
    end process sync_switches;

    -- switch to play next however sw4 has priority
    sel <= "00" when pressed(0) = '1' else
           "01" when pressed(1) = '1' else
           "10" when pressed(2) = '1' else
           "11";

    -- table index: new switch when idle, playing message otherwise
    idx <= sel when state = IDLE else msg;

    -- message start address lookup table
    with idx select msg_start <=
        "00" & x"0000" when "00",       -- sw4: 0x40000
        "00" & x"8000" when "01",       -- sw3: 0x48000
        "01" & x"8000" when "10",       -- sw2: 0x58000
        "11" & x"C000" when others;     -- sw1: 0x7C000

    -- message end address lookup table 
    with idx select msg_end <=
        "00" & x"8000" when "00",       -- sw4: 0x48000
        "01" & x"8000" when "01",       -- sw3: 0x58000
        "11" & x"C000" when "10",       -- sw2: 0x7C000
        "00" & x"0000" when others;     -- sw1: 0x80000 

    -- registered end-of-message flag, addr only changes on ticks so it is
    -- always valid by the next tick
    end_check: process(CLK)
    begin
        if rising_edge(CLK) then
            if addr = msg_end then
                at_end <= '1';
            else
                at_end <= '0';
            end if;
        end if;
    end process end_check;

    -- player fsm that shoudl only acts on ticks
    control: process(CLK)
    begin
        if rising_edge(CLK) then
            if tick = '1' then

                if state = IDLE then
                    -- switch pressed -> load its message and first period is
                    -- silent while first byte is fetched bcuz no stored sample
                    if pressed /= "0000" then
                        msg    <= sel;
                        addr   <= msg_start;
                        sample <= (others => '0');
                        state  <= PLAY;
                    end if;

                elsif at_end = '1' then
                    -- end of message -> repeat if its switch is held, else idle
                    if pressed(to_integer(msg)) = '1' then
                        addr  <= msg_start;
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

    -- pwm: set at ramp = 0, clear at ramp = sample (high for sample clocks),
    -- low when idle; equality compares are much cheaper on a cpld than <
    pwm_gen: process(CLK)
    begin
        if rising_edge(CLK) then
            if state = IDLE or cnt(7 downto 0) = sample then
                pwm_out <= '0';
            elsif cnt(7 downto 0) = 0 then
                pwm_out <= '1';
            end if;
        end if;
    end process pwm_gen;

    -- outputs 
    AudioAddr   <= '1' & std_logic_vector(addr);
    AudioPWMOut <= pwm_out;

end architecture rtl;
