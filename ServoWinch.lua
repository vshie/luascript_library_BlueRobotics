-- ServoWinch.lua - BlueBoat winch control script
-- Controls a servo winch on Navigator channel 9
-- Triggers when entering loiter mode, unwinds for specified rotations
-- Uses ADC to count rotations (0-3.3V per rotation)
-- increased SCHED_LOOP_RATE to 200Hz to support faster ADC sampling

-- Parameter table setup
PARAM_TABLE_KEY = 92
PARAM_TABLE_PREFIX = 'WINCH_'

-- Parameter binding helper functions
function bind_param(name)
    p = Parameter()
    assert(p:init(name), string.format('could not find %s parameter', name))
    return p
end

function bind_add_param(name, idx, default_value)
    assert(param:add_param(PARAM_TABLE_KEY, idx, name, default_value), string.format('could not add param %s', name))
    return bind_param(PARAM_TABLE_PREFIX .. name)
end

-- Add parameter table
assert(param:add_table(PARAM_TABLE_KEY, PARAM_TABLE_PREFIX, 32), 'could not add param table')

-- Add configurable parameters with defaults
target_rotations = bind_add_param('ROTATIONS', 1, 2)     -- Number of rotations to unwind
dwell_time_s = bind_add_param('DWELL_S', 2, 10)          -- Time to wait before winding back (seconds)
output_pin = bind_add_param('OUT_PIN', 3, 8)             -- PWM output pin/channel

-- PWM values for winch control
PWM_STOP = 1500      -- No motion
PWM_UNWIND = 1600    -- Unwind direction
PWM_WIND = 1400      -- Wind direction


-- Mode constants
MODE_LOITER = 5
MODE_AUTO = 10

-- State machine states
STANDINGBY = 0
DETECTING_LOITER = 1
UNWINDING = 2
DWELLING = 3
WINDING_BACK = 4
COMPLETED = 5

-- Initialize state and variables
state = STANDINGBY
rotation_count = 0
last_adc_voltage = 0
adc_rising_edge_count = 0
dwell_start_time = 0
wind_back_start_time = 0
cast_completed_in_loiter = false

-- Setup ADC for rotation counting
local analog_in = analog:channel()
if not analog_in:set_pin(3) then
    gcs:send_text(0, "ServoWinch: Invalid analog pin")
end

-- Function to detect rotation via ADC
function detect_rotation()
    local current_voltage = analog_in:voltage_latest()
    
    gcs:send_text(6, "ServoWinch: ADC voltage: " .. string.format("%.2f", current_voltage) .. "V")
    
    -- Detect vertical jumps in sawtooth wave (instant transitions)
    -- Look for large voltage changes that indicate vertical jumps
    local voltage_change = math.abs(current_voltage - last_adc_voltage)
    
    -- Detect vertical jump (large voltage change in one sample)
    if voltage_change > 2.0 then  -- Jump of more than 2V indicates vertical transition
        adc_rising_edge_count = adc_rising_edge_count + 1
        gcs:send_text(6, "ServoWinch: Rotation " .. adc_rising_edge_count .. " detected (jump: " .. string.format("%.2f", voltage_change) .. "V)")
        last_adc_voltage = current_voltage
        return true
    end
    
    last_adc_voltage = current_voltage
    return false
end

-- Function to check if vehicle is in loiter mode
function is_in_loiter_mode()
    return vehicle:get_mode() == MODE_LOITER
end

-- Function to check if vehicle was just switched to loiter mode
function just_entered_loiter()
    -- Only trigger if in loiter mode, in standby state, and haven't completed a cast yet
    return is_in_loiter_mode() and state == STANDINGBY and not cast_completed_in_loiter
end

-- Main winch control function
function handle_winch()
    if state == STANDINGBY then
        -- Stop winch and wait for loiter mode
        SRV_Channels:set_output_pwm_chan(tonumber(output_pin:get()), PWM_STOP)
        
        -- Reset cast completion flag if we're no longer in loiter mode
        if not is_in_loiter_mode() then
            cast_completed_in_loiter = false
        end
        
        if just_entered_loiter() then
            gcs:send_text(6, "ServoWinch: Loiter mode detected, starting unwind")
            state = DETECTING_LOITER
            rotation_count = 0
            adc_rising_edge_count = 0
            last_adc_voltage = analog_in:voltage_latest()
        end
        
    elseif state == DETECTING_LOITER then
        -- Start unwinding immediately since we already confirmed loiter mode
        gcs:send_text(6, "ServoWinch: Starting unwind for " .. target_rotations:get() .. " rotations")
        local pin_num = tonumber(tonumber(output_pin:get()))
        SRV_Channels:set_output_pwm_chan(pin_num, PWM_UNWIND)
        state = UNWINDING
        
    elseif state == UNWINDING then
        -- Check for rotations while unwinding
        detect_rotation()  -- This will update adc_rising_edge_count
        
        -- Check if we've reached target rotations
        if adc_rising_edge_count >= target_rotations:get() then
            gcs:send_text(6, "ServoWinch: Target rotations reached, starting dwell period")
            SRV_Channels:set_output_pwm_chan(tonumber(output_pin:get()), PWM_STOP)
            dwell_start_time = millis()
            state = DWELLING
        end
        
    elseif state == DWELLING then
        -- Wait for dwell time before winding back
        if millis() > (dwell_start_time + dwell_time_s:get() * 1000) then
            gcs:send_text(6, "ServoWinch: Dwell time complete, starting wind back")
            SRV_Channels:set_output_pwm_chan(tonumber(output_pin:get()), PWM_WIND)
            wind_back_start_time = millis()
            rotation_count = 0  -- Reset counter for wind back
            adc_rising_edge_count = 0
            state = WINDING_BACK
        end
        
    elseif state == WINDING_BACK then
        -- Check for rotations while winding back
        detect_rotation()  -- This will update adc_rising_edge_count
        
        -- Check if we've wound back the same number of rotations
        if adc_rising_edge_count >= target_rotations:get() then
            gcs:send_text(6, "ServoWinch: Wind back complete, operation finished")
            SRV_Channels:set_output_pwm_chan(tonumber(output_pin:get()), PWM_STOP)
            state = COMPLETED
        end
        
    elseif state == COMPLETED then
        -- Winch operation completed, return to standby
        SRV_Channels:set_output_pwm_chan(tonumber(output_pin:get()), PWM_STOP)
        gcs:send_text(6, "ServoWinch: Operation completed, returning to standby")
        cast_completed_in_loiter = true
        state = STANDINGBY
    end
end

-- Main loop function
function loop()
    --gcs:send_text(6, "ServoWinch: State = " .. state)
    handle_winch()
    return loop, 20  -- Run every 20ms (50Hz)
end

-- Initialize and start the script
function main()
    gcs:send_text(6, "ServoWinch: Starting script")
    return loop, 20
end

return main, 1000  -- Start after 1 second delay
