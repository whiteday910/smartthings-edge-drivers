-- HOBEIAN ZG-IR01 Smart IR Remote Switch
-- Tuya EF00 datapoint driver: 6 IR switch channels + temperature/humidity/battery
-- + per-channel IR code "study" (learn), all on a single device.
--
-- The 6 switch channels are exposed as 6 *components* of one device ("main"
-- labeled 스위치 1, plus switch2..switch6) instead of separate child devices,
-- so everything lives on one device screen. Each component carries the switch
-- capability plus a custom acrosswatch58328.irSlotStudy capability that shows
-- the ON/OFF code registration state (datapoints 120-131 reports) and provides
-- push buttons to start learning each code, replacing the old
-- preference-based learn triggers.
--
-- This driver intentionally does NOT implement the Zosung raw IR code
-- (arbitrary code learn/send, e.g. SmartIR library import) feature. Each
-- switch channel's ON/OFF code is instead taught directly on the device via
-- the "study" datapoints (120-131): point the original remote at the
-- blaster and press the button while that slot is in study mode.

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
-- (interleaved layout and study enum values confirmed against the
-- therealdigitalkiwi/zha-zg-ir01 quirk: Study=0, Registered=1, Unregistered=2)
local DP_LEARN = {
  [1] = {120, 121},
  [2] = {122, 123},
  [3] = {124, 125},
  [4] = {126, 127},
  [5] = {128, 129},
  [6] = {130, 131},
}

local IR_SLOT_STUDY_ID = "acrosswatch58328.irSlotStudy"
local ir_slot_study = capabilities[IR_SLOT_STUDY_ID]

local STUDY_STATE_TEXT = {
  [0] = "학습 중",
  [1] = "저장됨",
  [2] = "없음",
}

local SWITCH_TO_COMPONENT = { "main", "switch2", "switch3", "switch4", "switch5", "switch6" }
local COMPONENT_TO_SWITCH = {}
for i, id in ipairs(SWITCH_TO_COMPONENT) do
  COMPONENT_TO_SWITCH[id] = i
end

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

local function emit_to_switch(device, switch_num, event)
  local component_id = SWITCH_TO_COMPONENT[switch_num]
  local component = component_id and device.profile.components[component_id]
  if component then
    device:emit_component_event(component, event)
  end
end

--------------------------------------------------

local function handle_dp(device, dp, payload)
  if dp >= 1 and dp <= 6 then
    local is_on = string.byte(payload, 1) ~= 0
    emit_to_switch(device, dp, is_on and capabilities.switch.switch.on() or capabilities.switch.switch.off())
  elseif dp == DP_TEMPERATURE then
    local raw = string.unpack(">i4", payload)
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = raw / 10.0, unit = "C"}))
  elseif dp == DP_HUMIDITY then
    local raw = string.unpack(">i4", payload)
    device:emit_event(capabilities.relativeHumidityMeasurement.humidity(raw))
  elseif dp == DP_BATTERY then
    local raw = string.unpack(">i4", payload)
    device:emit_event(capabilities.battery.battery(math.max(0, math.min(100, raw))))
  elseif dp >= 120 and dp <= 131 then
    local slot = dp - 120
    local switch_num = math.floor(slot / 2) + 1
    local is_on_code = (slot % 2) == 0
    local state_text = STUDY_STATE_TEXT[string.byte(payload, 1)]
    if state_text == nil then
      log.warn(string.format("ZG-IR01: unknown study state %d on dp %d", string.byte(payload, 1), dp))
      return
    end
    local event = is_on_code and ir_slot_study.onCodeStatus(state_text) or ir_slot_study.offCodeStatus(state_text)
    emit_to_switch(device, switch_num, event)
  else
    log.debug(string.format("ZG-IR01: unhandled datapoint %d (len %d)", dp, #payload))
  end
end

-- A single EF00 frame may carry several datapoints back-to-back after the
-- 2-byte sequence number (dp(1) type(1) len(2) data(len), repeated) -- parse
-- in a loop instead of reading only the first block.
local function tuya_cluster_handler(driver, device, zb_rx)
  local rx = zb_rx.body.zcl_body.body_bytes
  local pos = 3
  while pos + 3 <= #rx do
    local dp = string.byte(rx, pos)
    local fncmd_len = string.unpack(">I2", rx, pos + 2)
    local payload = rx:sub(pos + 4, pos + 3 + fncmd_len)
    if #payload < fncmd_len then
      log.warn(string.format("ZG-IR01: truncated datapoint %d (want %d bytes, got %d)", dp, fncmd_len, #payload))
      break
    end
    local ok, err = pcall(handle_dp, device, dp, payload)
    if not ok then
      log.warn(string.format("ZG-IR01: error handling datapoint %d: %s", dp, tostring(err)))
    end
    pos = pos + 4 + fncmd_len
  end
end

--------------------------------------------------

local function switch_command(driver, device, command, is_on)
  local dp = COMPONENT_TO_SWITCH[command.component] or 1
  send_tuya_dp(device, dp, DP_TYPE_BOOL, is_on and "\x01" or "\x00")
end

local function switch_on(driver, device, command)
  switch_command(driver, device, command, true)
end

local function switch_off(driver, device, command)
  switch_command(driver, device, command, false)
end

local function learn_command(device, command, is_on_code)
  local switch_num = COMPONENT_TO_SWITCH[command.component]
  if switch_num == nil then return end
  local dp = DP_LEARN[switch_num][is_on_code and 1 or 2]
  send_tuya_dp(device, dp, DP_TYPE_ENUM, "\x00")
  -- optimistic feedback; the device's own dp report will confirm/correct it
  local event = is_on_code and ir_slot_study.onCodeStatus("학습 중") or ir_slot_study.offCodeStatus("학습 중")
  emit_to_switch(device, switch_num, event)
end

local function learn_on_code(driver, device, command)
  learn_command(device, command, true)
end

local function learn_off_code(driver, device, command)
  learn_command(device, command, false)
end

--------------------------------------------------

-- Backfills default state for components that have never reported anything yet
-- (a fresh pairing, or an already-paired device that just gained components
-- from a profile update -- lifecycle "added" won't refire for those).
local function ensure_defaults(device)
  for _, component_id in ipairs(SWITCH_TO_COMPONENT) do
    local component = device.profile.components[component_id]
    if component ~= nil then
      if device:get_latest_state(component_id, capabilities.switch.ID, "switch") == nil then
        device:emit_component_event(component, capabilities.switch.switch.off())
      end
      if device:get_latest_state(component_id, IR_SLOT_STUDY_ID, "onCodeStatus") == nil then
        device:emit_component_event(component, ir_slot_study.onCodeStatus("없음"))
      end
      if device:get_latest_state(component_id, IR_SLOT_STUDY_ID, "offCodeStatus") == nil then
        device:emit_component_event(component, ir_slot_study.offCodeStatus("없음"))
      end
    end
  end
end

local function do_configure(driver, device)
  configure_tuya_magic_packet(device)
end

local function device_added(driver, device)
  ensure_defaults(device)
  device.thread:call_with_delay(2, function()
    do_configure(driver, device)
  end)
end

local function device_init(driver, device)
  ensure_defaults(device)
end

local function info_changed(driver, device, event, args)
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
end

--------------------------------------------------

local zg_ir01_driver = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.temperatureMeasurement,
    capabilities.relativeHumidityMeasurement,
    capabilities.battery,
    ir_slot_study,
  },
  zigbee_handlers = {
    cluster = {
      [CLUSTER_TUYA] = {
        [0x01] = tuya_cluster_handler, -- dataResponse
        [0x02] = tuya_cluster_handler, -- dataReport
        [0x05] = tuya_cluster_handler, -- activeStatusReportAlt (some firmwares)
        [0x06] = tuya_cluster_handler, -- activeStatusReport
      }
    },
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on,
      [capabilities.switch.commands.off.NAME] = switch_off,
    },
    [IR_SLOT_STUDY_ID] = {
      ["learnOnCode"] = learn_on_code,
      ["learnOffCode"] = learn_off_code,
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
