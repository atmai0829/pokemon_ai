memory.usememorydomain("IWRAM")

local function read_u32(address)
    local offset = address - 0x03000000
    return memory.read_u8(offset, "IWRAM")
        + memory.read_u8(offset + 1, "IWRAM") * 0x100
        + memory.read_u8(offset + 2, "IWRAM") * 0x10000
        + memory.read_u8(offset + 3, "IWRAM") * 0x1000000
end

local output = assert(io.open("C:\\Users\\maibi\\GIT\\pokemon_ai\\bizhawk\\battle-state.txt", "wb"))
output:write(string.format(
    "callback1=%08X\ncallback2=%08X\nmenu_state=%02X\n",
    read_u32(0x030030F0),
    read_u32(0x030030F4),
    memory.read_u8(0x3D88, "EWRAM")
))
output:close()
client.exit()
