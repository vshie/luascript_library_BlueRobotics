-- ===== Drift Loiter for ArduRover / BlueBoat =====
-- Energy-saving alternative to Loiter. When triggered, the current position is
-- saved as the "center" and the boat is put in HOLD (motors off) to drift.
-- Once it drifts DRFT_RADIUS meters from the center, it switches to GUIDED and
-- drives back to the center, then returns to HOLD. This repeats until the
-- pilot selects any other mode (or the aux switch is turned off).
--
-- Triggers (either one works):
--   * Select LOITER mode while DRFT_ENABLE = 1 (the script takes over Loiter)
--   * An RC aux switch with RCx_OPTION = 300 (Scripting1) moved to HIGH
-- Selecting LOITER again while drifting re-centers on the current position.
-- If the script is not running, Loiter behaves like stock Loiter.

-- Rover mode numbers
local MODE_HOLD   = 4
local MODE_LOITER = 5
local MODE_GUIDED = 15

local AUX_FUNC_SCRIPTING1 = 300
local UPDATE_MS = 200
local EXIT_CONFIRM_COUNT = 3  -- consecutive samples outside radius before driving (GPS noise filter)
local MODE_SETTLE_MS = 1500   -- grace period after we change mode before checking for pilot override

-- ---------------------------------------------------------------------------
-- Parameters (appear in the GCS as DRFT_*)
-- ---------------------------------------------------------------------------
local PARAM_TABLE_KEY = 87
local PARAM_TABLE_PREFIX = "DRFT_"
assert(param:add_table(PARAM_TABLE_KEY, PARAM_TABLE_PREFIX, 6), "DRFT: could not add param table")

local function bind_add_param(name, idx, default_value)
  assert(param:add_param(PARAM_TABLE_KEY, idx, name, default_value), "DRFT: could not add " .. name)
  return Parameter(PARAM_TABLE_PREFIX .. name)
end

-- DRFT_ENABLE: 0 = disabled, 1 = take over LOITER mode
local DRFT_ENABLE    = bind_add_param("ENABLE", 1, 1)
-- DRFT_RADIUS: drift radius in meters; drive back once this far from center
local DRFT_RADIUS    = bind_add_param("RADIUS", 2, 20)
-- DRFT_ARRIVE: distance in meters from the return target at which motors stop
local DRFT_ARRIVE    = bind_add_param("ARRIVE", 3, 3)
-- DRFT_SPEED: return speed in m/s (0 = use WP_SPEED)
local DRFT_SPEED     = bind_add_param("SPEED", 4, 0)
-- DRFT_OVERSHOOT: 0..0.8, fraction of radius to aim past the center, on the
-- side opposite where the boat left the circle (i.e. upwind/up-current). This
-- makes each drift cover up to (1 + OVERSHOOT) * RADIUS, so motors run less often.
local DRFT_OVERSHOOT = bind_add_param("OVERSHOOT", 5, 0)
-- DRFT_DEBUG: 1 = send DRFT_DIST / DRFT_STATE named floats to the GCS
local DRFT_DEBUG     = bind_add_param("DEBUG", 6, 1)

local WP_RADIUS = Parameter("WP_RADIUS")

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local STATE_IDLE     = 0
local STATE_DRIFTING = 1
local STATE_RETURN   = 2

local state = STATE_IDLE
local center = nil          -- Location where drift loiter was triggered
local target = nil          -- Location we drive back to (center, or center + overshoot)
local target_sent = false
local expected_mode = -1    -- the mode this script last set
local mode_set_ms = 0
local exit_count = 0
local return_start_ms = 0
local cycle_count = 0
local last_mode = vehicle:get_mode()
local last_aux_pos = nil

local function send(sev, msg)
  gcs:send_text(sev, "DRFT: " .. msg)
end

local function set_mode(mode)
  expected_mode = mode
  mode_set_ms = millis()
  if vehicle:get_mode() == mode then
    return true
  end
  return vehicle:set_mode(mode)
end

local function radius_m()
  return math.max(DRFT_RADIUS:get(), 2)
end

-- arrival distance must be well inside the drift radius and no smaller than
-- WP_RADIUS, otherwise GUIDED may declare arrival first and start its own loiter
local function arrive_m()
  local arrive = math.max(DRFT_ARRIVE:get(), WP_RADIUS:get() or 0, 0.5)
  return math.min(arrive, radius_m() * 0.5)
end

local function stop(msg)
  if msg then send(6, msg) end
  state = STATE_IDLE
  center = nil
  target = nil
  expected_mode = -1
end

local function start_drift()
  state = STATE_DRIFTING
  exit_count = 0
  if not set_mode(MODE_HOLD) then
    send(4, "failed to set HOLD, retrying")
  end
end

local function start(reason)
  local loc = ahrs:get_location()
  if not loc then
    send(4, "no position, cannot start")
    return false
  end
  center = loc:copy()
  cycle_count = 0
  send(6, string.format("%s, R=%.0fm, motors off", reason, radius_m()))
  start_drift()
  return true
end

-- pick the return point: the center, optionally pushed past it on the side
-- opposite to where the boat left the circle
local function compute_target(loc)
  local tgt = center:copy()
  local overshoot = math.min(math.max(DRFT_OVERSHOOT:get(), 0), 0.8)
  if overshoot > 0 then
    local ne = center:get_distance_NE(loc)  -- vector center -> boat (m)
    local len = ne:length()
    if len > 0.1 then
      local d = overshoot * radius_m()
      tgt:offset(-ne:x() / len * d, -ne:y() / len * d)
    end
  end
  return tgt
end

local function start_return(loc)
  target = compute_target(loc)
  target_sent = false
  return_start_ms = millis()
  cycle_count = cycle_count + 1
  send(6, string.format("at %.0fm, returning (cycle %d)", loc:get_distance(center), cycle_count))
  if not set_mode(MODE_GUIDED) then
    send(4, "failed to set GUIDED, retrying")
  end
end

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
local function check_aux_switch()
  local ch = rc:find_channel_for_option(AUX_FUNC_SCRIPTING1)
  if not ch then return end
  local pos = ch:get_aux_switch_pos()
  if pos == last_aux_pos then return end
  local prev = last_aux_pos
  last_aux_pos = pos
  if prev == nil then return end  -- don't act on the initial switch position at boot
  if pos == 2 and state == STATE_IDLE then
    if arming:is_armed() then
      start("switch on")
    else
      send(4, "arm first")
    end
  elseif pos == 0 and state ~= STATE_IDLE then
    set_mode(MODE_HOLD)
    stop("switch off, stopped in HOLD")
  end
end

local function check_loiter_entry(mode)
  if mode == MODE_LOITER and last_mode ~= MODE_LOITER and DRFT_ENABLE:get() >= 1 and arming:is_armed() then
    start("LOITER")
  end
end

-- ---------------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------------
local function update()
  local now = millis()
  local mode = vehicle:get_mode()

  check_loiter_entry(mode)
  check_aux_switch()
  mode = vehicle:get_mode()
  last_mode = mode

  if state == STATE_IDLE then
    return update, UPDATE_MS
  end

  if not arming:is_armed() then
    stop("disarmed, stopped")
    return update, UPDATE_MS
  end

  -- pilot (or a failsafe) picked a different mode: hand control back
  if mode ~= expected_mode and (now - mode_set_ms) > MODE_SETTLE_MS then
    stop("mode changed, stopped")
    return update, UPDATE_MS
  end

  local loc = ahrs:get_location()
  if not loc then
    -- without a position we can't navigate; drift with motors off
    if state == STATE_RETURN then
      send(4, "position lost, HOLD")
      start_drift()
    end
    return update, UPDATE_MS
  end

  local dist = loc:get_distance(center)

  if state == STATE_DRIFTING then
    if mode ~= MODE_HOLD then
      set_mode(MODE_HOLD)  -- retry until HOLD is active
    end
    if dist > radius_m() then
      exit_count = exit_count + 1
      if exit_count >= EXIT_CONFIRM_COUNT then
        start_return(loc)
      end
    else
      exit_count = 0
    end

  elseif state == STATE_RETURN then
    if mode ~= MODE_GUIDED then
      set_mode(MODE_GUIDED)  -- retry until GUIDED is active
    elseif not target_sent then
      if vehicle:set_target_location(target) then
        target_sent = true
        if DRFT_SPEED:get() > 0 then
          vehicle:set_desired_speed(DRFT_SPEED:get())
        end
      end
    end
    if target_sent and loc:get_distance(target) <= arrive_m() then
      send(6, string.format("arrived in %.0fs, motors off", (now - return_start_ms) * 0.001))
      start_drift()
    end
  end

  if DRFT_DEBUG:get() >= 1 then
    gcs:send_named_float("DRFT_DIST", dist)
    gcs:send_named_float("DRFT_STATE", state)
  end
  logger:write("DRFT", "State,Dist,Cycle", "BfH", state, dist, cycle_count)

  return update, UPDATE_MS
end

send(6, "drift loiter loaded")
return update, 1000
