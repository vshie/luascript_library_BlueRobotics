-- ===== Manual Loiter/Hold Switch (arms on engage; OFF = software control) =====

-- ADC setup
local analog_in = analog:channel()
if not analog_in:set_pin(2) then
  gcs:send_text(0, "Invalid analog pin")
end

-- Thresholds and timings
local VOLTAGE_HIGH_THRESHOLD = 2.0
local VOLTAGE_LOW_THRESHOLD  = 1.0
local DELAY_TIME_MS          = 30000  -- 30s high before engaging
local LOW_DEBOUNCE_MS        = 1000   -- 1s debounce on LOW

-- Modes (as you confirmed)
local MODE_HOLD   = 5
local MODE_MANUAL = 0

-- Policy
local KILL_ON_SWITCH_OFF = true  -- leave false to allow full software control when switch is OFF

-- State
local high_voltage_detected = false
local latched_on            = false
local override_active       = false
local timer_start           = millis()
local last_set_mode         = -1
local last_set_time_ms      = 0
local low_since_ms          = nil
local control_owner         = "software" -- "switch" once we ARM+LOITER due to the switch

local function arm_vehicle()
  if not arming:is_armed() then
    if arming:arm() then
      gcs:send_text(6, "Vehicle armed")
      return true
    else
      gcs:send_text(6, "Arming failed")
      return false
    end
  end
  return true
end

local function disarm_vehicle()
  if arming:is_armed() then
    if arming:disarm() then
      gcs:send_text(6, "Vehicle disarmed")
    else
      gcs:send_text(6, "Disarm failed")
    end
  end
end

local function set_mode_safe(mode)
  if vehicle:get_mode() ~= mode then
    if vehicle:set_mode(mode) then
      last_set_mode = mode
      last_set_time_ms = millis()
      return true
    end
    return false
  end
  last_set_mode = mode
  last_set_time_ms = millis()
  return true
end

function loop()
  local v = analog_in:voltage_latest()
  local now = millis()
  local current_mode = vehicle:get_mode()

  if v == nil then
    return loop, 500
  end

  -- Treat mode mismatch as override ONLY if switch owns control (prevents false overrides on new cycles)
  if control_owner == "switch"
     and last_set_mode ~= -1
     and current_mode ~= last_set_mode
     and (now - last_set_time_ms) > 1500 then
    if not override_active then
      override_active = true
      control_owner   = "software"
      gcs:send_text(6, "Operator override detected; ignoring switch until OFF.")
    end
  end

  -- LOW handling with debounce
  if v < VOLTAGE_LOW_THRESHOLD then
    if not low_since_ms then low_since_ms = now end
    if (now - low_since_ms) >= LOW_DEBOUNCE_MS then
      high_voltage_detected = false
      latched_on            = false
      override_active       = false
      last_set_mode         = -1
      last_set_time_ms      = 0

      if KILL_ON_SWITCH_OFF and control_owner == "switch" then
        gcs:send_text(6, "Switch OFF: Manual + disarm.")
        set_mode_safe(MODE_MANUAL)
        disarm_vehicle()
      else
        gcs:send_text(6, "Switch OFF: software control (no auto-disarm).")
      end
      control_owner = "software"
    end
    return loop, 500
  else
    -- reset debounce timer whenever we're not in the LOW state
    low_since_ms = nil
  end

  -- Input is HIGH (or in the gap)
  if override_active then
    return loop, 500
  end

  if latched_on then
    return loop, 500
  end

  -- Not latched yet: qualify HIGH and start the 30s timer
  if not high_voltage_detected then
    if v >= VOLTAGE_HIGH_THRESHOLD then
      high_voltage_detected = true
      timer_start = now
      gcs:send_text(6, "Switch ON: starting 30s countdown to Loiter/Hold.")
    end
    return loop, 500
  end

  -- Timer running; after 30s of continuous HIGH, ARM + Loiter/Hold (5)
  if now - timer_start > DELAY_TIME_MS then
    gcs:send_text(6, "Engaging: ARM + Loiter/Hold.")
    if arm_vehicle() then
      if set_mode_safe(MODE_HOLD) then
        gcs:send_text(6, "Mode set to Loiter/Hold (5).")
        control_owner = "switch"
      else
        gcs:send_text(6, "Failed to set Loiter/Hold.")
      end
    end
    latched_on = true
    high_voltage_detected = false
  end

  return loop, 500
end

return loop, 500
