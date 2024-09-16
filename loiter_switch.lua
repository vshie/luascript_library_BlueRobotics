local analog_in = analog:channel()
if not analog_in:set_pin(2) then -- Assuming pin 2 for ADC input
  gcs:send_text(0, "Invalid analog pin")
end

local VOLTAGE_HIGH_THRESHOLD = 2.0 -- Adjust this threshold as needed
local VOLTAGE_LOW_THRESHOLD = 1.0 -- Adjust this threshold as needed
local DELAY_TIME_MS = 30000 -- 30 seconds in milliseconds
local MODE_LOITER = 5 -- Loiter mode number
local MODE_MANUAL = 0 -- Manual mode number

local high_voltage_detected = false
local timer_start = millis()

function arm_vehicle()
    if not vehicle:armed() then
        if vehicle:arm() then
            gcs:send_text(6, "Vehicle armed successfully")
            return true
        else
            gcs:send_text(6, "Failed to arm vehicle")
            return false
        end
    end
    return true -- Already armed
end

function disarm_vehicle()
    if vehicle:armed() then
        if vehicle:disarm() then
            gcs:send_text(6, "Vehicle disarmed and set to manual mode")
        else
            gcs:send_text(6, "Failed to disarm vehicle")
        end
    end
end

function loop()
    local current_voltage = analog_in:voltage_latest()
    local current_time = millis()

    if not high_voltage_detected then
        if current_voltage > VOLTAGE_HIGH_THRESHOLD then
            gcs:send_text(6, "Switch on. Starting 30-second countdown to loiter mode.")
            high_voltage_detected = true
            timer_start = current_time
        end
    else
        if current_voltage < VOLTAGE_LOW_THRESHOLD then
            gcs:send_text(6, "Switch off. Switching to Manual mode and disarming.")
            vehicle:set_mode(MODE_MANUAL)
            disarm_vehicle()
            high_voltage_detected = false
        elseif current_time - timer_start > DELAY_TIME_MS then
            gcs:send_text(6, "Arming and switching to Loiter mode.")
            if arm_vehicle() then
                vehicle:set_mode(MODE_LOITER)
            end
            high_voltage_detected = false
        end
    end
    
    return loop, 1000 -- Check every second
end

return loop, 1000