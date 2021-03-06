-- Teruview v1.2

-- Mod for open-source voxel game Minetest (https://www.minetest.net/)
-- Written for Minetest version 0.4.16
-- Provides in-game information on blocks in the world by clicking/punching them

--[[ Copyright (C) 2017-2018 Terumoc (Scott Horvath)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>. ]]

teruview = {}
teruview.version = {major=1, minor=2, patch=3}
local ver = teruview.version
teruview.version_text = ver.major .. '.' .. ver.minor .. '.' .. ver.patch
teruview.mod_name = 'teruview'

dofile(minetest.get_modpath(teruview.mod_name) .. '/options.lua')

local private = {}
private.hud_data = {}

function teruview.get_hud_data(player)
    return private.hud_data[player:get_player_name()]
end

function teruview.delete_hud_data(player)
    private.hud_data[player:get_player_name()] = nil
end

function teruview.parse_mod_name(id)
    return id:match('(%w+):')
end

function teruview.parse_node_id(id)
    return id:match(':(.+)')
end

function teruview.init_hud_data(player)
    local hud_data = {}
    local player_name = player:get_player_name()
    hud_data.bg = player:hud_add{
        hud_elem_type = 'image',
        position = teruview.anchor,
        scale = {x=1.0, y=1.0},
        offset = teruview.background_offset,
        text = teruview.background_image,
        alignment = 0
    }
    hud_data.name_text = player:hud_add{
        hud_elem_type = 'text',
        position = teruview.anchor,
        offset = teruview.node_name_offset,
        scale = {x=240, y=32},
        text = '<left-click for information>',
        alignment = 0,
        number = teruview.view_color_nothing
    }
    hud_data.mod_text = player:hud_add{
        hud_elem_type = 'text',
        position = teruview.anchor,
        offset = teruview.mod_name_offset,
        scale = {x=240, y=32},
        text = 'Teruview version ' .. teruview.version_text,
        alignment = 0,
        number = teruview.view_color_modname
    }
    hud_data.tool_info_text = player:hud_add{
        hud_elem_type = 'text',
        position = teruview.anchor,
        offset = teruview.tool_info_offset,
        scale = {x=80, y=32},
        text = '',
        alignment = 0,
        number = teruview.view_color_nothing
    }
    hud_data.node_info_text = player:hud_add{
        hud_elem_type = 'text',
        position = teruview.anchor,
        offset = teruview.node_info_offset,
        scale = {x=80, y=32},
        text = '',
        alignment = 0,
        number = teruview.view_color_nothing
    }
    hud_data.display_time = teruview.view_display_time
    private.hud_data[player_name] = hud_data
end

function private.section_update(player, hud_elem, text, text_color)
    player:hud_change(hud_elem, 'text', text or '')
    player:hud_change(hud_elem, 'number', text_color)
end

-- returns color to display for using this tool to dig given node
function teruview.rate_tool_for_node(node_data, tool_caps)
    if not tool_caps.groupcaps then return teruview.view_tool_unable end
    local tool_color = teruview.view_tool_unable
    local required_level = 0
    if node_data.groups and node_data.groups.level then
        required_level = node_data.groups.level
    end
    for grp, rating in pairs(node_data.groups) do
        if tool_caps.groupcaps[grp] then
            local groupcaps = tool_caps.groupcaps[grp]
            if groupcaps.times[rating] then
                local level = groupcaps.maxlevel or 0
                if level >= required_level then
                    return teruview.view_tool_able
                else
                    tool_color = teruview.view_tool_insuff
                end
            else
                tool_color = teruview.view_tool_insuff
            end
        end
    end
    return tool_color
end

function teruview.update_view(pos, node, player, pointed_thing)
    local hud_data = teruview.get_hud_data(player)
    local update = {}
    update.name = '<nothing>'
    update.mod = '<none>'
    update.name_color = teruview.view_color_nothing
    update.mod_color = teruview.view_color_undefined
    update.tools = ''
    update.tools_color = teruview.view_color_nothing
    update.flags = ''
    update.flags_color = teruview.view_color_nothing
    if node then
        local node_data = minetest.registered_nodes[node.name]
        if node_data then
            update.mod = teruview.parse_mod_name(node.name)
            update.mod_color = teruview.view_color_modname
            -- read node name (prefer description, ID as last resort)
            update.name = node_data.description
            if update.name and #update.name > 0 then
                update.name_color = teruview.view_color_node_name
            else
                update.name = teruview.parse_node_id(node.name)
                update.name_color = teruview.view_color_node_id
            end
            -- read and parse node groups (for listing tools and flags)
            local node_level = 0
            for grp, rating in pairs(node_data.groups) do
                if teruview.info_node_groups[grp] then
                    update.flags = teruview.info_node_groups[grp] .. ' ' .. update.flags
                    update.flags_color = teruview.view_node_info
                end
                if teruview.tool_node_groups[grp] then
                    update.tools = teruview.tool_node_groups[grp] .. ':' .. (teruview.tool_group_rating_description[rating] or 'Unk.') .. ' ' .. update.tools
                end
                if grp == 'level' then node_level = rating end
            end
            if node_level > 0 then update.tools = teruview.tool_group_level_description .. node_level .. ' ' .. update.tools end
            -- determine tool capability for node
            local player_tool_caps = player:get_wielded_item():get_tool_capabilities()
            update.tools_color = teruview.rate_tool_for_node(node_data, player_tool_caps)
            if update.tools_color ~= teruview.view_tool_able then
                -- if tool does not work, test implicit hand tool as well
                update.tools_color = teruview.rate_tool_for_node(node_data, minetest.registered_items[''].tool_capabilities)
            end
        else
            -- case that there is no registered data for node
            update.name = node.name
            update.mod = '<undefined>'
            update.name_color = teruview.view_color_undefined
            update.mod_color = teruview.view_color_undefined
        end
    end
    -- update actual HUD objects with new information
    private.section_update(player, hud_data.name_text, update.name, update.name_color)
    private.section_update(player, hud_data.mod_text, update.mod, update.mod_color)
    private.section_update(player, hud_data.tool_info_text, update.tools, update.tools_color)
    private.section_update(player, hud_data.node_info_text, update.flags, update.flags_color)
    player:hud_change(hud_data.bg, 'text', teruview.background_image)

    -- set disappearance timer
    hud_data.display_time = teruview.view_display_time
end

function teruview.time_hud(player, dt)
    local hud_data = teruview.get_hud_data(player)
    if hud_data.display_time and hud_data.display_time > 0.0 then
        hud_data.display_time = hud_data.display_time - dt
        if hud_data.display_time <= 0.0 then
            player:hud_change(hud_data.name_text, 'text', '')
            player:hud_change(hud_data.mod_text, 'text', '')
            player:hud_change(hud_data.bg, 'text', '')
            player:hud_change(hud_data.tool_info_text, 'text', '')
            player:hud_change(hud_data.node_info_text, 'text', '')
            hud_data.display_time = nil
        end
    end
end

minetest.register_on_joinplayer(teruview.init_hud_data)

minetest.register_on_leaveplayer(teruview.delete_hud_data)

minetest.register_on_punchnode(teruview.update_view)

minetest.register_globalstep(function(dt)
    for _,pl in ipairs(minetest.get_connected_players()) do
        teruview.time_hud(pl, dt)
    end
end)