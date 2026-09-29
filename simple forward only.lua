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
local FORWARD_DRIVE_TIME_MS = 3000  -- Time in milliseconds to drive forward

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
local time=0
function update()
    if is_vehicle_armed() and is_in_alt_hold_mode() then
        if time == 0 then
            gcs:send_text(0, "going f")
            time = millis()
        end
        RCFORWARD:set_override(1900)
    end
    if  millis() - time > FORWARD_DRIVE_TIME_MS then
        if is_vehicle_armed() then
                gcs:send_text(0, "stop")
                disarm_vehicle()
            end
        time = 0
    end
    return update, 20
end
return update()