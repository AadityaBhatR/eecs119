------------------------------------------------------------------------------
-- jtag.vhd
--
-- description:
--   jtag tap controller. state machine is a copy of the tap diagram,
--   next state only depends on TMS. 32 bit DR and 7 bit IR shift in on TDI
--   msb first while in the shift states, TDO is the msb of whichever
--   register's column we're in
--
-- inputs:
--   TCK  - jtag clock
--   TMS  - state manager input
--   TDI  - serial data in
--   TRST - state reset (active high, only resets the state, not the regs)
--
-- outputs:
--   TDO  - serial data out
--
-- edits:
--   11/13/26  aadi  started it, states + skeleton
--   11/14/26  aadi  filled out all the states, added DR/IR, fixed TDO and
--                   TRST so it passes the tb, renamed to TAPController
--   11/14/26  aadi  added this header
------------------------------------------------------------------------------

library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

entity TAPController is
    port(
        TCK     : in std_logic; -- jtag clock
        TMS     : in std_logic; -- state manager input
        TDI     : in std_logic; -- serial data in
        TRST    : in std_logic; -- state reset

        TDO     : out std_logic -- serial data out

    );
end entity TAPController;


architecture behavioral of TAPController is
    type state_t is (test_logic_reset,run_test_idle,select_DR_scan,
                    select_IR_scan,capture_DR,capture_IR, shift_DR,
                    shift_IR, exit_1_DR, exit_1_IR, pause_DR, pause_IR,
                    exit_2_DR, exit_2_IR, update_DR, update_IR);
    signal state        : state_t;      -- driven just by state_update
    signal next_state   : state_t;      -- the actual flip flops

    signal DR           : std_logic_vector(31 downto 0);   -- data register
    signal IR           : std_logic_vector(6 downto 0);    -- instruction register

begin
    state_machine : process(TCK,TRST)
    begin
        if(TRST = '1') then                     -- reset 
            next_state <= test_logic_reset;     -- registers keep their contents
                                                -- just a state reset

        elsif(rising_edge(TCK)) then
            -- the registers act on the current state
            if(state = shift_DR) then
                DR <= DR(30 downto 0) & TDI;        -- MSB first
            elsif(state = shift_IR) then
                IR <= IR(5 downto 0) & TDI;         -- MSB first
            end if;

          
            case state is   -- states are dependant only on TMS
                            -- just carbon copy of diagram
                            -- for clarification reference jtag state 
                            -- machine diagram Glen gave us
                when test_logic_reset   => 
                    if(TMS = '1') then
                        next_state <= test_logic_reset;
                    else
                        next_state <= run_test_idle;
                    end if;
                when run_test_idle      =>
                    if(TMS = '1') then
                        next_state <= select_DR_scan;
                    else
                        next_state <= run_test_idle;
                    end if;
                when select_DR_scan     =>
                    if(TMS = '1') then
                        next_state <= select_IR_scan;
                    else
                        next_state <= capture_DR;
                    end if;
                when select_IR_scan     =>
                    if(TMS = '1') then
                        next_state <= test_logic_reset;
                    else
                        next_state <= capture_IR;
                    end if;
                when capture_DR         =>
                    if(TMS = '1') then
                        next_state <= exit_1_DR;
                    else
                        next_state <= shift_DR;
                    end if;
                when capture_IR         =>
                    if(TMS = '1') then
                        next_state <= exit_1_IR;
                    else
                        next_state <= shift_IR;
                    end if;
                when shift_DR           =>
                    if(TMS = '1') then
                        next_state <= exit_1_DR;
                    else
                        next_state <= shift_DR;
                    end if;
                when shift_IR           =>
                    if(TMS = '1') then
                        next_state <= exit_1_IR;
                    else
                        next_state <= shift_IR;
                    end if;
                when exit_1_DR          =>
                    if(TMS = '1') then
                        next_state <= update_DR;
                    else
                        next_state <= pause_DR;
                    end if;
                when exit_1_IR          =>
                    if(TMS = '1') then
                        next_state <= update_IR;
                    else
                        next_state <= pause_IR;
                    end if;
                when pause_DR           =>
                    if(TMS = '1') then
                        next_state <= exit_2_DR;
                    else
                        next_state <= pause_DR;
                    end if;
                when pause_IR           =>
                    if(TMS = '1') then
                        next_state <= exit_2_IR;
                    else
                        next_state <= pause_IR;
                    end if;
                when exit_2_DR          =>
                    if(TMS = '1') then
                        next_state <= update_DR;
                    else
                        next_state <= shift_DR;
                    end if;
                when exit_2_IR          =>
                    if(TMS = '1') then
                        next_state <= update_IR;
                    else
                        next_state <= shift_IR;
                    end if;
                when update_DR          =>
                    if(TMS = '1') then
                        next_state <= select_DR_scan;
                    else
                        next_state <= run_test_idle;
                    end if;
                when update_IR          =>
                    if(TMS = '1') then
                        next_state <= select_DR_scan;
                    else
                        next_state <= run_test_idle;
                    end if;
                when others             =>
                    next_state <= test_logic_reset;
             end case;
        end if;
    end process; -- state_machine

    state_update : process(next_state)
    begin
        state <= next_state;
    end process; -- state_update

    -- TDO is MSB of the register for the column we're in
    TDO <= DR(31) when (state = capture_DR or state = shift_DR or
                        state = exit_1_DR  or state = pause_DR or
                        state = exit_2_DR  or state = update_DR) else
           IR(6)  when (state = capture_IR or state = shift_IR or
                        state = exit_1_IR  or state = pause_IR or
                        state = exit_2_IR  or state = update_IR) else
           '0';

end architecture behavioral;