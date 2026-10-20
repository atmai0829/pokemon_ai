local script_directory = "C:\\Users\\maibi\\GIT\\pokemon_ai\\.worktrees\\firered-shiny-hunter\\bizhawk\\"
local bridge_path = script_directory .. "bridge.lua"

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
    end
end

local function assert_true(actual, message)
    assert_equal(actual, true, message)
end

local function assert_false(actual, message)
    assert_equal(actual, false, message)
end

local function run()
memory = {
    usememorydomain = function() end,
    read_u8 = function()
        return 0
    end,
}

local input_calls = {}
joypad = {
    set = function(buttons)
        input_calls[#input_calls + 1] = buttons
    end,
}

BRIDGE_TEST_MODE = true
local bridge = dofile(bridge_path)

local valid_grass_config = {
    mode = "grass",
    grass_inputs = { { buttons = { "Up" }, frames = 1 } },
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

assert_false(bridge.validate_hunt_config({ mode = "grass", grass_inputs = {} }), "empty grass inputs")

local unknown_button_config = {
    mode = "grass",
    grass_inputs = { { buttons = { "Invalid" }, frames = 1 } },
    flee_inputs = valid_grass_config.flee_inputs,
    reset_inputs = valid_grass_config.reset_inputs,
    post_reset_inputs = valid_grass_config.post_reset_inputs,
    starter_species = valid_grass_config.starter_species,
    timeouts = valid_grass_config.timeouts,
}
assert_false(bridge.validate_hunt_config(unknown_button_config), "unknown button")

local zero_frame_config = {
    mode = "grass",
    grass_inputs = { { buttons = { "Up" }, frames = 0 } },
    flee_inputs = valid_grass_config.flee_inputs,
    reset_inputs = valid_grass_config.reset_inputs,
    post_reset_inputs = valid_grass_config.post_reset_inputs,
    starter_species = valid_grass_config.starter_species,
    timeouts = valid_grass_config.timeouts,
}
assert_false(bridge.validate_hunt_config(zero_frame_config), "zero frame action")

assert_true(bridge.validate_hunt_config(valid_grass_config), "valid grass configuration")

bridge.submit_input({ buttons = { "Up", "A" }, frames = 2 })
assert_equal(input_calls[1].Up, true, "up input")
assert_equal(input_calls[1].A, true, "a input")
assert_equal(input_calls[1].frames, 2, "input frame duration")

bridge.clear_input()
assert_equal(next(input_calls[#input_calls]), nil, "cleared input")

print("PASS")
end

local success, error_message = xpcall(run, debug.traceback)
local result = assert(io.open(script_directory .. "test_hunt-result.txt", "wb"))
result:write(success and "PASS" or error_message)
result:close()
client.exit()

if not success then
    error(error_message)
end
