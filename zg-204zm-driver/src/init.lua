-- HOBEIAN ZG-204ZM PIR + 24GHz Radar Presence Sensor
-- Tuya EF00 datapoint driver: presence/motion state, illuminance, battery,
-- plus device-side settings (fading time, static detection distance/
-- sensitivity, motion detection mode/sensitivity, LED indicator) via
-- device Settings.
--
-- Same whitelabel family as HOBEIAN ZG-IR01 (see ../zgir01-driver): reports
-- modelID "ZG-204ZM" / manufacturer "HOBEIAN" directly (not a generic Tuya
-- _TZE200_ string), confirmed against the live paired device. Datapoint
-- layout ported from zigbee-herdsman-converters' ZG-204ZM definition
-- (src/devices/tuya.ts), which is shared with the AOYAN AY205Z whitelabel
-- of the same module.
--
-- Besides the Tuya DP protocol, this device also spontaneously reports the
-- standard Zigbee Illuminance Measurement cluster (0x0400) without needing
-- reporting configured (confirmed live: it arrives unprompted alongside
-- Tuya DP reports, and unlike DP 106 it also answers an on-demand read) --
-- handled here via st.zigbee.defaults as a second path feeding the same
-- illuminanceMeasurement capability.
--
-- The device also spontaneously reports a standard Power Configuration
-- (0x0001) battery cluster, but it bundles BatteryVoltage together with
-- BatteryPercentageRemaining in the same report, and st.zigbee.defaults logs
-- a WARN for the unhandled voltage attribute on every single one -- so DP
-- 121 (which reports the identical percentage and already answers refresh's
-- dataQuery) is kept as the only battery path here.

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local data_types = require "st.zigbee.data_types"
local zb_const = require "st.zigbee.constants"
local generic_body = require "st.zigbee.generic_body"
local read_attribute = require "st.zigbee.zcl.global_commands.read_attribute"
local log = require "log"

local IlluminanceMeasurement = clusters.IlluminanceMeasurement

local CLUSTER_TUYA = 0xEF00
local CLUSTER_BASIC = 0x0000
local SET_DATA = 0x00

local DP_TYPE_BOOL = "\x01"
local DP_TYPE_VALUE = "\x02"
local DP_TYPE_ENUM = "\x04"

local DP_PRESENCE = 1
local DP_STATIC_SENSITIVITY = 2
local DP_STATIC_DISTANCE = 4
local DP_MOTION_STATE = 101
local DP_FADING_TIME = 102
local DP_ILLUMINANCE = 106
local DP_INDICATOR = 107
local DP_BATTERY = 121
local DP_MOTION_MODE = 122
local DP_MOTION_SENSITIVITY = 123

local MOTION_STATE_ID = "acrosswatch58328.motionState"
local motion_state_cap = capabilities[MOTION_STATE_ID]
local MOTION_STATE_LABEL = {
  [0] = "없음",
  [1] = "큰 동작",
  [2] = "미세 동작",
  [3] = "정지(재실)",
}

local MOTION_MODE_TO_ENUM = { only_pir = 0, pir_and_radar = 1, only_radar = 2 }

local packet_id = 0

--------------------------------------------------

local function round(x)
  if x >= 0 then
    return math.floor(x + 0.5)
  else
    return -math.floor(-x + 0.5)
  end
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

-- Asks the MCU to report every datapoint it currently holds (cluster 0xEF00,
-- command 0x03, empty body) -- lets the app's "Refresh" pull the device's
-- actual current settings instead of only reflecting whatever was last set
-- from the app.
local function send_tuya_data_query(device)
  local zclh = zcl_messages.ZclHeader({cmd = data_types.ZCLCommandId(0x03)})
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
  local message_body = zcl_messages.ZclMessageBody({zcl_header = zclh, zcl_body = generic_body.GenericBody("")})
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

local function tuya_cluster_handler(driver, device, zb_rx)
  local rx = zb_rx.body.zcl_body.body_bytes
  local dp = string.byte(rx, 3)
  local fncmd_len = string.unpack(">I2", rx, 5)
  local payload = rx:sub(7, 6 + fncmd_len)

  if dp == DP_PRESENCE then
    local active = string.byte(payload, 1) ~= 0
    device:emit_event(active and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
  elseif dp == DP_MOTION_STATE then
    local raw = string.byte(payload, 1)
    local label = MOTION_STATE_LABEL[raw]
    if label then
      device:emit_event(motion_state_cap.motionState(label))
    else
      log.warn(string.format("ZG-204ZM: unknown motion_state value %s", tostring(raw)))
    end
  elseif dp == DP_ILLUMINANCE then
    local raw = string.unpack(">i4", payload)
    device:emit_event(capabilities.illuminanceMeasurement.illuminance(math.max(0, raw)))
  elseif dp == DP_BATTERY then
    local raw = string.unpack(">i4", payload)
    device:emit_event(capabilities.battery.battery(math.max(0, math.min(100, raw))))
  elseif dp == DP_STATIC_SENSITIVITY then
    log.info(string.format("ZG-204ZM: static_detection_sensitivity = %d", string.unpack(">i4", payload)))
  elseif dp == DP_STATIC_DISTANCE then
    log.info(string.format("ZG-204ZM: static_detection_distance = %.2fm", string.unpack(">i4", payload) / 100.0))
  elseif dp == DP_FADING_TIME then
    log.info(string.format("ZG-204ZM: fading_time = %ds", string.unpack(">i4", payload)))
  elseif dp == DP_INDICATOR then
    log.info(string.format("ZG-204ZM: indicator = %s", string.byte(payload, 1) ~= 0 and "on" or "off"))
  elseif dp == DP_MOTION_MODE then
    log.info(string.format("ZG-204ZM: motion_detection_mode = %d", string.byte(payload, 1)))
  elseif dp == DP_MOTION_SENSITIVITY then
    log.info(string.format("ZG-204ZM: motion_detection_sensitivity = %d", string.unpack(">i4", payload)))
  else
    log.info(string.format("ZG-204ZM: unhandled datapoint %d (len %d): %s", dp, fncmd_len, payload:gsub(".", function(c)
      return string.format("%02X ", string.byte(c))
    end)))
  end
end

--------------------------------------------------

local function do_configure(driver, device)
  configure_tuya_magic_packet(device)
  device:send(IlluminanceMeasurement.attributes.MeasuredValue:read(device))
  send_tuya_data_query(device)
end

local function refresh_handler(driver, device, command)
  device:send(IlluminanceMeasurement.attributes.MeasuredValue:read(device))
  send_tuya_data_query(device)
end

local function device_added(driver, device)
  device:emit_event(capabilities.motionSensor.motion.inactive())
  device.thread:call_with_delay(2, function()
    do_configure(driver, device)
  end)
end

local function info_changed(driver, device, event, args)
  local old = args.old_st_store.preferences
  local new = device.preferences

  if old.fadingTime ~= new.fadingTime then
    send_tuya_dp(device, DP_FADING_TIME, DP_TYPE_VALUE, string.pack(">i4", new.fadingTime))
  end
  if old.staticDistance ~= new.staticDistance then
    send_tuya_dp(device, DP_STATIC_DISTANCE, DP_TYPE_VALUE, string.pack(">i4", round(new.staticDistance * 100)))
  end
  if old.staticSensitivity ~= new.staticSensitivity then
    send_tuya_dp(device, DP_STATIC_SENSITIVITY, DP_TYPE_VALUE, string.pack(">i4", new.staticSensitivity))
  end
  if old.motionMode ~= new.motionMode then
    local v = MOTION_MODE_TO_ENUM[new.motionMode]
    if v then
      send_tuya_dp(device, DP_MOTION_MODE, DP_TYPE_ENUM, string.char(v))
    end
  end
  if old.motionSensitivity ~= new.motionSensitivity then
    send_tuya_dp(device, DP_MOTION_SENSITIVITY, DP_TYPE_VALUE, string.pack(">i4", new.motionSensitivity))
  end
  if old.indicator ~= new.indicator then
    send_tuya_dp(device, DP_INDICATOR, DP_TYPE_BOOL, new.indicator and "\x01" or "\x00")
  end
end

--------------------------------------------------

local zg_204zm_driver = {
  supported_capabilities = {
    capabilities.motionSensor,
    capabilities.illuminanceMeasurement,
    capabilities.battery,
    capabilities.refresh,
    motion_state_cap,
  },
  zigbee_handlers = {
    cluster = {
      [CLUSTER_TUYA] = {
        [0x01] = tuya_cluster_handler, -- dataResponse (reply to dataQuery)
        [0x02] = tuya_cluster_handler, -- dataReport (unsolicited)
        [0x05] = tuya_cluster_handler, -- activeStatusReportAlt (some firmwares use this instead)
        [0x06] = tuya_cluster_handler, -- activeStatusReport
      }
    },
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler,
    },
  },
  lifecycle_handlers = {
    added = device_added,
    infoChanged = info_changed,
    doConfigure = do_configure,
  },
  health_check = false,
}

defaults.register_for_default_handlers(zg_204zm_driver, {capabilities.illuminanceMeasurement})

local driver = ZigbeeDriver("zg-204zm", zg_204zm_driver)
driver:run()
