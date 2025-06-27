local S = core.get_translator("safe_chest")
local password_lenght = tonumber(core.settings:get("password_lenght")) or 4
has_default = core.get_modpath("default") ~= nil
has_mineclonia = core.get_modpath("mcl_core") ~= nil

-- Variables based on Minetest Game
local cols = 8
local inventory_size = 32
local groups = {cracky = 1, level = 2}
-- Variables based on Mineclonia
if has_mineclonia then
    cols = 9
    inventory_size = 36
    -- This requires a diamond pickaxe, and it takes about 4 seconds to mine just like in MTG.
    groups = { cracky = 1, pickaxey = 5, material_stone = 1 }
end
local rows = math.ceil(inventory_size / cols)

local function create_digit_button(i, row, col)
    return string.format("button[%d,%0.1f;1,1;btn%d;%d]", col, row + 0.5, i, i)
end

local function create_delete_button()
    return "button[1,3.5;1,1;btn_del;<-]"
end

local function create_number_buttons()
    local buttons = {}
    for i = 1, 9 do
        local row = math.ceil(i / 3) - 1
        local col = (i - 1) % 3
        table.insert(buttons, create_digit_button(i, row, col))
    end
    table.insert(buttons, "button[0,3.5;1,1;btn0;0]")
    table.insert(buttons, create_delete_button())
    return table.concat(buttons)
end

local function create_password_display(password)
    return string.format("textlist[3.35,1;3,1;pwd_display;%s;]", core.formspec_escape(password))
end

local function create_digit_count_label(password)
    return string.format("label[3.35,2;%s]", core.colorize("gray", string.format("%d/%d", #password, password_lenght)))
end

local function create_formspec(title, password, action_button)
    return table.concat({
        "size[7,4.1]",
        string.format("label[0,0;%s]", title),
        create_password_display(password),
        create_digit_count_label(password),
        create_number_buttons(),
        string.format("tabheader[0,0;safe_chest;Safe Chest Password;1]") ..
        string.format("button[4,3.5;2,1;%s;%s]", action_button, action_button)
    })
end

local function update_formspec(meta, password, mode)
    local title = mode == "set" and "Set a new password" or "Enter the password"
    local action_button = mode == "set" and "set_password" or "open"
    meta:set_string("formspec", create_formspec(title, password, action_button))
end

local function handle_login(meta, password, player)
    local stored_password = meta:get_string("password")
    if password == stored_password then
        local formspec
        if has_default then
            formspec =
                "size[" .. cols .. ",9]" ..
                "list[current_player;main;0,5;" .. cols .. ",1;]" ..
                "list[current_player;main;0,6.23;" .. cols .. ",3;" .. cols .. "]" ..
                "listring[current_player;main]" ..
                "list[current_name;main;0,0;" .. cols .. ",3;]" ..
                "listring[current_name;main]" ..
                "image[" .. (cols - 1) .. ",3;1,1;safe_chest.png]" ..
                "button[0,3;2.5,1;reset_password;Reset Password]" ..
                "tabheader[0,0;safe_chest;Safe Chest Storage;1]"
        elseif has_mineclonia then
            local padding_x = 0.33
            local inv_start_y = 0.5
            local player_inv_start_y = inv_start_y + ((rows + 1) * 1.1) + 0.75
            local bf = 1.3 -- bloat factor
            local hotbar_start_y = player_inv_start_y + 3 + 0.75 + 0.2
            local button_row = 4.25 * bf
            formspec =
            "formspec_version[4]"..
            "size[" .. cols * bf .. ",".. 9.5 * bf .."]"..
            mcl_formspec.get_itemslot_bg_v4(padding_x,             inv_start_y,      cols,      rows)..
            "list[context;main;"          ..padding_x..","..       inv_start_y..";"..cols..","..rows..";]"..
            "listring[context;main]"..
            "image[" .. (cols - 1) * bf .. "," .. button_row ..";1,1;safe_chest.png]"..
            "button["..padding_x..","..button_row..";2.5,1;reset_password;Reset Password]"..
            mcl_formspec.get_itemslot_bg_v4(padding_x,      player_inv_start_y,      cols,         3)..
            "list[current_player;main;"   ..padding_x..","..player_inv_start_y..";"..cols..      ",3;"..cols.."]"..
            mcl_formspec.get_itemslot_bg_v4(padding_x,          hotbar_start_y,      cols,         1)..
            "list[current_player;main;"   ..padding_x.. ","..   hotbar_start_y..";"..cols..      ",1;]"..
            "tabheader[0,0;safe_chest;Safe Chest Storage;1]"
        end

        meta:set_string("formspec", formspec)
        meta:set_string("formspec_state", "open")
        meta:set_string("entered_password", "")
    else
        core.chat_send_player(player:get_player_name(), "Incorrect password!")
        meta:set_string("entered_password", "")
        update_formspec(meta, "", "enter")
    end
end

local function handle_password_set(meta, password, player)
    if password == "" then
        core.chat_send_player(player:get_player_name(), "Enter a valid password.")
        return
    end
    if meta:get_string("password") == "" then
        meta:set_string("password", password)
        core.chat_send_player(player:get_player_name(), "Password set!")
        meta:set_string("entered_password", "")
        handle_login(meta, password, player)
    else
        core.chat_send_player(player:get_player_name(), "Password already set.")
    end
end

local function handle_button_click(meta, fields, player)
    local password = meta:get_string("entered_password")
    for i = 0, 9 do
        if fields["btn" .. i] and #password < password_lenght then
            password = password .. tostring(i)
            meta:set_string("entered_password", password)
            update_formspec(meta, password, meta:get_string("password") == "" and "set" or "enter")
        end
    end
    if fields.btn_del then
        password = password:sub(1, -2)
        meta:set_string("entered_password", password)
        update_formspec(meta, password, meta:get_string("password") == "" and "set" or "enter")
    end
    if fields.set_password then
        handle_password_set(meta, password, player)
    elseif fields.open then
        handle_login(meta, password, player)
    end
end

local function on_construct(pos, placer)
    local meta = core.get_meta(pos)
    meta:set_string("password", "")
    meta:set_string("entered_password", "")
    update_formspec(meta, "", "set")
    meta:get_inventory():set_size("main", inventory_size)

    if placer and placer:is_player() then
        meta:set_string("infotext", "Safe Chest (owned by " .. placer:get_player_name() .. ")")
    end
end

local function after_place_node(pos, placer, itemstack, pointed_thing)
    if placer and placer:is_player() then
        local meta = core.get_meta(pos)
        local name = placer:get_player_name() or ""
        meta:set_string("owner", name)
        meta:set_string("infotext", ("Safe Chest (owned by %s)"):format(name))
    end
end

local function can_dig(pos, player)
    local meta  = minetest.get_meta(pos)
    local inv   = meta:get_inventory()
    local owner = meta:get_string("owner")
    local name  = player:get_player_name()
    if owner ~= name then
        return false
    end
    if not inv:is_empty("main") then
        return false
    end
    return true
end

local function on_receive_fields(pos, _, fields, player)
    local meta = core.get_meta(pos)
    handle_button_click(meta, fields, player)
    if fields.quit then
        update_formspec(meta, "", "enter")
    elseif fields.reset_password then
        meta:set_string("password", "")
        meta:set_string("entered_password", "")
        core.chat_send_player(player:get_player_name(), S("Password has been reset. Please set a new one."))
        update_formspec(meta, "", "set")
    end
end

local sounds, tiles

if has_default then
    sounds = default.node_sound_metal_defaults()
    tiles = {"default_stone_block.png", "default_stone_block.png", "default_stone_block.png",
    "default_stone_block.png", "default_stone_block.png", "safe_chest.png"}
elseif has_mineclonia then
    sounds = mcl_sounds.node_sound_metal_defaults()
    tiles = {"default_stone.png", "default_stone.png", "default_stone.png",
    "default_stone.png", "default_stone.png", "safe_chest.png"}
end

core.register_node("safe_chest:safe_chest", {
    description = "Safe Chest",
    tiles = tiles,
    groups = groups,
    on_construct = on_construct,
    sounds = sounds,
    can_dig = can_dig,
    after_place_node = after_place_node,
    on_receive_fields = on_receive_fields,
    protected = true,
    paramtype2 = "facedir",
    on_blast = function(pos, intensity)
    end,
    _mcl_hardness = 10,
    _mcl_blast_resistance = 1200,
})

if has_default then
    minetest.register_craft({
        output = "safe_chest:safe_chest",
        recipe = {
            {"", "default:steel_ingot", ""},
            {"default:steelblock", "default:chest_locked", "default:steelblock"},
            {"", "default:steel_ingot", ""},
        }
    })
elseif has_mineclonia then
    minetest.register_craft({
        output = "safe_chest:safe_chest",
        recipe = {
            {"mcl_redstone_torch:redstoneblock", "mcl_core:iron_ingot", ""},
            {"mcl_core:ironblock", "mcl_chests:trapped_chest", "mcl_core:ironblock"},
            {"", "mcl_core:iron_ingot", ""},
        }
    })
end
