function is_upside_down()
    -- Check if the vehicle iss upside down
    local roll = math.deg(ahrs:get_roll())
    return math.abs(roll) > 90
end

local previously_flipped = FALSE
local MODE_HOLD = 4

local RC5 = rc:get_channel(5)
local currentmode 

function update()
    if not ahrs:initialised() then
        return update, 2000
    end
    if is_upside_down() then
        if not previously_upside_down then
            local mode_num = vehicle:get_mode()
            currentmode = mode_num
            gcs:send_text(0, "RC_override flip_over attempted!")
        end
        vehicle:set_mode(MODE_HOLD)
        RC5:set_override(1100)
    elseif not is_upside_down() and previously_upside_down then
        gcs:send_text(0, "RC_override flip_over cleared!")
        -- restore mode
        vehicle:set_mode(currentmode)
    else
        RC5:set_override(1500)
    end
    previously_upside_down = is_upside_down()
    return update, 1000
end

return update() -- run immediately before starting to reschedule