-- Link button to output servo - gamepad right trigger goes to neutral, left trigger goes to reverse, otherwise FWD signal sent (may want this to be neutral but could cause problems as positive throttle input (on that channel) leads to vehicle being in fwd "gear"

local MANUAL_CONTROL = {}
    MANUAL_CONTROL.id = 69
    MANUAL_CONTROL.fields = {
             { "x", "<i2" },
             { "y", "<i2" },
             { "z", "<i2" },
             { "r", "<i2" },
             { "buttons", "<I2" },
             { "target", "<B" },
             }

function mavlink_decode_header(message)
  -- build up a map of the result
  local result = {}

  local read_marker = 3

  -- id the MAVLink version
  result.protocol_version, read_marker = string.unpack("<B", message, read_marker)
  if (result.protocol_version == 0xFE) then -- mavlink 1
    result.protocol_version = 1
  elseif (result.protocol_version == 0XFD) then --mavlink 2
    result.protocol_version = 2
  else
    error("Invalid magic byte")
  end

  _, read_marker = string.unpack("<B", message, read_marker) -- payload is always the second byte

  -- strip the incompat/compat flags
  result.incompat_flags, result.compat_flags, read_marker = string.unpack("<BB", message, read_marker)

  -- fetch seq/sysid/compid
  result.seq, result.sysid, result.compid, read_marker = string.unpack("<BBB", message, read_marker)

  -- fetch the message id
  result.msgid, read_marker = string.unpack("<I3", message, read_marker)

  return result, read_marker
end


function mavlink_decode(message)
  local result, offset = mavlink_decode_header(message)
  local message_map = MANUAL_CONTROL
  if not message_map then
    -- we don't know how to decode this message, bail on it
    return nil
  end

  -- map all the fields out
  for _,v in ipairs(message_map.fields) do
    if v[3] then
      result[v[1]] = {}
      for j=1,v[3] do
        result[v[1]][j], offset = string.unpack(v[2], message, offset)
      end
    else
      result[v[1]], offset = string.unpack(v[2], message, offset)
    end
  end

  -- ignore the idea of a checksum

  return result;
end


mavlink.init(1, 10)
mavlink.register_rx_msgid(MANUAL_CONTROL.id)

local RC4 = rc:get_channel(4)

function update()   
    local msg, _, timestamp_ms = mavlink.receive_chan()
    if msg then
        local result = mavlink_decode(msg)
        -- split into a list of 16 bits
        local buttons = {}
        for i = 5, 15 do 
            buttons[i] = (result.buttons >> i) & 1
        end 
        -- uncomment this line to print all button states
        -- gcs:send_text(0, "buts: " .. result.buttons)
        -- change x in  buttons[x] to the corresponding button numbr in qgc
        
        if buttons[0] == 1 then --determine button for right trigger
            RC4:set_override(1100)
        if buttons[0] == 1 then --determine button for right trigger
            RC4:set_override(1500)
        else
            RC4:set_override(2000)
        end
    end
    return update, 100
end

return update()