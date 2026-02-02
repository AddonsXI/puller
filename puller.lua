--[[
* Addons - Copyright (c) 2021 Ashita Development Team
* Contact: https://www.ashitaxi.com/
* Contact: https://discord.gg/Ashita
*
* This file is part of Ashita.
*
* Ashita is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Ashita is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with Ashita.  If not, see <https://www.gnu.org/licenses/>.
--]]

addon.name     = 'puller'
addon.version  = '1.0'
addon.author   = 'AddonsXI'
addon.link     = 'https://github.com/AddonsXI'
addon.description = 'Enhance your FFXI Puller role with real-time mob updates sent to your party, including mob name, level, difficulty, and evasion / defense attributes.'

-- Special thanks to atom0s for creating the Checker addon, which inspired this project and provided some of the code used here.

require('common')

local settings = require('settings')
local imgui = require('imgui')

-----------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------- default config
-----------------------------------------------------------------------------------------------

local defaultConfig = T{ -- Default configuration for the addon
    callSound = 1
}

local puller = T{ -- Stores addon settings and state for the configuration menu
    settings = settings.load(defaultConfig),
    configMenuOpen = false
}

--[[
* Updates the addon settings.
*
* @param {table} s - The new settings table to use for the addon settings. (Optional.)
--]]
local function update_settings(s)
    -- Update the settings table..
    if (s ~= nil) then
        puller.settings = s;
    end
    
    -- Save the current settings..
    settings.save();
end

--[[
* Registers a callback for the settings to monitor for changes.
--]]
settings.register('settings', 'settings_update', update_settings);

local callOptions = { -- List of sound call options for the user to choose from
    "No Call",  
    "<call1> (Loud Whistle 1)",  
    "<call2> (Loud Whistle 2)",  
    "<call3> (Loud Whistle 3)",  
    "<call4> (Fanfare)",  
    "<call5> (Fail Fanfare)",  
    "<call6> (War Drum Beat 1)",  
    "<call7> (War Drum Beat 2)",  
    "<call8> (Snare Drum Beat)",  
    "<call9> (Snare Drum Roll)",  
    "<call10> (Crystal Theme)",  
    "<call11> (Reverse Crystal Theme)",  
    "<call12> (Gong)",  
    "<call13> (Flat Gong)",  
    "<call14> (Light Ding)",  
    "<call15> (Buzzer)",  
    "<call16> (Ring Short)",  
    "<call17> (Ring Long)",  
    "<call18> (Sproing Low)",  
    "<call19> (Sproing High)",  
    "<call20> (Quiet Chime)",  
    "<call21> (Quiet Chime 2)"
}

-----------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------- mob attributes
-----------------------------------------------------------------------------------------------

local mobData = { -- Information about mob attributes and difficulty levels
    attributes = {
        [0xAE] = '',
        [0xB1] = 'Low EVA',
        [0xAF] = 'Low DEF',
        [0xAD] = 'High EVA',
        [0xAB] = 'High DEF',
        [0xB2] = 'Low EVA & DEF',
        [0xAA] = 'High EVA & DEF',
        [0xAC] = 'High EVA & Low DEF',
        [0xB0] = 'Low EVA & High DEF'
    },
    difficulty = {
        [0x40] = 'Too Weak',
        [0x41] = 'Incredibly Easy Prey',
        [0x42] = 'Easy Prey',
        [0x43] = 'Decent Challenge',
        [0x44] = 'Even Match',
        [0x45] = 'Tough',
        [0x46] = 'Very Tough',
        [0x47] = 'Incredibly Tough'
    },
    widescan = {}
}

local isPulling = false -- Keeps track if pulling is active

-----------------------------------------------------------------------------------------------
------------------------------------------------------------------------------ command handling
-----------------------------------------------------------------------------------------------

ashita.events.register('command', 'command_cb', function(e) -- Handles in-game commands
    local args = e.command:args()

    if (#args >= 1) then
        local command = args[1]:lower()

        if command == '/pull' then -- Handles the /pull command
            if (#args == 1) then
                isPulling = true -- Start the pulling process
                AshitaCore:GetChatManager():QueueCommand(1, '/check') -- Perform a /check command on the mob
                e.blocked = true -- Block further processing of the command
                return
            elseif (#args > 1 and args[2]:lower() == '<t>') then
                isPulling = true -- Start the pulling process targeting <t>
                AshitaCore:GetChatManager():QueueCommand(1, '/check') -- Perform a /check command on <t>
                e.blocked = true -- Block the command to avoid opening the menu
                return
            else
                puller.configMenuOpen = not puller.configMenuOpen -- Toggle the configuration menu
                e.blocked = true -- Block the command to avoid further processing
                return
            end
        end

        if command == '/puller' then -- Toggle the config menu with /puller command
            puller.configMenuOpen = not puller.configMenuOpen
            e.blocked = true -- Block the command
            return
        end
    end
end)

-----------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------- packet handler
-----------------------------------------------------------------------------------------------

local function handleIncomingPacket(event) -- Handles incoming packets related to mobs
    if event.id == 0x0029 then -- Specific packet ID for mob data
        local mobLevel = struct.unpack('l', event.data, 0x0C + 0x01) -- Extract mob level
        local mobDifficulty = struct.unpack('L', event.data, 0x10 + 0x01) -- Extract mob difficulty
        local mobAttributes = struct.unpack('H', event.data, 0x18 + 0x01) -- Extract mob attributes
        local mobId = struct.unpack('H', event.data, 0x16 + 0x01) -- Extract mob ID
        local mobEntity = GetEntity(mobId) -- Get entity based on mob ID

        if mobEntity and mobData.attributes[mobAttributes] and mobData.difficulty[mobDifficulty] then -- Check if mob data is valid
            if mobLevel <= 0 then mobLevel = mobData.widescan[mobId] or mobLevel end -- Use widescan if level is not available

            if isPulling then -- If pulling is active
                local callMessage = ""
                if puller.settings.callSound > 1 then -- Set call message based on config
                    callMessage = callOptions[puller.settings.callSound]:match("<call%d+>")
                end

                -- Send mob data to party chat
                AshitaCore:GetChatManager():QueueCommand(1, string.format(
                    '/party %s (Lv. %s)  ---  %s (%s) %s',
                    mobEntity.Name,
                    mobLevel > 0 and tostring(mobLevel) or '???',
                    mobData.difficulty[mobDifficulty],
                    mobData.attributes[mobAttributes],
                    callMessage
                ))

                isPulling = false -- Reset pulling status after the message
            end

            event.blocked = true -- Block further packet processing
        end
        return
    end
end

-----------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------- error handling
-----------------------------------------------------------------------------------------------

local function handleTextError(event) -- Resets pulling if a command error is encountered
    if event.message:lower():find('a command error occurred') then isPulling = false end
end

-----------------------------------------------------------------------------------------------
--------------------------------------------------------------------------- config ui rendering
-----------------------------------------------------------------------------------------------

local function renderConfigMenu() -- Renders the configuration UI
    if not puller.configMenuOpen then
        return;
    end

    -- Set window position and size
    imgui.SetNextWindowPos({0, 0}, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSize({497, 260}, ImGuiCond_FirstUseEver);

    -- Use table reference for p_open so X button can modify it
    local p_open = T{true};
    
    if imgui.Begin('Puller Config', p_open, bit.bor(ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoCollapse)) then -- Open config window
        imgui.Text('')
        if imgui.BeginCombo('Select Call Sound', callOptions[puller.settings.callSound]) then -- Dropdown for call sound selection
            for i = 1, #callOptions do
                local isSelected = (puller.settings.callSound == i)
                if imgui.Selectable(callOptions[i], isSelected) then -- Update selected call sound
                    puller.settings.callSound = i
                    settings.save(); -- Save settings on change
                end
                if isSelected then
                    imgui.SetItemDefaultFocus() -- Set focus to the selected item
                end
            end
            imgui.EndCombo()
        end

        -- Instructions for the user
        imgui.Text('')
        imgui.Text('Instructions:')
        imgui.BulletText('Add a line in your pull macro that only says /pull.')
        imgui.BulletText('Target the mob when pulling, "checking" the mob before is ok.')
        imgui.BulletText('Select a <call> from the dropdown above if you wish to use one.')
        imgui.BulletText('Use /puller to open this config window.')
        imgui.Text('')
        imgui.Text('Check github.com/addonsxi for updates and more addons!')
        imgui.Text('')

        -- Buttons for resetting and closing
        if imgui.Button('  Reset Settings  ') then
            settings.reset();
            print('Puller settings reset to defaults.');
        end
        imgui.SameLine();
        if imgui.Button('  Close  ') then
            puller.configMenuOpen = false;
        end

        -- End the configuration window
        imgui.End();
    end
    
    -- Update configMenuOpen based on p_open (handles X button)
    if not p_open[1] then
        puller.configMenuOpen = false;
    end
end

-----------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------- event cleanup
-----------------------------------------------------------------------------------------------

ashita.events.register('unload', 'unload_cb', function() -- Save settings when the addon is unloaded
    settings.save()
end)

-----------------------------------------------------------------------------------------------
----------------------------------------------------------------------------- rendering handler
-----------------------------------------------------------------------------------------------

ashita.events.register('d3d_present', 'present_cb', function() -- Render the config menu if it's open
    if puller.configMenuOpen then
        renderConfigMenu() -- Call the function to render the menu
    end
end)

-----------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------- event binding
-----------------------------------------------------------------------------------------------

ashita.events.register('packet_in', 'packet_in_cb', handleIncomingPacket) -- Bind incoming packet handler
ashita.events.register('text_in', 'text_in_cb', handleTextError) -- Bind text error handler