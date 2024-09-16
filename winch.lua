function extract_winch_points()
   local total = mission:num_commands()
   local winch_points = {}
   for x=0, total-1 do
       -- we should be checking for a specific code. QGC seems to support 206 for camera trigget, but it is weird.
       -- this code will run on every regular waypoint(16). we could also do a whitelist instead
       if mission:get_item(x):command() == 16 then
          table.insert(winch_points, x)
       end
   end
   gcs:send_text(0,"waypoints: " .. #winch_points .. "/" .. total)
   return winch_points
end

--  if mission is running or paused
function mission_is_running()
    if (mission:get_current_nav_index() > 0) then
            return true
        else
            return false
    end
end

function loop()
    if mission_is_running() then
        handle_winch()
    else
        SRV_Channels:set_output_pwm_chan(winch_channel, PWM_STOP)
    end
    return loop, 100
end

-- states
STANDINGBY = 0
WAITING_FOR_WAYPOINT = 1
LOWERING = 2
POST_LOWER_WAIT = 3
RAISING = 4


LOWERING_TIME_S = 30
RAISING_TIME_S = 35
WAIT_TIME_LOITER_S = 5
WAIT_TIME_BOTTOM_S = 10

PWM_STOP = 1500
PWM_RAISE = 1340
PWM_LOWER = 1580

-- modes from
MODE_LOITER = 5
MODE_AUTO = 10

WINCH_SERVO = 5

-- from https://ardupilot.org/rover/docs/parameters.html#servo14-function-servo-output-function
WINCH_FUNCTION = 88


timer = 0
state = STANDINGBY

winch_channel = SRV_Channels:find_channel(WINCH_FUNCTION)
if winch_channel == nil then
    gcs:send_text(6, "Set a SERVO_FUNCTION to WINCH and try restart vehicle")
end


function waypoint_is_done()
    current_index = mission:get_current_nav_index()
    for x=0, #done_waypoints do
        if done_waypoints[x] == current_index then
            return true
        end
    end
    return false
end

function current_waypoint_should_lower_winch()
    current_index = mission:get_current_nav_index()
    if waypoint_is_done() then
        return false
    end
    return true
    -- for x=0, #winch_waypoints do
    --     if winch_waypoints[x] == current_index then
    --         return true
    --     end
    -- end
    -- return false
end
local analog_in = analog:channel()
if not analog_in:set_pin(2) then -- typically 13 is the battery input
  gcs:send_text(0, "Invalid analog pin")
end
function payload_rise_detected()
    --gcs:send_text(6, analog_in:voltage_latest()) --print statement for debugging ADC / appropriate threshold
    if analog_in:voltage_latest() < 1 then
        return true
        else
            return false
        end
end

function handle_winch()
    if state == STANDINGBY then
        SRV_Channels:set_output_pwm_chan(winch_channel, PWM_STOP) --Do nothing unless at a waypoint that we should lower at
        if current_waypoint_should_lower_winch() then
            -- this switches to LOWERING
            gcs:send_text(6, "Switching to LOWERING")
            timer = millis()
            vehicle:set_mode(MODE_LOITER)
            if millis() > (timer + WAIT_TIME_LOITER_S * 1000) then    
                SRV_Channels:set_output_pwm_chan(winch_channel, PWM_LOWER)
                state = LOWERING
                timer = millis()
            end
        else
           -- gcs:send_text(0, "waypoint " .. mission:get_current_nav_index() .. "should not lower winch" )
        end
        table.insert(done_waypoints, mission:get_current_nav_index())
    end
    if state == LOWERING then
        if millis() > (timer + LOWERING_TIME_S * 1000) then
            -- this switches to POST_LOWER_WAIT
            SRV_Channels:set_output_pwm_chan(winch_channel, PWM_STOP)
            gcs:send_text(6, "LOWERED, Switching to WAIT")
            timer = millis()
            state = POST_LOWER_WAIT
            
        end
    end
    if state == POST_LOWER_WAIT then
        if millis() > (timer + WAIT_TIME_BOTTOM_S * 1000) then
            gcs:send_text(6, "WAIT done, Switching to RAISING")
            -- we are switching to RAISING
            state = RAISING
            SRV_Channels:set_output_pwm_chan(winch_channel, PWM_RAISE)
            timer = millis()
        end
    end
    if state == RAISING then
        if millis() > (timer + RAISING_TIME_S * 1000) or payload_rise_detected() then
            -- we are switching to standy mode, stop servo
            gcs:send_text(6, "RAISE done, switching to STANDBY")
            SRV_Channels:set_output_pwm_chan(winch_channel, PWM_STOP)
            state = STANDINGBY
            timer = 0
            vehicle:set_mode(MODE_AUTO)
        end
    end

end


winch_waypoints = {}
done_waypoints = {}

function main()
    winch_waypoints = extract_winch_points()
    return loop, 100
end


return main, 5000

