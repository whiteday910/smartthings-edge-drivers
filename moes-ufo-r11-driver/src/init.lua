-- MOES UFO-R11 "Tuya ZigBee Smart IR Remote Control Universal Infrared Remote
-- Controller" (chipset reports as manufacturer _TZ3290_ot6ewjvmejq5ekhl, modelID
-- TS1201; the same chipset/protocol is also sold as Aubess ZXZIR-02, Zemismart ZS06,
-- and other rebrands).
--
-- Unlike HOBEIAN ZG-IR01 (see ../zgir01-driver), this device has no on-device switch
-- slots: it learns exactly one arbitrary IR code at a time and reports the raw learned
-- bytes back to the hub, and to replay a code the hub must send those same bytes back
-- to the device. This is the "Zosung" protocol: a small JSON control command on cluster
-- 0xE004, plus a manufacturer-specific chunked binary transfer handshake on cluster
-- 0xED00 (commands 0x00-0x05) used both when the device reports a newly learned code
-- and when the hub pushes a code to be transmitted.
--
-- Ported/adapted from two independent open-source references (cross-checked against
-- each other for consistency):
--   - zigbee-herdsman-converters lib/zosung.ts (Koenkk/zigbee-herdsman-converters)
--   - zhaquirks/tuya/ts1201.py (zigpy/zha-device-handlers), which explicitly lists
--     _TZ3290_ot6ewjvmejq5ekhl as a supported manufacturer for this exact model.
-- Full learn + send round trip confirmed against the physical device via Live Logging
-- (smartthings edge:drivers:logcat). Two SDK API mistakes were caught and fixed this
-- way: FrameCtrl's getter is is_disable_default_response_set() (not
-- is_disable_default_response()), and DefaultResponse's cmd argument must be a
-- Uint8, not a ZCLCommandId. If learn/send misbehaves again, logcat is the fastest
-- way to see why.

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local zcl_messages = require "st.zigbee.zcl"
local zcl_types = require "st.zigbee.zcl.types"
local messages = require "st.zigbee.messages"
local data_types = require "st.zigbee.data_types"
local zb_const = require "st.zigbee.constants"
local generic_body = require "st.zigbee.generic_body"
local default_response = require "st.zigbee.zcl.global_commands.default_response"
local json = require "st.json"
local log = require "log"

local CLUSTER_ZOSUNG_CONTROL = 0xE004
local CLUSTER_ZOSUNG_TRANSMIT = 0xED00
local ZOSUNG_MFG_CODE = 0x1002
local CHUNK_SIZE = 0x38

local ir_blaster = capabilities["acrosswatch58328.irBlasterV2"]

--------------------------------------------------
-- base64 (pure Lua, no external dependency)

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64_encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local b1, b2, b3 = string.byte(data, i, i + 2)
    b2 = b2 or 0
    b3 = b3 or 0
    local n = b1 * 65536 + b2 * 256 + b3
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    local chunk_len = math.min(3, #data - i + 1)
    out[#out + 1] = B64_CHARS:sub(c1 + 1, c1 + 1)
    out[#out + 1] = B64_CHARS:sub(c2 + 1, c2 + 1)
    out[#out + 1] = (chunk_len >= 2) and B64_CHARS:sub(c3 + 1, c3 + 1) or "="
    out[#out + 1] = (chunk_len >= 3) and B64_CHARS:sub(c4 + 1, c4 + 1) or "="
  end
  return table.concat(out)
end

local function base64_decode(data)
  data = data:gsub("[^A-Za-z0-9+/=]", "")
  local rev = {}
  for i = 1, #B64_CHARS do
    rev[B64_CHARS:sub(i, i)] = i - 1
  end
  local out = {}
  local i = 1
  while i + 3 <= #data + 1 do
    local c1 = rev[data:sub(i, i)]
    local c2 = rev[data:sub(i + 1, i + 1)]
    local c3 = data:sub(i + 2, i + 2)
    local c4 = data:sub(i + 3, i + 3)
    if c1 == nil or c2 == nil then break end
    local n = c1 * 262144 + c2 * 4096 + (rev[c3] or 0) * 64 + (rev[c4] or 0)
    out[#out + 1] = string.char(math.floor(n / 65536) % 256)
    if c3 ~= "=" and c3 ~= "" then
      out[#out + 1] = string.char(math.floor(n / 256) % 256)
    end
    if c4 ~= "=" and c4 ~= "" then
      out[#out + 1] = string.char(n % 256)
    end
    i = i + 4
  end
  return table.concat(out)
end

--------------------------------------------------
-- low-level Zosung frame helpers

local function crc_sum(bytes)
  local sum = 0
  for i = 1, #bytes do
    sum = (sum + string.byte(bytes, i)) % 256
  end
  return sum
end

local function next_seq(device)
  local seq = ((device:get_field("zosung_seq") or -1) + 1) % 0x10000
  device:set_field("zosung_seq", seq)
  return seq
end

local function send_zosung_frame(device, cluster_id, cmd_id, payload_bytes)
  local header_args = { cmd = data_types.ZCLCommandId(cmd_id) }
  header_args.mfg_code = data_types.validate_or_build_type(ZOSUNG_MFG_CODE, data_types.Uint16, "mfg_code")
  local zclh = zcl_messages.ZclHeader(header_args)
  zclh.frame_ctrl:set_cluster_specific()
  zclh.frame_ctrl:set_mfg_specific()
  zclh.frame_ctrl:set_disable_default_response()
  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(cluster_id),
    zb_const.HA_PROFILE_ID,
    cluster_id
  )
  local payload_body = generic_body.GenericBody(payload_bytes)
  local message_body = zcl_messages.ZclMessageBody({ zcl_header = zclh, zcl_body = payload_body })
  device:send(messages.ZigbeeMessageTx({ address_header = addrh, body = message_body }))
end

-- Reply with a ZCL Default Response if the incoming frame asked for one (the Zosung
-- transmit cluster otherwise retries the same frame indefinitely).
local function maybe_ack(device, zclh)
  if zclh.frame_ctrl:is_disable_default_response_set() then return end
  local dr_header_args = {
    cmd = data_types.ZCLCommandId(default_response.DefaultResponse.ID),
    seqno = data_types.Uint8(zclh.seqno.value),
  }
  dr_header_args.mfg_code = data_types.validate_or_build_type(ZOSUNG_MFG_CODE, data_types.Uint16, "mfg_code")
  local dr_zclh = zcl_messages.ZclHeader(dr_header_args)
  dr_zclh.frame_ctrl:set_mfg_specific()
  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(CLUSTER_ZOSUNG_TRANSMIT),
    zb_const.HA_PROFILE_ID,
    CLUSTER_ZOSUNG_TRANSMIT
  )
  local dr_body = default_response.DefaultResponse(data_types.Uint8(zclh.cmd.value), zcl_types.ZclStatus.SUCCESS)
  local message_body = zcl_messages.ZclMessageBody({ zcl_header = dr_zclh, zcl_body = dr_body })
  device:send(messages.ZigbeeMessageTx({ address_header = addrh, body = message_body }))
end

-- cluster 0xE004, cmd 0x00: raw JSON control payload, e.g. {"study":0}
local function send_ircontrol_json(device, tbl)
  send_zosung_frame(device, CLUSTER_ZOSUNG_CONTROL, 0x00, json.encode(tbl))
end

-- cluster 0xED00 frame builders (all fields little-endian, per ZCL convention)
local function build_frame_00(seq, length, clusterid, unk2, cmd)
  return string.pack("<I2I4I4I2I1I1I2", seq, length, 0, clusterid, unk2, cmd, 0)
end

local function build_frame_01(seq, length, clusterid, unk2, cmd)
  return string.pack("<I1I2I4I4I2I1I1I2", 0, seq, length, 0, clusterid, unk2, cmd, 0)
end

local function build_frame_02(seq, position, maxlen)
  return string.pack("<I2I4I1", seq, position, maxlen)
end

local function build_frame_03(seq, position, msgpart, crc)
  return string.pack("<I1I2I4", 0, seq, position) .. string.char(#msgpart) .. msgpart .. string.char(crc)
end

local function build_frame_04(seq)
  return string.pack("<I1I2I2", 0, seq, 0)
end

local function build_frame_05(seq)
  return string.pack("<I2I2", seq, 0)
end

--------------------------------------------------
-- learn (device -> hub) and send (hub -> device) flows

local function start_learning(device)
  send_ircontrol_json(device, { study = 0 })
  device:emit_event(ir_blaster.learningState("learning"))
end

local function stop_learning(device)
  send_ircontrol_json(device, { study = 1 })
  device:emit_event(ir_blaster.learningState("idle"))
end

-- Builds the Zosung "key press" JSON message for a given code. `code` may be:
--  - a plain base64 string (as shown in the last learned code) -> wrapped as key_code
--  - a full {"key_num":1,...,"key1":{...}} JSON payload -> passed through
--  - a {"key_code":"...", ...} JSON payload -> normalized into the full structure
local function build_ir_message(code)
  local trimmed = code:match("^%s*(.-)%s*$")
  if trimmed:sub(1, 1) == "{" and trimmed:sub(-1) == "}" then
    local ok, parsed = pcall(json.decode, trimmed)
    if ok and type(parsed) == "table" then
      if parsed.key_num ~= nil and parsed.key1 ~= nil then
        return trimmed
      elseif parsed.key_code ~= nil then
        return json.encode({
          key_num = 1,
          delay = parsed.delay or 300,
          key1 = {
            num = parsed.num or 1,
            freq = parsed.freq or 38000,
            type = parsed.type or 1,
            key_code = parsed.key_code,
          },
        })
      end
    end
  end
  return json.encode({
    key_num = 1,
    delay = 300,
    key1 = { num = 1, freq = 38000, type = 1, key_code = trimmed },
  })
end

local function send_ir_code(device, code)
  local ir_msg = build_ir_message(code)
  local seq = next_seq(device)
  device:set_field("zosung_send_seq", seq)
  device:set_field("zosung_send_message", ir_msg)
  send_zosung_frame(
    device, CLUSTER_ZOSUNG_TRANSMIT, 0x00,
    build_frame_00(seq, #ir_msg, CLUSTER_ZOSUNG_CONTROL, 0x01, 0x02)
  )
end

--------------------------------------------------
-- cluster 0xED00 inbound handlers

local function handle_frame_00(driver, device, zb_rx)
  local zclh = zb_rx.body.zcl_header
  local body = zb_rx.body.zcl_body.body_bytes
  local seq, length, _unk1, clusterid, unk2, cmd = string.unpack("<I2I4I4I2I1I1", body)
  maybe_ack(device, zclh)

  device:set_field("zosung_learn_seq", seq)
  device:set_field("zosung_learn_length", length)
  device:set_field("zosung_learn_buffer", "")

  send_zosung_frame(device, CLUSTER_ZOSUNG_TRANSMIT, 0x01, build_frame_01(seq, length, clusterid, unk2, cmd))
  send_zosung_frame(device, CLUSTER_ZOSUNG_TRANSMIT, 0x02, build_frame_02(seq, 0, CHUNK_SIZE))
end

local function handle_frame_01(driver, device, zb_rx)
  maybe_ack(device, zb_rx.body.zcl_header)
  log.debug("TS1201: transfer start acknowledged by device (0x01)")
end

local function handle_frame_02(driver, device, zb_rx)
  local zclh = zb_rx.body.zcl_header
  local body = zb_rx.body.zcl_body.body_bytes
  local seq, position, maxlen = string.unpack("<I2I4I1", body)
  maybe_ack(device, zclh)

  local msg = device:get_field("zosung_send_message")
  if msg == nil or seq ~= device:get_field("zosung_send_seq") then
    log.warn("TS1201: chunk request for unknown transfer (seq " .. tostring(seq) .. ")")
    return
  end
  local part = msg:sub(position + 1, position + maxlen)
  send_zosung_frame(device, CLUSTER_ZOSUNG_TRANSMIT, 0x03, build_frame_03(seq, position, part, crc_sum(part)))
end

local function handle_frame_03(driver, device, zb_rx)
  local zclh = zb_rx.body.zcl_header
  local body = zb_rx.body.zcl_body.body_bytes
  local _zero, seq, position = string.unpack("<I1I2I4", body)
  local part_len = string.byte(body, 8)
  local msgpart = body:sub(9, 8 + part_len)
  local msgpartcrc = string.byte(body, 9 + part_len)
  maybe_ack(device, zclh)

  if seq ~= device:get_field("zosung_learn_seq") then
    log.warn("TS1201: unexpected learn transfer sequence")
    return
  end
  if crc_sum(msgpart) ~= msgpartcrc then
    log.warn("TS1201: learn chunk checksum mismatch, keeping data anyway")
  end

  local buffer = (device:get_field("zosung_learn_buffer") or "") .. msgpart
  device:set_field("zosung_learn_buffer", buffer)

  if #buffer < (device:get_field("zosung_learn_length") or 0) then
    send_zosung_frame(device, CLUSTER_ZOSUNG_TRANSMIT, 0x02, build_frame_02(seq, #buffer, CHUNK_SIZE))
  else
    send_zosung_frame(device, CLUSTER_ZOSUNG_TRANSMIT, 0x04, build_frame_04(seq))
  end
end

local function handle_frame_04(driver, device, zb_rx)
  local zclh = zb_rx.body.zcl_header
  local body = zb_rx.body.zcl_body.body_bytes
  local _zero0, seq = string.unpack("<I1I2", body)
  maybe_ack(device, zclh)

  send_zosung_frame(device, CLUSTER_ZOSUNG_TRANSMIT, 0x05, build_frame_05(seq))
  device:set_field("zosung_send_message", nil)
  device:set_field("zosung_send_seq", nil)
  log.info("TS1201: IR code transmit completed")
end

local function handle_frame_05(driver, device, zb_rx)
  maybe_ack(device, zb_rx.body.zcl_header)

  local buffer = device:get_field("zosung_learn_buffer") or ""
  device:set_field("zosung_learn_buffer", nil)
  device:set_field("zosung_learn_seq", nil)
  device:set_field("zosung_learn_length", nil)

  local learned_code = base64_encode(buffer)
  device:emit_event(ir_blaster.learnedCode(learned_code))
  log.info("TS1201: learned a new IR code (" .. #buffer .. " bytes)")
  stop_learning(device)
end

--------------------------------------------------
-- capability command handlers

local function cap_learn(driver, device, command)
  start_learning(device)
end

local function cap_cancel_learn(driver, device, command)
  stop_learning(device)
end

local function cap_send_code(driver, device, command)
  local code = command.args.code
  if code == nil or code:match("^%s*$") then
    log.warn("TS1201: sendCode called with empty code")
    return
  end
  send_ir_code(device, code)
end

-- Replays whatever is currently in learnedCode. The SmartThings app has no free-text
-- input UI for custom capability commands, so this no-argument button is the only way
-- to trigger a replay from the app itself (sendCode(code) still exists for CLI/Rules).
local function cap_send(driver, device, command)
  local code = device:get_latest_state("main", "acrosswatch58328.irBlasterV2", "learnedCode")
  if code == nil or code:match("^%s*$") then
    log.warn("TS1201: send pressed with no learnedCode yet")
    return
  end
  send_ir_code(device, code)
end

--------------------------------------------------

local function device_added(driver, device)
  device:emit_event(ir_blaster.learningState("idle"))
end

local ts1201_driver = {
  supported_capabilities = {
    capabilities.momentary,
    ir_blaster,
  },
  zigbee_handlers = {
    cluster = {
      [CLUSTER_ZOSUNG_TRANSMIT] = {
        [0x00] = handle_frame_00,
        [0x01] = handle_frame_01,
        [0x02] = handle_frame_02,
        [0x03] = handle_frame_03,
        [0x04] = handle_frame_04,
        [0x05] = handle_frame_05,
      },
    },
  },
  capability_handlers = {
    [capabilities.momentary.ID] = {
      [capabilities.momentary.commands.push.NAME] = cap_learn,
    },
    ["acrosswatch58328.irBlasterV2"] = {
      ["learn"] = cap_learn,
      ["cancelLearn"] = cap_cancel_learn,
      ["sendCode"] = cap_send_code,
      ["replayLearnedCode"] = cap_send,
    },
  },
  lifecycle_handlers = {
    added = device_added,
  },
  health_check = false,
}

local driver = ZigbeeDriver("ts1201-ir-blaster", ts1201_driver)
driver:run()
