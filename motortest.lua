local analog_in = analog:channel()
if not analog_in:set_pin(2) then -- typically 13 is the battery input
  gcs:send_text(0, "Invalid analog pin")
end

WINCH_SERVO = 5

-- from https://ardupilot.org/rover/docs/parameters.html#servo14-function-servo-output-function
WINCH_FUNCTION = 88

winch_channel = SRV_Channels:find_channel(WINCH_FUNCTION)
if winch_channel == nil then
    gcs:send_text(6, "Set a SERVO_FUNCTION to WINCH and try restart vehicle")
end

SRV_Channels:set_output_pwm_chan(winch_channel, 1500)
function payload_rise_detected()
    gcs:send_text(6, analog_in:voltage_latest())
    if analog_in:voltage_latest() > 1 then
        SRV_Channels:set_output_pwm_chan(winch_channel, 1500)
        gcs:send_text(0,"running at 1700")
        return true
        else
            SRV_Channels:set_output_pwm_chan(winch_channel, 1500)
            return false
        end
    -- homework for Tony goes here
    -- adapt either code from the leak detection script or the adc examples to return true if the payload is retracted
end

function loop()
    if payload_rise_detected() then
        gcs:send_text(6, "Payload retracted")
    end
    return loop, 1000
end

return loop, 1000