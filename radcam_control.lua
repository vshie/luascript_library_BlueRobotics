-- this script is a temporary solution to controlling ip cameras with ardupilot while the functionality is not done in cockpit

--before you run:

-- install cockpit v1.0.1 or newer
-- set the joystick functions:
-- script1, script2 - zoom
-- script3, script4 - focus
-- custom1 - toggle awb


-- SET YOUR CAMERA IP HERE
local cameraip = '192.168.2.10'


local cameraport = 80

local MANUAL_CONTROL = {}
MANUAL_CONTROL.id = 69
MANUAL_CONTROL.fields = {
  { "x",                  "<i2" },
  { "y",                  "<i2" },
  { "z",                  "<i2" },
  { "r",                  "<i2" },
  { "buttons",            "<I2" },
  { "target",             "<B" },
  { "buttons2",           "<I2" },
  { "enabled_extensions", "<B" },
  { "s",                  "<i2" },
  { "t",                  "<i2" },
  { "aux1",               "<i2" },
  { "aux2",               "<i2" },
  { "aux3",               "<i2" },
  { "aux4",               "<i2" },
  { "aux5",               "<i2" },
  { "aux6",               "<i2" },
}

local all_btn_params = {
  "BTN0_FUNCTION",
  "BTN1_FUNCTION",
  "BTN2_FUNCTION",
  "BTN3_FUNCTION",
  "BTN4_FUNCTION",
  "BTN5_FUNCTION",
  "BTN6_FUNCTION",
  "BTN7_FUNCTION",
  "BTN8_FUNCTION",
  "BTN9_FUNCTION",
  "BTN10_FUNCTION",
  "BTN11_FUNCTION",
  "BTN12_FUNCTION",
  "BTN13_FUNCTION",
  "BTN14_FUNCTION",
  "BTN15_FUNCTION",
  "BTN16_FUNCTION",
  "BTN17_FUNCTION",
  "BTN18_FUNCTION",
  "BTN19_FUNCTION",
  "BTN20_FUNCTION",
  "BTN21_FUNCTION",
  "BTN22_FUNCTION",
  "BTN23_FUNCTION",
  "BTN24_FUNCTION",
  "BTN25_FUNCTION",
  "BTN26_FUNCTION",
  "BTN27_FUNCTION",
  "BTN28_FUNCTION",
  "BTN29_FUNCTION",
  "BTN30_FUNCTION",
  "BTN31_FUNCTION"
}

local ZOOMIN_IN = 0
local ZOOMING_OUT = 1
local FOCUSING_IN = 2
local FOCUSING_OUT = 3
local IDLE = 4

local state = IDLE


function get_btn_for_function(func)
  for i, btn in ipairs(all_btn_params) do
    if (param:get(all_btn_params[i]) == func) then
      return i - 1
    end
  end
  return -1
end

local custom1 = get_btn_for_function(91)

gcs:send_text(6, "awb btn: " .. custom1)

function mavlink_decode_header(message)
  -- build up a map of the result
  local result = {}

  local read_marker = 3

  -- id the MAVLink version
  result.protocol_version, read_marker = string.unpack("<B", message, read_marker)
  if (result.protocol_version == 0xFE) then       -- mavlink 1
    result.protocol_version = 1
  elseif (result.protocol_version == 0XFD) then   --mavlink 2
    result.protocol_version = 2
  else
    error("Invalid magic byte")
  end

  _, read_marker = string.unpack("<B", message, read_marker)   -- payload is always the second byte

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
  for _, v in ipairs(message_map.fields) do
    if v[3] then
      result[v[1]] = {}
      for j = 1, v[3] do
        result[v[1]][j], offset = string.unpack(v[2], message, offset)
      end
    else
      result[v[1]], offset = string.unpack(v[2], message, offset)
    end
  end

  -- ignore the idea of a checksum

  return result
end

mavlink.init(1, 10)
mavlink.register_rx_msgid(MANUAL_CONTROL.id)

-- Function to send HTTP request
local function send_http_request(url, method, headers, body)
  local sock = Socket(0)

  if not sock:bind("0.0.0.0", 9988) then
    gcs:send_text(0, string.format("WebServer: failed to bind to TCP %u", 9988))
    sock.close(sock)
    return
  end

  if (sock:is_connected() == false) then
    if (not sock:connect(cameraip, cameraport)) then
      gcs:send_text(0, "Connection failed ")
      sock.close(sock)
      return
    end
  end
  local request = string.format(
    "%s %s HTTP/1.1\r\nHost: %s\r\n",
    method,
    url,
    cameraip
  )

  for k, v in pairs(headers) do
    request = request .. string.format("%s: %s\r\n", k, v)
  end

  request = request .. "Connection: close\r\n"

  if body then
    request = request .. string.format("Content-Length: %d\r\n\r\n%s", #body, body)
  else
    request = request .. "\r\n"
  end

  sock:send(request, #request)
  --sock.recv(1000)
  sock.close(sock)
  sock = nil
end


function zoom_in()
  if state ~= ZOOMIN_IN then
    state = ZOOMIN_IN
    send_http_request(
    '/action/cgi_action?user=admin&pwd=e10adc3949ba59abbe56e057f20f883e&action=setPtzControl&json={"speed_h":100,"speed_v":100,"channel":0,"ptz_cmd":9}',
      "GET", {}, nil)
    gcs:send_text(6, 'zoom in')
  end
end

function zoom_out()
  if state ~= ZOOMING_OUT then
    state = ZOOMING_OUT
    send_http_request(
    '/action/cgi_action?user=admin&pwd=e10adc3949ba59abbe56e057f20f883e&action=setPtzControl&json={"speed_h":100,"speed_v":100,"channel":0,"ptz_cmd":10}',
      "GET", {}, nil)
    gcs:send_text(6, 'zoom out')
  end
end

function focus_in()
  if state ~= FOCUSING_IN then
    state = FOCUSING_IN
    send_http_request(
    '/action/cgi_action?user=admin&pwd=e10adc3949ba59abbe56e057f20f883e&action=setPtzControl&json={"speed_h":100,"speed_v":100,"channel":0,"ptz_cmd":5}',
      "GET", {}, nil)
    gcs:send_text(6, 'focus +')
  end
end

function focus_out()
  if state ~= FOCUSING_OUT then
    state = FOCUSING_OUT
    send_http_request(
    '/action/cgi_action?user=admin&pwd=e10adc3949ba59abbe56e057f20f883e&action=setPtzControl&json={"speed_h":100,"speed_v":100,"channel":0,"ptz_cmd":6}',
      "GET", {}, nil)
    gcs:send_text(6, 'focus -')
  end
end


function update()
  if (sub:is_button_pressed(1)) then
    zoom_in()
  elseif (sub:is_button_pressed(2)) then
    zoom_out()
  elseif (sub:is_button_pressed(3)) then
    focus_out()
  elseif (sub:is_button_pressed(4)) then
    focus_in()
  elseif state ~= IDLE then
    state = IDLE
    gcs:send_text(6, 'stop')
    send_http_request('/action/cgi_action?user=admin&pwd=e10adc3949ba59abbe56e057f20f883e&action=setPtzControl&json={"speed_h":50,"speed_v":50,"channel":0,"ptz_cmd":21}', "GET", {}, nil)
  end
  local msg, _, timestamp_ms = mavlink.receive_chan()
  if msg then
    local result = mavlink_decode(msg)
    -- split into a list of 16 bits
    local buttons = {}
    for i = 0, 15 do
      buttons[i] = (result.buttons >> i) & 1
    end
    local buttons2 = {}
    for i = 0, 15 do
      buttons2[i] = (result.buttons2 >> i) & 1
    end

    local custom1_pressed = false

    if custom1 <= 16 and buttons[custom1] == 1 then
      custom1_pressed = true
    elseif buttons2[custom1 - 16] == 1 then
      custom1_pressed = true
    end
    -- gcs:send_text(0, "buttons2: " .. result.buttons2 .. " custom1: " .. buttons2[custom1 - 16])
    if custom1_pressed then
      gcs:send_text(6, "Auto white balance")
      send_http_request(
      '/action/cgi_action?user=admin&pwd=e10adc3949ba59abbe56e057f20f883e&action=setImageAdjustmentEx&json={"onceAWB":1}',
        "GET", {}, nil)
    end
  end
  return update, 200
end

-- step 1
zoom_out()

--send_ptz_request(100, 100, 9) -- 9 is zoom in
return update, 15000
