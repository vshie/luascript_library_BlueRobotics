local analog_in = analog:channel()
if not analog_in:set_pin(2) then -- typically 13 is the battery input
  gcs:send_text(0, "Invalid analog pin")
end
function payload_rise_detected()
    gcs:send_text(6, analog_in:voltage_latest())
    if analog_in:voltage_latest() < 2.8 then
        return true
        else
            return false
        end
end

function loop()
    if payload_rise_detected() then
        gcs:send_text(6, "Payload retracted")
    end
    return loop, 1000
end

return loop, 1000