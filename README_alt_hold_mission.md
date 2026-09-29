# ArduSub Altitude Hold Mission Script

## Overview

This Lua script demonstrates a comprehensive state machine for ArduSub operations triggered when the vehicle enters `ALT_HOLD` mode. The script performs a sequence of actions including depth control, yaw control, lighting, and simulated pilot input.

## Educational Features

- **Modular State Machine Design**: Each action is encapsulated in its own state for clarity and maintainability
- **Comprehensive Error Handling**: Robust error checking and status reporting throughout
- **Detailed Logging**: Extensive status messages for debugging and monitoring
- **ArduPilot API Best Practices**: Demonstrates proper usage of ArduPilot's Lua scripting API
- **RC Channel Control Examples**: Shows how to control servos and RC channels programmatically

## Mission Sequence

When the vehicle enters `ALT_HOLD` mode, the script executes the following sequence:

1. **Depth Control**: Commands autopilot to dive to 1.5 meters using `vehicle:set_target_location()`
2. **Yaw Control**: Commands autopilot to orient north using `vehicle:set_target_attitude()`
3. **Turn On Lights**: Activates RC9 lights to 50% brightness
4. **Forward Movement**: Simulates pilot input to drive forward at 30% throttle for 3 seconds
5. **Stop Movement**: Returns all movement controls to neutral
6. **Disarm and Turn Off Lights**: Safely disarms the vehicle and turns off lights

## Prerequisites

### Vehicle Configuration

1. **Enable Lua Scripting**:
   ```
   SCR_ENABLE = 1
   ```

2. **RC Channel Setup**:
   - RC9: Configure for lights (`SERVO9_FUNCTION = 33`)
   - RC3: Forward/backward movement
   - RC4: Left/right movement  
   - RC5: Up/down movement
   - RC6: Yaw control

3. **Script Installation**:
   - Place `alt_hold_mission.lua` in the `/scripts/` directory on the vehicle's SD card
   - Restart the vehicle or reload scripts

### Safety Requirements

- Vehicle must be armed before entering `ALT_HOLD` mode
- Test in a safe, controlled environment first
- Ensure adequate water depth for the 1.5m target depth
- Have manual override capability ready

## Configuration

The script includes easily adjustable parameters at the top of the file:

```lua
-- Mission parameters - easily adjustable for different scenarios
local TARGET_DEPTH_M = 1.5          -- Target depth in meters
local LIGHT_BRIGHTNESS_PWM = 1500   -- 50% brightness (1500 = neutral, 1100-1900 range)
local FORWARD_THROTTLE_PCT = 30     -- Forward throttle percentage
local MOVE_DURATION_MS = 3000       -- Duration to move forward (3 seconds)
```

## State Machine Architecture

The script uses a state machine pattern with the following states:

- `WAIT_FOR_ALT_HOLD`: Monitors for vehicle mode change
- `SET_TARGET_DEPTH`: Commands depth control
- `SET_YAW_NORTH`: Sets heading to north
- `TURN_ON_LIGHTS`: Controls lighting system
- `MOVE_FORWARD`: Simulates pilot input
- `STOP_MOVEMENT`: Returns controls to neutral
- `DISARM_AND_TURN_OFF_LIGHTS`: Safe shutdown
- `MISSION_COMPLETE`: Mission finished
- `ERROR_STATE`: Error handling

## Key Learning Points

### 1. ArduPilot API Usage

```lua
-- Mode checking
vehicle:get_mode() == MODE_ALT_HOLD

-- Direct autopilot control (equivalent to pymavlink)
vehicle:set_target_location(target_location)  -- For depth control
vehicle:set_target_attitude(roll, pitch, yaw) -- For attitude control

-- RC Channel control for lights and movement
SRV_Channels:set_output_pwm(RC_CHANNEL_LIGHTS, pwm_value)

-- Arming/disarming
arming:is_armed()
arming:disarm()
```

### 1.1 Comparison with pymavlink

**pymavlink approach (external control):**
```python
# Direct MAVLink commands
master.mav.set_position_target_global_int_send(..., alt=depth, ...)
master.mav.set_attitude_target_send(..., QuaternionBase([...]), ...)
```

**ArduPilot Lua approach (internal control):**
```lua
-- Direct autopilot control (equivalent functionality)
vehicle:set_target_location(target_location)  -- Same as pymavlink position control
vehicle:set_target_attitude(roll, pitch, yaw) -- Same as pymavlink attitude control
```

**Key Similarities:**
- **Both approaches**: Use direct autopilot commands for precise control
- **Both approaches**: Support position and attitude control
- **Both approaches**: Provide equivalent functionality for depth and yaw control
- **ArduPilot Lua**: Integrated with ArduPilot's control system
- **pymavlink**: External application with full MAVLink access

### 2. RC Channel Control

```lua
-- Set PWM values for RC channels
SRV_Channels:set_output_pwm(channel, pwm_value)

-- Get current PWM values
SRV_Channels:get_output_pwm(channel)
```

### 3. Status Messaging

```lua
-- Send messages to ground control station
gcs:send_text(severity_level, message)
-- Severity levels: 0=EMERGENCY, 1=ALERT, 2=CRITICAL, 3=ERROR, 4=WARNING, 5=NOTICE, 6=INFO, 7=DEBUG
```

### 4. Timing Control

```lua
-- Get current time
millis()

-- Calculate elapsed time
local elapsed = current_time - start_time
```

## Error Handling

The script includes comprehensive error handling:

- **State Validation**: Each state checks for successful completion before proceeding
- **Timeout Protection**: Prevents infinite loops in state transitions
- **Status Reporting**: Detailed error messages sent to ground control
- **Safe Fallback**: Error state provides graceful degradation

## Monitoring and Debugging

### Ground Control Station Messages

The script sends status messages with different severity levels:

- **INFO (6)**: Normal operation updates
- **WARNING (3)**: Non-critical issues
- **ERROR (4)**: Mission-stopping errors
- **SUCCESS (5)**: Mission completion

### Common Debug Messages

```
[AltHold Mission] ALT_HOLD mode detected! Starting mission sequence
[AltHold Mission] Setting target depth to 1.5 meters
[AltHold Mission] Setting yaw to north (0 degrees)
[AltHold Mission] Controlling lights: 50% brightness
[AltHold Mission] Simulating forward movement at 30% throttle
[AltHold Mission] Mission completed successfully in 8.5 seconds
```

## Customization Examples

### Change Target Depth

```lua
local TARGET_DEPTH_M = 3.0  -- Change to 3 meters
```

### Adjust Movement Duration

```lua
local MOVE_DURATION_MS = 5000  -- Change to 5 seconds
```

### Modify Light Brightness

```lua
local LIGHT_BRIGHTNESS_PWM = 1700  -- Brighter lights (70% brightness)
```

### Add New Actions

To add new actions, follow this pattern:

1. Add new state to `State` table
2. Create action function
3. Add state processing logic in `process_current_state()`
4. Update state transitions

## Troubleshooting

### Common Issues

1. **Script Not Starting**:
   - Verify `SCR_ENABLE = 1`
   - Check script is in correct directory
   - Restart vehicle after script installation

2. **Mode Not Detected**:
   - Ensure vehicle is in `ALT_HOLD` mode (mode 2)
   - Check mode switching is working properly

3. **RC Channels Not Responding**:
   - Verify channel assignments match your configuration
   - Check servo functions are set correctly
   - Test channels manually first

4. **Depth Control Issues**:
   - Ensure adequate water depth
   - Check depth sensor is working
   - Verify depth control is enabled

### Debug Mode

To enable more verbose logging, modify the status message calls:

```lua
-- Change from INFO to DEBUG level
gcs:send_text(7, "[AltHold Mission] " .. message)  -- DEBUG level
```

## Safety Considerations

- **Always test in safe environment first**
- **Have manual override ready**
- **Monitor vehicle status throughout mission**
- **Ensure adequate water depth for target depth**
- **Verify all RC channels are properly configured**
- **Test emergency procedures before deployment**

## Further Reading

- [ArduPilot Lua Scripting Documentation](https://ardupilot.org/copter/docs/common-lua-scripts.html)
- [ArduSub User Guide](https://ardupilot.org/sub/docs/user-guide/)
- [ArduPilot RC Input/Output](https://ardupilot.org/copter/docs/rc-input-output.html)
- [ArduPilot Servo Functions](https://ardupilot.org/copter/docs/servo-functions.html)

## License

This script is provided as an educational resource. Use at your own risk and always follow proper safety procedures when operating underwater vehicles.
