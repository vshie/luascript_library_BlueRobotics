-- RC Channel assignments (adjust based on your vehicle configuration)
local RC_CHANNEL_FORWARD = 5        -- RC3 for forward/backward movement
local RC_CHANNEL_LATERAL = 6        -- RC4 for left/right movement
local RC_CHANNEL_VERTICAL = 3       -- RC5 for up/down movement
local RC_CHANNEL_YAW = 4           -- RC6 for yaw control

-- Get RC channel objects for override (equivalent to pymavlink rc_channels_override_send)
local RCFORWARD = rc:get_channel(RC_CHANNEL_FORWARD)  -- Forward/backward
local RCLATERAL = rc:get_channel(RC_CHANNEL_LATERAL)  -- Left/right
local RCVERTICAL = rc:get_channel(RC_CHANNEL_VERTICAL) -- Up/down
local RCYAW = rc:get_channel(RC_CHANNEL_YAW)      -- Yaw

local MODE_ALT_HOLD = 2 

-- Check if vehicle is armed
local function is_vehicle_armed()
    return arming:is_armed()
end

-- Check if vehicle is in ALT_HOLD mode
local function is_in_alt_hold_mode()
    return vehicle:get_mode() == MODE_ALT_HOLD
end

local function send_status(message, severity)
    severity = severity or 6  -- Default to INFO level
    gcs:send_text(severity, "" .. message)
end

local function disarm_vehicle()
    send_status("Disarming vehicle")
    
    if arming:disarm() then
        send_status("Vehicle disarmed successfully")
        return true
    else
        send_status("Failed to disarm vehicle", 4) -- ERROR level
        return false
    end
end
-- State machine for movement sequence
local time = 0
local PWM_NEUTRAL = 1500

function update()
    if is_vehicle_armed() and is_in_alt_hold_mode() then
        if time == 0 then
            time = millis()
            send_status("State: FORWARD")
        end
        
        local elapsed = millis() - time
        
        -- Forward: 0-3000ms
        if elapsed < 3000 then
            RCFORWARD:set_override(1900)
            RCLATERAL:set_override(PWM_NEUTRAL)
        
        -- Left: 3000-5000ms
        elseif elapsed < 5000 then
            RCFORWARD:set_override(PWM_NEUTRAL)
            RCLATERAL:set_override(1300)
        
        -- Reverse: 5000-7000ms
        elseif elapsed < 7000 then
            RCFORWARD:set_override(1100)
            RCLATERAL:set_override(PWM_NEUTRAL)
        
        -- Right: 7000-9000ms
        elseif elapsed < 9000 then
            RCFORWARD:set_override(PWM_NEUTRAL)
            RCLATERAL:set_override(1700)
        
        elseif elapsed > 9000 then
            disarm_vehicle()
            time = 0
            RCFORWARD:set_override(PWM_NEUTRAL)
            RCLATERAL:set_override(PWM_NEUTRAL)
            RCVERTICAL:set_override(PWM_NEUTRAL)
            RCYAW:set_override(PWM_NEUTRAL)

        end
    end

    return update, 20
end
return update()