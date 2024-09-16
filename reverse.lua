local RC6 = rc:get_channel(6) --Jetski scoop control channel

local CONTROL_OUTPUT_THROTTLE = 3

function update()  
    if vehicle:get_control_output(CONTROL_OUTPUT_THROTTLE) < 0 then --"if desired speed/throttle value negative"
        RC6:set_override(2000)
    else
        RC6:set_override(1000)
    end
end
return update, 50