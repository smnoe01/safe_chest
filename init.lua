local number_pass = 4
local password_try_per_sec = 0.001

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
    return string.format("textlist[3.35,1;3,1;pwd_display;%s;]", minetest.formspec_escape(password))
end

local function create_digit_count_label(password)
    return string.format("label[3.35,2;%s]", minetest.colorize("gray", string.format("%d/%d", #password, number_pass)))
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
        meta:set_string("formspec", "size[8,9]" ..
            "list[current_player;main;0,5;8,1;]" ..
            "list[current_player;main;0,6.23;8,3;8]" ..
            "list[current_player;storage;0,0.23;8,2;8]" ..
            "list[current_name;main;0,0;8,3;]" ..
            "image[7,3;1,1;safe_chest.png]" ..
            "tabheader[0,0;safe_chest;Safe Chest Storage (Open);1]" ..
            "label[5.75,3;Safe Chest]")
        meta:set_string("formspec_state", "open")
        meta:set_string("entered_password", "")
    else
        minetest.chat_send_player(player:get_player_name(), "[Safe Chest] Incorrect password!")
        meta:set_string("entered_password", "")
        update_formspec(meta, "", "enter")
    end
end

local function handle_password_set(meta, password, player)
    if password == "" then
        minetest.chat_send_player(player:get_player_name(), "[Safe Chest] Enter a valid password.")
        return
    end
    if meta:get_string("password") == "" then
        meta:set_string("password", password)
        minetest.chat_send_player(player:get_player_name(), "[Safe Chest] Password set!")
        meta:set_string("entered_password", "")
        update_formspec(meta, "", "enter")
    else
        minetest.chat_send_player(player:get_player_name(), "[Safe Chest] Password already set.")
    end
end

local function handle_button_click(meta, fields, player)
    local password = meta:get_string("entered_password")
    for i = 0, 9 do
        if fields["btn" .. i] and #password < number_pass then
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

local function on_construct(pos)
    local meta = minetest.get_meta(pos)
    meta:set_string("password", "")
    meta:set_string("entered_password", "")
    update_formspec(meta, "", "set")
    meta:get_inventory():set_size("main", 32)
end

local function can_dig(pos)
    return minetest.get_meta(pos):get_inventory():is_empty("main")
end

local function on_receive_fields(pos, _, fields, player)
    local meta = minetest.get_meta(pos)
    handle_button_click(meta, fields, player)
    if fields.quit then
        update_formspec(meta, "", "enter")
    end
end

minetest.register_node("safe_chest:safe_chest", {
    description = "Safe Chest",
    tiles = {"default_stone_block.png", "safe_chest.png"},
    groups = {cracky = 1, level = 2},
    on_construct = on_construct,
    sounds = default.node_sound_metal_defaults(),
    can_dig = can_dig,
    on_receive_fields = on_receive_fields,
})

local function search_for_safe_chest(pos)
    local directions = {
        {x =  1, y = 0, z =  0}, -- x+1
        {x = -1, y = 0, z =  0}, -- x-1
        {x =  0, y = 0, z =  1}, -- z+1
        {x =  0, y = 0, z = -1}  -- z-1
    }

    for _, offset in ipairs(directions) do
        local target_pos = vector.add(pos, offset)
        local node = minetest.get_node(target_pos)
        if node.name == "safe_chest:safe_chest" then
            return target_pos
        end
    end
    return nil
end

local function generate_combinations(max_digits)
    local combinations = {}
    for digits = 1, max_digits do
        for i = 0, 10^digits - 1 do
            table.insert(combinations, string.format("%0" .. digits .. "d", i))
        end
    end
    return combinations
end

local function generate_combinations_randomized(max_digits)
    local combinations = generate_combinations(max_digits)
    math.randomseed(os.time())
    for i = #combinations, 2, -1 do
        local j = math.random(1, i)
        combinations[i], combinations[j] = combinations[j], combinations[i]
    end
    return combinations
end
local active_breakers = {}

local function stop_password_crack(pos, clicker)
    local pos_key = minetest.pos_to_string(pos)
    if active_breakers[pos_key] then
        active_breakers[pos_key].stopped = true
        minetest.chat_send_player(clicker:get_player_name(), minetest.colorize("#FF0000", "[Safe Chest Breaker] Password cracking stopped at " .. pos_key .. "."))
        active_breakers[pos_key] = nil
    end
end

local function attempt_password_crack(pos, meta, player, combinations)
    local password = meta:get_string("password")
    if not password or password == "" then
        minetest.chat_send_player(player:get_player_name(), minetest.colorize("#FF0000", "[Safe Chest] Invalid or missing password."))
        return
    end

    local pos_key = minetest.pos_to_string(pos)
    local current_attempt = 1

    active_breakers[pos_key] = { stopped = false }

    local function try_next_combination()

        if not active_breakers[pos_key] or active_breakers[pos_key].stopped then
            return
        end
        if current_attempt > #combinations then
            minetest.chat_send_player(player:get_player_name(), minetest.colorize("#FF0000", "[Safe Chest] Failed to find password at " .. pos_key .. "."))
            active_breakers[pos_key] = nil
            return
        end

        local attempt = combinations[current_attempt]
        minetest.chat_send_player(player:get_player_name(), minetest.colorize("#aaa5a4", "[Safe Chest]") .. " Trying password at " .. pos_key .. ": " .. attempt)
        if attempt == password then
            minetest.chat_send_player(player:get_player_name(), minetest.colorize("#00FF00", "[Safe Chest] Password found at " .. pos_key .. ": " .. attempt))
            minetest.sound_play("found", {
                pos = pos,
                gain = 0.5,
                max_hear_distance = 15,
                loop = false
            })
            active_breakers[pos_key] = nil
            return
        end

        minetest.sound_play("try", {
            pos = pos,
            gain = 0.7,
            max_hear_distance = 10,
            loop = false
        })

        current_attempt = current_attempt + 1

        minetest.after(password_try_per_sec, try_next_combination)
    end

    try_next_combination()
end

local function on_rightclick_safe_chest_breaker(pos, _, clicker, randomized)
    local meta = minetest.get_meta(pos)

    local is_active = meta:get_string("active") == "true"
    if is_active then
        meta:set_string("active", "false")
        stop_password_crack(pos, clicker)
        minetest.chat_send_player(clicker:get_player_name(), minetest.colorize("#FF0000", "[Safe Chest Breaker] Deactivated."))
        return
    end

    meta:set_string("active", "true")

    local safe_chest_pos = search_for_safe_chest(pos)
    if not safe_chest_pos then
        minetest.chat_send_player(clicker:get_player_name(), minetest.colorize("#FF0000", "[Safe Chest Breaker] No safe chest found within 1 block!"))
        return
    end

    local safe_meta = minetest.get_meta(safe_chest_pos)
    local max_digits = number_pass or 4
    local combinations = randomized and generate_combinations_randomized(max_digits) or generate_combinations(max_digits)
    minetest.chat_send_player(clicker:get_player_name(), minetest.colorize("#aaa5a4", "[Safe Chest Breaker] Found a safe chest! Attempting to crack password..."))
    attempt_password_crack(pos, safe_meta, clicker, combinations)
end

minetest.register_node("safe_chest:breaker_random", {
    description = "Safe Chest Breaker (Random)",
    tiles = {"default_stone_block.png"},
    groups = {cracky = 1, level = 2},
    is_ground_content = false,
    sounds = default.node_sound_metal_defaults(),
    on_rightclick = function(pos, _, clicker)
        on_rightclick_safe_chest_breaker(pos, _, clicker, true)
    end,
    on_destruct = function(pos)
        local pos_key = minetest.pos_to_string(pos)
        if active_breakers[pos_key] then
            active_breakers[pos_key].stopped = true
            active_breakers[pos_key] = nil
        end
    end,
})
