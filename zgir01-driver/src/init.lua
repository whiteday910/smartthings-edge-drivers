-- HOBEIAN ZG-IR01 Smart IR Remote Switch
-- Tuya EF00 datapoint driver: 6 IR switch channels + temperature/humidity/battery
-- + per-channel IR code "study" (learn) triggers via device Settings.
--
-- This driver intentionally does NOT implement the Zosung raw IR code
-- (arbitrary code learn/send, e.g. SmartIR library import) feature. Each
-- switch channel's ON/OFF code is instead taught directly on the device via
-- the "study" datapoints (120-131): point the original remote at the
-- blaster and press the button while the matching Setting is set to learn.

local st_device = require "st.device"
local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local data_types = require "st.zigbee.data_types"
local zb_const = require "st.zigbee.constants"
local generic_body = require "st.zigbee.generic_body"
local read_attribute = require "st.zigbee.zcl.global_commands.read_attribute"
local log = require "log"

local CLUSTER_TUYA = 0xEF00
local CLUSTER_BASIC = 0x0000
local SET_DATA = 0x00

local DP_TYPE_BOOL = "\x01"
local DP_TYPE_VALUE = "\x02"
local DP_TYPE_ENUM = "\x04"

local DP_TEMPERATURE = 109
local DP_HUMIDITY = 110
local DP_TEMP_CALIBRATION = 107
local DP_HUMIDITY_CALIBRATION = 108
local DP_TEMP_UNIT = 111
local DP_BATTERY = 112

-- switch N -> [on-code study dp, off-code study dp]
local DP_LEARN = {
  [1] = {120, 121},
  [2] = {122, 123},
  [3] = {124, 125},
  [4] = {126, 127},
  [5] = {128, 129},
  [6] = {130, 131},
}

local packet_id = 0

--------------------------------------------------

local function round(x)
  if x >= 0 then
    return math.floor(x + 0.5)
  else
    return -math.floor(-x + 0.5)
  end
end

local function child_key(switch_num)
  return string.format("%02d", switch_num)
end

--------------------------------------------------

local function send_tuya_dp(device, dp, dp_type, data)
  local zclh = zcl_messages.ZclHeader({cmd = data_types.ZCLCommandId(SET_DATA)})
  zclh.frame_ctrl:set_cluster_specific()
  zclh.frame_ctrl:set_disable_default_response()
  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(CLUSTER_TUYA),
    zb_const.HA_PROFILE_ID,
    CLUSTER_TUYA
  )
  packet_id = (packet_id + 1) % 65536
  local payload_body = generic_body.GenericBody(
    string.pack(">I2", packet_id) .. string.char(dp) .. dp_type .. string.pack(">I2", #data) .. data
  )
  local message_body = zcl_messages.ZclMessageBody({zcl_header = zclh, zcl_body = payload_body})
  local send_message = messages.ZigbeeMessageTx({address_header = addrh, body = message_body})
  device:send(send_message)
end

local function configure_tuya_magic_packet(device)
  local zclh = zcl_messages.ZclHeader({cmd = data_types.ZCLCommandId(read_attribute.ReadAttribute.ID)})
  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(CLUSTER_BASIC),
    zb_const.HA_PROFILE_ID,
    CLUSTER_BASIC
  )
  local payload_body = read_attribute.ReadAttribute({0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xFFFE})
  local message_body = zcl_messages.ZclMessageBody({zcl_header = zclh, zcl_body = payload_body})
  local send_message = messages.ZigbeeMessageTx({address_header = addrh, body = message_body})
  device:send(send_message)
end

--------------------------------------------------

local function find_child(parent, key)
  return parent:get_child_by_parent_assigned_key(key)
end

local function create_child_devices(driver, device)
  for i = 2, 6 do
    local key = child_key(i)
    if device:get_child_by_parent_assigned_key(key) == nil then
      driver:try_create_device({
        type = "EDGE_CHILD",
        parent_assigned_child_key = key,
        label = device.label .. " " .. i,
        profile = "zg-ir01-child-switch",
        parent_device_id = device.id,
      })
    end
  end
end

local function emit_switch_state(device, switch_num, is_on)
  local state = is_on and capabilities.switch.switch.on() or capabilities.switch.switch.off()
  if switch_num == 1 then
    device:emit_event(state)
    return
  end
  local child = device:get_child_by_parent_assigned_key(child_key(switch_num))
  if child then
    child:emit_event(state)
  end
end

--------------------------------------------------

local function tuya_cluster_handler(driver, device, zb_rx)
  local rx = zb_rx.body.zcl_body.body_bytes
  local dp = string.byte(rx, 3)
  local fncmd_len = string.unpack(">I2", rx, 5)
  local payload = rx:sub(7, 6 + fncmd_len)

  if dp >= 1 and dp <= 6 then
    emit_switch_state(device, dp, string.byte(payload, 1) ~= 0)
  elseif dp == DP_TEMPERATURE then
    local raw = string.unpack(">i4", payload)
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = raw / 10.0, unit = "C"}))
  elseif dp == DP_HUMIDITY then
    local raw = string.unpack(">i4", payload)
    device:emit_event(capabilities.relativeHumidityMeasurement.humidity(raw))
  elseif dp == DP_BATTERY then
    local raw = string.unpack(">i4", payload)
    device:emit_event(capabilities.battery.battery(math.max(0, math.min(100, raw))))
  else
    log.debug(string.format("ZG-IR01: unhandled datapoint %d (len %d)", dp, fncmd_len))
  end
end

--------------------------------------------------

local function switch_command(driver, device, command, is_on)
  local target = device
  local dp = 1
  if device.network_type == st_device.NETWORK_TYPE_CHILD then
    dp = tonumber(device.parent_assigned_child_key)
    target = device:get_parent_device()
  end
  send_tuya_dp(target, dp, DP_TYPE_BOOL, is_on and "\x01" or "\x00")
end

local function switch_on(driver, device, command)
  switch_command(driver, device, command, true)
end

local function switch_off(driver, device, command)
  switch_command(driver, device, command, false)
end

--------------------------------------------------

local function do_configure(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_CHILD then return end
  configure_tuya_magic_packet(device)
end

local function device_added(driver, device)
  device:emit_event(capabilities.switch.switch.off())
  if device.network_type == st_device.NETWORK_TYPE_CHILD then return end
  create_child_devices(driver, device)
  device.thread:call_with_delay(2, function()
    do_configure(driver, device)
  end)
end

local function device_init(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_CHILD then return end
  device:set_find_child(find_child)
end

local function info_changed(driver, device, event, args)
  if device.network_type == st_device.NETWORK_TYPE_CHILD then return end
  local old = args.old_st_store.preferences
  local new = device.preferences

  if old.temperatureUnit ~= new.temperatureUnit then
    local v = (new.temperatureUnit == "fahrenheit") and 1 or 0
    send_tuya_dp(device, DP_TEMP_UNIT, DP_TYPE_ENUM, string.char(v))
  end
  if old.temperatureCalibration ~= new.temperatureCalibration then
    send_tuya_dp(device, DP_TEMP_CALIBRATION, DP_TYPE_VALUE, string.pack(">i4", round(new.temperatureCalibration * 10)))
  end
  if old.humidityCalibration ~= new.humidityCalibration then
    send_tuya_dp(device, DP_HUMIDITY_CALIBRATION, DP_TYPE_VALUE, string.pack(">i4", new.humidityCalibration))
  end

  for i = 1, 6 do
    local pref_name = "switch" .. i .. "Learn"
    if old[pref_name] ~= new[pref_name] then
      local dps = DP_LEARN[i]
      if new[pref_name] == "learn_on" then
        send_tuya_dp(device, dps[1], DP_TYPE_ENUM, "\x00")
      elseif new[pref_name] == "learn_off" then
        send_tuya_dp(device, dps[2], DP_TYPE_ENUM, "\x00")
      end
    end
  end
end

--------------------------------------------------

local zg_ir01_driver = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.temperatureMeasurement,
    capabilities.relativeHumidityMeasurement,
    capabilities.battery,
  },
  zigbee_handlers = {
    cluster = {
      [CLUSTER_TUYA] = {
        [0x01] = tuya_cluster_handler,
        [0x02] = tuya_cluster_handler,
      }
    },
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on,
      [capabilities.switch.commands.off.NAME] = switch_off,
    },
  },
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    infoChanged = info_changed,
    doConfigure = do_configure,
  },
  health_check = false,
}

local driver = ZigbeeDriver("zg-ir01", zg_ir01_driver)
driver:run()
