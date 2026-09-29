-- Generic survey pattern mission using GUIDED mode with depth and heading control
local SUB_MODE_GUIDED = 4
local TARGET_DEPTH = -0.5    -- Target depth in meters (negative for NED frame)
local FORWARD_VELOCITY = 0.3 -- Forward velocity in m/s
local HEADING_TOLERANCE = 2  -- Heading tolerance in degrees to consider turn complete

-- ============================================================================
-- SURVEY PLAN CONFIGURATION
-- ============================================================================
-- Define your survey pattern here. Each transect defines:
--   length_ms: Duration in milliseconds for this transect
--   heading_offset: Heading change relative to previous heading (in degrees)
--                   OR absolute heading if heading_mode is "absolute"
--   heading_mode: "relative" (offset from previous), "absolute" (degrees 0-360),
--                 or "initial_relative" (offset from initial heading)
--   forward_velocity: (OPTIONAL) Forward velocity in m/s for this transect.
--                     If not specified, uses FORWARD_VELOCITY default value.
--
-- Examples:
--   Relative Box pattern (4 sides, 90deg turns):
--     {{5000, 0, "initial_relative"}, {5000, -90, "relative"}, {5000, -90, "relative"}, {5000, -90, "relative"}}
--
--   Spiral outward (increasing length, constant turn):
--     {{3000, 0, "initial_relative"}, {4000, -90, "relative"}, {5000, -90, "relative"}, {6000, -90, "relative"}}
--
--   Grid pattern with varying speeds:
--     {{length_ms=5000, heading_offset=0, heading_mode="absolute", forward_velocity=0.2},
--      {length_ms=5000, heading_offset=90, heading_mode="absolute", forward_velocity=0.4}}
-- ============================================================================

local SURVEY_PLAN = {
    -- Snake/Lawn mowing pattern
    {length_ms = 30000, heading_offset = 0, heading_mode = "initial_relative", forward_velocity = 0.3},  -- Forward 30s at initial heading
    {length_ms = 5000, heading_offset = -90, heading_mode = "relative", forward_velocity = 0.3},         -- Turn left 90, drive 5s
    {length_ms = 30000, heading_offset = -90, heading_mode = "relative", forward_velocity = 0.3},         -- Turn left 90, back 30s
    {length_ms = 5000, heading_offset = 90, heading_mode = "relative", forward_velocity = 0.3},          -- Turn right 90, drive 5s
    {length_ms = 30000, heading_offset = 90, heading_mode = "relative", forward_velocity = 0.3},          -- Turn right 90, forward 30s
}

-- ============================================================================
-- STATE MACHINE
-- ============================================================================

-- Generic states (only 4 needed!)
local STATE_IDLE = 0
local STATE_DRIVING = 1      -- Executing a transect
local STATE_TURNING = 2      -- Turning to next transect heading
local STATE_COMPLETE = 3     -- Survey complete

-- State machine variables
local current_state = STATE_IDLE
local state_start_time = 0
local initial_heading = 0    -- Heading when GUIDED mode was entered
local current_transect_index = 0  -- Index into SURVEY_PLAN
local current_heading = 0    -- Current heading being used
local target_turn_heading = 0  -- Target heading for turn state

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Check if vehicle is armed
local function is_vehicle_armed()
    return arming:is_armed()
end

-- Check if vehicle is in GUIDED mode
local function is_in_guided_mode()
    return vehicle:get_mode() == SUB_MODE_GUIDED
end

-- Depth control using P controller
local function control_depth(target_depth)
    local P_gain = 0.5
    local error = target_depth - baro:get_altitude()
    local output = -error * P_gain
    return output
end

-- Move forward/lateral at given depth and heading
local function move_front_lateral_depth_yaw(front, lateral, depth, heading_deg)
    local target_vel = Vector3f()
    target_vel:x(front)
    target_vel:y(lateral)
    
    local z_output = control_depth(depth)
    target_vel:z(z_output)
    
    vehicle:set_target_velocity_NED(target_vel)
    vehicle:set_target_angle_and_climbrate(0, 0, heading_deg, -z_output, false, 0)
end

-- Calculate heading error accounting for wrap-around at 360/0
local function heading_error(current_deg, target_deg)
    local error = target_deg - current_deg
    -- Normalize error to [-180, 180]
    while error > 180 do
        error = error - 360
    end
    while error < -180 do
        error = error + 360
    end
    return math.abs(error)
end

-- Check if vehicle has reached target heading within tolerance
local function has_reached_heading(target_heading_deg)
    local current_heading = math.deg(ahrs:get_yaw_rad())
    local error = heading_error(current_heading, target_heading_deg)
    return error <= HEADING_TOLERANCE
end

-- Calculate heading for a transect based on its heading_mode
local function calculate_transect_heading(transect, previous_heading)
    local mode = transect.heading_mode
    local offset = transect.heading_offset
    
    if mode == "absolute" then
        return offset % 360
    elseif mode == "relative" then
        return (previous_heading + offset) % 360
    elseif mode == "initial_relative" then
        return (initial_heading + offset) % 360
    else
        -- Default to absolute if unknown mode
        return offset % 360
    end
end

-- Get current transect from survey plan
local function get_current_transect()
    if current_transect_index > 0 and current_transect_index <= #SURVEY_PLAN then
        return SURVEY_PLAN[current_transect_index]
    end
    return nil
end

-- Get forward velocity for a transect (defaults to FORWARD_VELOCITY if not specified)
local function get_transect_velocity(transect)
    if transect and transect.forward_velocity then
        return transect.forward_velocity
    end
    return FORWARD_VELOCITY
end

-- Transition to next state
local function transition_to_state(new_state, message)
    current_state = new_state
    state_start_time = millis()
    if message then
        gcs:send_text(6, message)  -- 6 = INFO level
    end
end

-- ============================================================================
-- MAIN UPDATE LOOP
-- ============================================================================

function update()
    -- Check if AHRS is initialized
    if not ahrs:initialised() then
        return update, 200
    end
    
    -- Check if vehicle is armed and in GUIDED mode
    if not (is_vehicle_armed() and is_in_guided_mode()) then
        -- Reset to idle if not armed or not in GUIDED
        if current_state ~= STATE_IDLE then
            current_transect_index = 0
            transition_to_state(STATE_IDLE, "Waiting for armed and GUIDED mode")
        end
        return update, 20
    end
    
    -- State machine logic
    if current_state == STATE_IDLE then
        -- Initialize survey: capture initial heading and start first transect
        initial_heading = math.deg(ahrs:get_yaw_rad())
        current_transect_index = 1
        local transect = get_current_transect()
        if transect then
            current_heading = calculate_transect_heading(transect, initial_heading)
            transition_to_state(STATE_DRIVING, string.format("Survey: Starting transect %d", current_transect_index))
        else
            transition_to_state(STATE_COMPLETE, "Survey plan is empty")
        end
        
    elseif current_state == STATE_DRIVING then
        -- Execute current transect
        local transect = get_current_transect()
        if not transect then
            transition_to_state(STATE_COMPLETE, "Survey complete")
        else
            local elapsed_time = millis() - state_start_time
            local transect_velocity = get_transect_velocity(transect)
            move_front_lateral_depth_yaw(transect_velocity, 0, TARGET_DEPTH, current_heading)
            
            if elapsed_time >= transect.length_ms then
                -- Transect complete, check if there's another one
                if current_transect_index < #SURVEY_PLAN then
                    -- Move to next transect and calculate its heading
                    current_transect_index = current_transect_index + 1
                    local next_transect = get_current_transect()
                    if next_transect then
                        target_turn_heading = calculate_transect_heading(next_transect, current_heading)
                        transition_to_state(STATE_TURNING, string.format("Survey: Turning for transect %d", current_transect_index))
                    else
                        transition_to_state(STATE_COMPLETE, "Survey complete")
                    end
                else
                    -- All transects complete
                    transition_to_state(STATE_COMPLETE, "Survey complete")
                end
            end
        end
        
    elseif current_state == STATE_TURNING then
        -- Stop and turn to next transect heading
        move_front_lateral_depth_yaw(0, 0, TARGET_DEPTH, target_turn_heading)
        
        if has_reached_heading(target_turn_heading) then
            -- Turn complete, update current heading and start driving
            current_heading = target_turn_heading
            transition_to_state(STATE_DRIVING, string.format("Survey: Starting transect %d", current_transect_index))
        end
        
    elseif current_state == STATE_COMPLETE then
        -- Stop movement and maintain depth
        move_front_lateral_depth_yaw(0, 0, TARGET_DEPTH, current_heading)
    end
    
    return update, 20
end

return update()
