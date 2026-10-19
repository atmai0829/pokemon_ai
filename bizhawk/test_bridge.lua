local test_directory = "C:\\Users\\maibi\\.copilot\\session-state\\e59edffd-6c01-44de-aa8b-1c1717669f98\\files\\bridge-test"
local bridge_path = "C:\\Users\\maibi\\GIT\\pokemon_ai\\bizhawk\\bridge.lua"

local writes = {
    EWRAM = {},
    IWRAM = {},
}

local function run()
local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
    end
end

local function read_observation()
    local file = assert(io.open(test_directory .. "\\observation.json", "rb"))
    local observation = file:read("*a")
    assert(file:close())
    return observation
end

memory = {
    usememorydomain = function(domain)
        assert_equal(domain, "EWRAM", "initial memory domain")
    end,
    read_u8 = function(address, domain)
        return writes[domain][address] or 0
    end,
}

BRIDGE_DIRECTORY_OVERRIDE = test_directory
BRIDGE_TEST_MODE = true

local bridge = dofile(bridge_path)

writes.IWRAM[0x5008] = 0x00
writes.IWRAM[0x5009] = 0x00
writes.IWRAM[0x500A] = 0x00
writes.IWRAM[0x500B] = 0x02

writes.EWRAM[0x0000] = 12
writes.EWRAM[0x0001] = 0
writes.EWRAM[0x0002] = 8
writes.EWRAM[0x0003] = 0
writes.EWRAM[0x0004] = 3
writes.EWRAM[0x0005] = 0
writes.EWRAM[0x0F64] = 5
writes.EWRAM[0x0034] = 0
writes.EWRAM[0x24280] = 1

assert_equal(bridge.read_u16_le(0x02000000), 12, "little-endian u16")
assert_equal(bridge.is_valid_ewram_pointer(0x02000000), true, "valid EWRAM pointer")
assert_equal(bridge.is_valid_ewram_pointer(0x03000000), false, "invalid EWRAM pointer")

local state = bridge.read_state()
assert_equal(state.map.group, 3, "map group")
assert_equal(state.map.number, 0, "map number")
assert_equal(state.player.x, 12, "player x")
assert_equal(state.player.y, 8, "player y")
assert_equal(state.progress.badges_bitmask, 5, "badge bitmask")
assert_equal(state.party.count, 1, "party count")

bridge.write_observation({ turn = 7, state = state })

local observation = read_observation()
assert_equal(
    observation,
    '{"turn":7,"state":{"map":{"group":3,"number":0},"player":{"x":12,"y":8},"progress":{"badges_bitmask":5},"party":{"count":1}}}',
    "observation JSON"
)

bridge.write_observation({ turn = 8, state = state })
observation = read_observation()
assert_equal(
    observation,
    '{"turn":8,"state":{"map":{"group":3,"number":0},"player":{"x":12,"y":8},"progress":{"badges_bitmask":5},"party":{"count":1}}}',
    "replacement observation JSON"
)

writes.IWRAM[0x5008] = 0
writes.IWRAM[0x5009] = 0
writes.IWRAM[0x500A] = 0
writes.IWRAM[0x500B] = 0
assert_equal(bridge.read_state(), nil, "invalid SaveBlock pointer")

os.remove(test_directory .. "\\observation.json")
end

local success, error_message = xpcall(run, debug.traceback)
local result = assert(io.open(test_directory .. "\\test-result.txt", "wb"))
result:write(success and "PASS" or error_message)
result:close()
client.exit()

if not success then
    error(error_message)
end
