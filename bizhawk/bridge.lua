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
local ENEMY_PARTY_BASE = 0x0202402C
local WILD_CALLBACK_1 = 0x080123E5
local WILD_CALLBACK_2 = 0x08011101

local ALLOWED_BUTTONS = {
    A = true,
    B = true,
    Down = true,
    L = true,
    Left = true,
    Power = true,
    R = true,
    Right = true,
    Select = true,
    Start = true,
    Up = true,
}

local HUNT_CONFIG = {
    mode = "grass",
    grass_inputs = {
        { buttons = { "Up" }, frames = 16 },
        { buttons = { "Down" }, frames = 16 },
    },
    flee_inputs = { { buttons = { "B" }, frames = 1 } },
    reset_inputs = { buttons = { "Power" }, frames = 1 },
    post_reset_inputs = { { buttons = { "A" }, frames = 1 } },
    starter_species = 1,
    timeouts = {
        overworld = 60,
        battle_start = 60,
        flee_completion = 60,
        reset = 60,
        target = 60,
    },
}

memory.usememorydomain(MEMORY_DOMAIN)

local function validate_action(action)
    if type(action) ~= "table" or type(action.buttons) ~= "table"
        or type(action.frames) ~= "number" or action.frames <= 0
        or action.frames % 1 ~= 0 then
        return false, "action must have buttons and a positive integer frame count"
    end

    for _, button in ipairs(action.buttons) do
        if not ALLOWED_BUTTONS[button] then
            return false, "unknown controller button: " .. tostring(button)
        end
    end

    return true
end

local function validate_action_list(actions, name)
    if type(actions) ~= "table" or #actions == 0 then
        return false, name .. " must be a non-empty action list"
    end

    for _, action in ipairs(actions) do
        local valid, message = validate_action(action)
        if not valid then
            return false, message
        end
    end

    return true
end

local function validate_hunt_config(config)
    if type(config) ~= "table" or (config.mode ~= "grass" and config.mode ~= "soft_reset") then
        return false, "mode must be grass or soft_reset"
    end

    local valid, message = validate_action_list(config.grass_inputs, "grass_inputs")
    if not valid then return false, message end
    valid, message = validate_action_list(config.flee_inputs, "flee_inputs")
    if not valid then return false, message end
    valid, message = validate_action(config.reset_inputs)
    if not valid then return false, message end
    valid, message = validate_action_list(config.post_reset_inputs, "post_reset_inputs")
    if not valid then return false, message end

    if type(config.starter_species) ~= "number" or config.starter_species <= 0 then
        return false, "starter_species must be positive"
    end

    if type(config.timeouts) ~= "table" then
        return false, "timeouts must be a table"
    end
    for _, name in ipairs({ "overworld", "battle_start", "flee_completion", "reset", "target" }) do
        local timeout = config.timeouts[name]
        if type(timeout) ~= "number" or timeout <= 0 or timeout % 1 ~= 0 then
            return false, "timeout must be a positive integer: " .. name
        end
    end

    return true
end

local function submit_input(action)
    local valid, message = validate_action(action)
    if not valid then
        error(message)
    end

    local buttons = { frames = action.frames }
    for _, button in ipairs(action.buttons) do
        buttons[button] = true
    end
    joypad.set(buttons)
end

local function clear_input()
    joypad.set({})
end

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

local function is_wild_battle()
    return read_u32_le(0x030030F0) == WILD_CALLBACK_1
        and read_u32_le(0x030030F4) == WILD_CALLBACK_2
end

local function read_wild_pokemon()
    if not is_wild_battle() then
        return nil
    end
    return {
        personality = read_u32_le(ENEMY_PARTY_BASE),
        original_trainer_id = read_u32_le(ENEMY_PARTY_BASE + 4),
    }
end

local function is_shiny(record)
    local personality_low = record.personality % 0x10000
    local personality_high = math.floor(record.personality / 0x10000)
    local trainer_low = record.original_trainer_id % 0x10000
    local trainer_high = math.floor(record.original_trainer_id / 0x10000)
    return bit.bxor(personality_low, personality_high, trainer_low, trainer_high) < 8
end

local function inspect_encounter(kind)
    if kind ~= "wild" then
        return "unknown"
    end
    local record = read_wild_pokemon()
    if not record then
        return "unknown"
    end
    return is_shiny(record) and "shiny" or "not_shiny"
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
    HUNT_CONFIG = HUNT_CONFIG,
    clear_input = clear_input,
    inspect_encounter = inspect_encounter,
    is_shiny = is_shiny,
    read_u16_le = read_u16_le,
    read_wild_pokemon = read_wild_pokemon,
    is_valid_ewram_pointer = is_valid_ewram_pointer,
    read_state = read_state,
    submit_input = submit_input,
    validate_hunt_config = validate_hunt_config,
    write_observation = write_observation,
}

if rawget(_G, "BRIDGE_TEST_MODE") then
    return bridge
end

local turn = 0
local config_valid, config_error = validate_hunt_config(HUNT_CONFIG)
if not config_valid then
    error("invalid HUNT_CONFIG: " .. config_error)
end

local grass_action_index = 1
local grass_frames_remaining = 0
local shiny_found = false

local function advance_grass_input()
    if grass_frames_remaining <= 0 then
        local action = HUNT_CONFIG.grass_inputs[grass_action_index]
        grass_action_index = grass_action_index % #HUNT_CONFIG.grass_inputs + 1
        grass_frames_remaining = action.frames
        submit_input(action)
    end
    grass_frames_remaining = grass_frames_remaining - 1
end

while true do
    local state = read_state()
    if state then
        turn = turn + 1
        write_observation({ turn = turn, state = state })
    end

    if HUNT_CONFIG.mode == "grass" and not shiny_found then
        local encounter = inspect_encounter("wild")
        if encounter == "shiny" then
            shiny_found = true
            clear_input()
            gui.drawText(4, 4, "SHINY FOUND - EMULATION PAUSED", "white", "red")
            client.pause()
        elseif encounter == "not_shiny" then
            grass_frames_remaining = 0
            submit_input(HUNT_CONFIG.flee_inputs[1])
        else
            advance_grass_input()
        end
    end

    emu.frameadvance()
end