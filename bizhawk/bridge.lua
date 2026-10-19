-- bridge.lua
-- Thin BizHawk adapter for Pokemon FireRed (USA) v1.0.
-- Keep game logic, party interpretation, battle logic, and planning in Python.
--
-- IMPORTANT:
-- Do not fill in an address/offset until it has been verified against the
-- exact ROM revision and live emulator memory. This bridge intentionally fails
-- closed rather than publishing plausible-looking but unverified values.

local BRIDGE_DIRECTORY = rawget(_G, "BRIDGE_DIRECTORY_OVERRIDE")
    or "C:\\Users\\maibi\\GIT\\pokemon_ai\\bridge"
local OBSERVATION_PATH = BRIDGE_DIRECTORY .. "\\observation.json"
local TEMP_PATH = BRIDGE_DIRECTORY .. "\\observation.json.tmp"

local MEMORY_DOMAIN = "EWRAM"
local EWRAM_START = 0x02000000
local EWRAM_END = 0x0203FFFF
local IWRAM_START = 0x03000000
local IWRAM_END = 0x03007FFF

-- Pokemon FireRed USA v1.0. Verify these against the loaded ROM before use.
local SAVE_BLOCK_1_POINTER = 0x03005008
local PLAYER_X_OFFSET = 0x0000
local PLAYER_Y_OFFSET = 0x0002
local MAP_GROUP_OFFSET = 0x0004
local MAP_NUMBER_OFFSET = 0x0005
local BADGES_OFFSET = 0x0F64
local PLAYER_PARTY_COUNT = 0x02024029

memory.usememorydomain(MEMORY_DOMAIN)

local function read_u8(address)
    if address >= EWRAM_START and address <= EWRAM_END then
        return memory.read_u8(address - EWRAM_START, "EWRAM")
    end
    if address >= IWRAM_START and address <= IWRAM_END then
        return memory.read_u8(address - IWRAM_START, "IWRAM")
    end
    error(string.format("unsupported GBA address: 0x%08X", address))
end

local function read_u16_le(address)
    return read_u8(address) + read_u8(address + 1) * 0x100
end

local function read_u32_le(address)
    return read_u16_le(address) + read_u16_le(address + 2) * 0x10000
end

local function is_valid_ewram_pointer(pointer)
    return pointer >= EWRAM_START and pointer <= EWRAM_END - 3 and pointer % 4 == 0
end

local function read_state()
    local save_block_1 = read_u32_le(SAVE_BLOCK_1_POINTER)
    if not is_valid_ewram_pointer(save_block_1) then
        return nil
    end

    local party_count = read_u8(PLAYER_PARTY_COUNT)
    if party_count > 6 then
        return nil
    end

    return {
        map = {
            group = read_u8(save_block_1 + MAP_GROUP_OFFSET),
            number = read_u8(save_block_1 + MAP_NUMBER_OFFSET),
        },
        player = {
            x = read_u16_le(save_block_1 + PLAYER_X_OFFSET),
            y = read_u16_le(save_block_1 + PLAYER_Y_OFFSET),
        },
        progress = {
            badges_bitmask = read_u8(save_block_1 + BADGES_OFFSET),
        },
        party = {
            count = party_count,
        },
    }
end

local function encode_observation(observation)
    local state = observation.state
    return string.format(
        '{"turn":%d,"state":{"map":{"group":%d,"number":%d},"player":{"x":%d,"y":%d},"progress":{"badges_bitmask":%d},"party":{"count":%d}}}',
        observation.turn,
        state.map.group,
        state.map.number,
        state.player.x,
        state.player.y,
        state.progress.badges_bitmask,
        state.party.count
    )
end

local function write_observation(observation)
    local temporary_file = assert(io.open(TEMP_PATH, "wb"))
    temporary_file:write(encode_observation(observation))
    assert(temporary_file:close())
    os.remove(OBSERVATION_PATH)
    assert(os.rename(TEMP_PATH, OBSERVATION_PATH))
end

local bridge = {
    read_u16_le = read_u16_le,
    is_valid_ewram_pointer = is_valid_ewram_pointer,
    read_state = read_state,
    write_observation = write_observation,
}

if rawget(_G, "BRIDGE_TEST_MODE") then
    return bridge
end

local turn = 0
while true do
    local state = read_state()
    if state then
        turn = turn + 1
        write_observation({ turn = turn, state = state })
    end
    emu.frameadvance()
end