--[[
* puller - Copyright (c) 2026 AddonsXI
*
* Built on the packet parsing in atom0s's Checker addon, which is where the check
* result layout and the difficulty and defense message ids come from.
*
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

addon.name      = 'puller';
addon.author    = 'AddonsXI';
addon.version   = '1.2.0';
addon.link      = 'https://github.com/AddonsXI';
addon.desc      = 'Announces the mob you are pulling to party chat, with its level, difficulty and defenses.';

require('common');
local chat = require('chat');
local imgui = require('imgui');
local theme = require('theme');
local settings = require('settings');

local callOptions = T{
    'No Call',
    '<call1> (Loud Whistle 1)',
    '<call2> (Loud Whistle 2)',
    '<call3> (Loud Whistle 3)',
    '<call4> (Fanfare)',
    '<call5> (Fail Fanfare)',
    '<call6> (War Drum Beat 1)',
    '<call7> (War Drum Beat 2)',
    '<call8> (Snare Drum Beat)',
    '<call9> (Snare Drum Roll)',
    '<call10> (Crystal Theme)',
    '<call11> (Reverse Crystal Theme)',
    '<call12> (Gong)',
    '<call13> (Flat Gong)',
    '<call14> (Light Ding)',
    '<call15> (Buzzer)',
    '<call16> (Ring Short)',
    '<call17> (Ring Long)',
    '<call18> (Sproing Low)',
    '<call19> (Sproing High)',
    '<call20> (Quiet Chime)',
    '<call21> (Quiet Chime 2)',
};

-- Index 21 is <call20>, the quiet chime.
local DEFAULT_CALL_SOUND = 21;

-- settings.load fills missing keys, never validates present ones.
local function validCallSound(i)
    if (type(i) ~= 'number') or (i ~= math.floor(i)) or (i < 1) or (i > #callOptions) then
        return DEFAULT_CALL_SOUND;
    end

    return i;
end

local DEFAULT_TEMPLATE = 'Pulling ${name} [Lv. ${level}] [${difficulty}] [${attributes}] ${call}';

local function validTemplate(t)
    if (type(t) ~= 'string') or (t:gsub('%s', '') == '') then
        return DEFAULT_TEMPLATE;
    end

    return t;
end

-- ${attributes} is empty on an ordinary mob, ${call} on No Call.
local TOKENS = T{
    { key = 'name',       hint = 'Steppe Hare' },
    { key = 'level',      hint = '9, or ??? when it cannot be read' },
    { key = 'difficulty', hint = 'Easy Prey' },
    { key = 'attributes', hint = 'Low EVA & DEF, empty on an ordinary mob' },
    { key = 'call',       hint = '<call12>, empty when no sound is picked' },
};

local defaultConfig = T{
    callSound = DEFAULT_CALL_SOUND,
    template = DEFAULT_TEMPLATE,
};

-- Preview values until a real check replaces them. The call tag comes from the dropdown.
local SAMPLE = {
    name = 'Steppe Hare',
    level = '9',
    difficulty = 'Easy Prey',
    attributes = 'Low EVA & DEF',
};

local EXAMPLES = T{
    { name = 'Default', text = DEFAULT_TEMPLATE },
    { name = 'Short',   text = '${name} - ${difficulty} ${call}' },
};

local puller = T{
    settings = settings.load(defaultConfig),
    configMenuOpen = false,

    -- InputText edits this in place. Rebuilding per frame would discard half typed text.
    templateBuf = T{ '' },

    lastValues = nil,
};

puller.settings.callSound = validCallSound(puller.settings.callSound);
puller.settings.template = validTemplate(puller.settings.template);
puller.templateBuf[1] = puller.settings.template;

local function update_settings(s)
    if (s ~= nil) then
        puller.settings = s;
    end

    puller.settings.callSound = validCallSound(puller.settings.callSound);
    puller.settings.template = validTemplate(puller.settings.template);
    settings.save();
end

settings.register('settings', 'settings_update', update_settings);

--[[
* 0xAA to 0xB2, no gaps. Evasion by row, defense by column. All nine verified live.
*
*              DEF high    DEF normal   DEF low
*  EVA high      0xAA         0xAB        0xAC
*  EVA normal    0xAD         0xAE        0xAF
*  EVA low       0xB0         0xB1        0xB2
--]]
local ATTRIBUTES = T{
    [0xAA] = 'High EVA & DEF',
    [0xAB] = 'High EVA',
    [0xAC] = 'High EVA & Low DEF',
    [0xAD] = 'High DEF',
    [0xAE] = '',
    [0xAF] = 'Low DEF',
    [0xB0] = 'Low EVA & High DEF',
    [0xB1] = 'Low EVA',
    [0xB2] = 'Low EVA & DEF',
};

-- Sent instead of a grid value when the mob is too far above you to read.
local UNGAUGEABLE = 0xF9;

local DIFFICULTY = T{
    [0x40] = 'Too Weak',
    [0x41] = 'Incredibly Easy Prey',
    [0x42] = 'Easy Prey',
    [0x43] = 'Decent Challenge',
    [0x44] = 'Even Match',
    [0x45] = 'Tough',
    [0x46] = 'Very Tough',
    [0x47] = 'Incredibly Tough',
};

--[[
* 0x029 carries every battle message, so a check is identified by its codes, not its id.
*
*  0x029  level  s32 0x0C   difficulty u32 0x10   index u16 0x16   attributes u16 0x18
*  0x0F4  index  u16 0x04   level      s8  0x06
--]]
local PACKET_ZONE_IN     = 0x000A;
local PACKET_ZONE_LEAVE  = 0x000B;
local PACKET_WIDESCAN    = 0x00F4;
local PACKET_BATTLE_MSG  = 0x0029;

-- Set by /pull, cleared by the result it triggers. A manual check is left alone.
local isPulling = false;

-- The only level source for a mob the check reports as unknown. Indices are per zone.
local widescan = T{ };

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0) then
        return;
    end

    local command = args[1]:lower();

    -- A macro line may carry the token, so /pull and /pull <t> both pull. Anything else
    -- is a typo, and opening the window for one would hide it.
    if (command == '/pull') then
        e.blocked = true;

        if (#args == 1 or args[2]:lower() == '<t>') then
            isPulling = true;
            AshitaCore:GetChatManager():QueueCommand(1, '/check');
        else
            print(chat.header(addon.name)
                :append(chat.message('Use /pull on its own, or /puller for the config.')));
        end

        return;
    end

    if (command == '/puller') then
        puller.configMenuOpen = not puller.configMenuOpen;
        e.blocked = true;
    end
end);

-- Drops a bracket pair left holding nothing, with the space in front of it.
-- Collapsing every run of spaces instead would eat a player's own spacing.
local function renderTemplate(template, values)
    local text = template:gsub('%${(%w+)}', function (key)
        return values[key] ~= nil and tostring(values[key]) or '';
    end);

    text = text:gsub(' ?%(%s*%)', ''):gsub(' ?%[%s*%]', ''):gsub(' ?{%s*}', '');

    return (text:gsub('^%s+', ''):gsub('%s+$', ''));
end

-- Colors the preview. Pieces are recovered from the rendered string with a moving cursor.
local function previewPieces(template, values)
    local text = renderTemplate(template, values);
    local pieces = T{ };
    local pos = 1;

    for key in template:gmatch('%${(%w+)}') do
        local value = values[key];

        if (value ~= nil) and (value ~= '') then
            local from, to = text:find(value, pos, true);

            if (from ~= nil) then
                if (from > pos) then
                    pieces:append({ text = text:sub(pos, from - 1) });
                end

                pieces:append({ text = value, key = key });
                pos = to + 1;
            end
        end
    end

    if (pos <= #text) then
        pieces:append({ text = text:sub(pos) });
    end

    return pieces;
end

-- The tag number is one below the index. Never parsed back out of the display label.
local function callTag()
    if (puller.settings.callSound > 1) then
        return ('<call%d>'):format(puller.settings.callSound - 1);
    end

    return '';
end

local function checkValues(name, level, difficulty, attributes)
    local call = callTag();

    return {
        name = name,
        level = (level > 0) and tostring(level) or '???',
        difficulty = difficulty,
        attributes = attributes or '',
        call = call,
    };
end

local function buildMessage(name, level, difficulty, attributes)
    puller.lastValues = checkValues(name, level, difficulty, attributes);

    return renderTemplate(puller.settings.template, puller.lastValues);
end

ashita.events.register('packet_in', 'packet_in_cb', function (e)
    -- An injected packet is not our reply, and blocking it would swallow another addon's.
    if (e.injected) then
        return;
    end

    if (e.id == PACKET_ZONE_IN or e.id == PACKET_ZONE_LEAVE) then
        widescan:clear();

        -- A result cannot cross a zone. Left armed, the pull claims the next manual check.
        isPulling = false;
        return;
    end

    if (e.id == PACKET_WIDESCAN) then
        widescan[struct.unpack('H', e.data, 0x04 + 0x01)] = struct.unpack('b', e.data, 0x06 + 0x01);
        return;
    end

    if (e.id ~= PACKET_BATTLE_MSG) then
        return;
    end

    local level = struct.unpack('l', e.data, 0x0C + 0x01);
    local difficulty = struct.unpack('L', e.data, 0x10 + 0x01);
    local attributes = struct.unpack('H', e.data, 0x18 + 0x01);
    local index = struct.unpack('H', e.data, 0x16 + 0x01);
    local entity = GetEntity(index);

    local gaugeable = (attributes ~= UNGAUGEABLE);

    -- Combat traffic lands here constantly and must leave the pull armed.
    if (gaugeable and (ATTRIBUTES[attributes] == nil or DIFFICULTY[difficulty] == nil)) then
        return;
    end

    -- Blocking unconditionally would swallow every check the player runs by hand.
    if (not isPulling) then
        return;
    end

    isPulling = false;

    -- A mob gone from the entity table cannot be named, so the game's own line goes out.
    if (entity == nil) or (entity.Name == nil) or (entity.Name == '') then
        return;
    end

    e.blocked = true;

    -- A check far above you reports no level, so widescan is the only source left.
    if (level <= 0) then
        level = widescan[index] or level;
    end

    local text;
    if (gaugeable) then
        text = buildMessage(entity.Name, level, DIFFICULTY[difficulty], ATTRIBUTES[attributes]);
    else
        text = buildMessage(entity.Name, level, 'Impossible to gauge', nil);
    end

    -- ${call} alone with No Call renders to nothing, which would post a blank line.
    if (text ~= '') then
        AshitaCore:GetChatManager():QueueCommand(1, '/party ' .. text);
    end
end);

ashita.events.register('text_in', 'text_in_cb', function (e)
    -- A check with no valid target produces no packet, so the pull would stay armed.
    if (not e.injected and e.message:lower():find('a command error occurred')) then
        isPulling = false;
    end
end);

local function renderConfigMenu()
    local pushed = theme.Push();

    -- Always would re-apply every frame and the window could not be dragged.
    imgui.SetNextWindowSize({ 720, 380 }, ImGuiCond_FirstUseEver);

    if (imgui.SetNextWindowSizeConstraints ~= nil) then
        imgui.SetNextWindowSizeConstraints({ 300, 180 }, { 99999, 99999 });
    end

    local p_open = T{ true };

    -- End is called even when Begin returns false, or the window stack unbalances.
    -- Three hashes so a version bump keeps the saved position. The id is hashed whole.
    local drawing = imgui.Begin(('Puller v%s###pullerwin'):format(addon.version), p_open, ImGuiWindowFlags_None);

    if (drawing) then
        imgui.TextColored(theme.col.textDim, 'What your party sees');

        -- The call tag comes from the dropdown. lastValues holds the one used at pull time.
        local shown = { };
        for key, value in pairs(puller.lastValues or SAMPLE) do shown[key] = value; end
        shown.call = callTag();

        local pieces = previewPieces(puller.templateBuf[1], shown);

        -- SameLine(0, 0): the pieces already carry their own spacing.
        for i, piece in ipairs(pieces) do
            if (i > 1) then
                imgui.SameLine(0, 0);
            end

            local color = piece.key and theme.token[piece.key] or theme.col.text;
            imgui.TextColored(color, piece.text);
        end

        if (#pieces == 0) then
            imgui.TextColored(theme.col.textFaint, '(nothing)');
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        imgui.TextColored(theme.col.textDim, 'Template');
        -- Text sits on the baseline, an input inside a frame, so the icon would ride high.
        imgui.AlignTextToFramePadding();
        imgui.TextColored(theme.col.textFaint, '✏');
        imgui.SameLine(0, 4);
        imgui.PushItemWidth(-1);
        imgui.PushStyleColor(ImGuiCol_FrameBg, theme.inputBg);
        imgui.PushStyleColor(ImGuiCol_FrameBgHovered, theme.inputBg);
        imgui.PushStyleColor(ImGuiCol_FrameBgActive, theme.inputBg);

        if (imgui.InputText('##template', puller.templateBuf, 256)) then
            puller.settings.template = validTemplate(puller.templateBuf[1]);
            settings.save();
        end

        imgui.PopStyleColor(3);
        imgui.PopItemWidth();

        -- Each name wears the color its value wears in the preview above.
        imgui.TextColored(theme.col.textDim, 'Variables');

        for _, token in ipairs(TOKENS) do
            imgui.SameLine();
            imgui.TextColored(theme.token[token.key] or theme.col.text, '${' .. token.key .. '}');

            if (imgui.IsItemHovered()) then
                imgui.SetTooltip(token.hint);
            end
        end

        imgui.TextColored(theme.col.textDim, 'Examples');

        for _, example in ipairs(EXAMPLES) do
            imgui.SameLine();

            if (imgui.SmallButton(example.name)) then
                puller.templateBuf[1] = example.text;
                puller.settings.template = example.text;
                settings.save();
            end
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        imgui.TextColored(theme.col.textDim, 'Call sound');
        imgui.PushItemWidth(-1);

        if (imgui.BeginCombo('##callsound', callOptions[puller.settings.callSound])) then
            for i = 1, #callOptions do
                local isSelected = (puller.settings.callSound == i);

                if (imgui.Selectable(callOptions[i], isSelected)) then
                    puller.settings.callSound = i;
                    settings.save();
                end

                if (isSelected) then
                    imgui.SetItemDefaultFocus();
                end
            end

            imgui.EndCombo();
        end

        imgui.PopItemWidth();
        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- A draw list rectangle, not a child window, which cannot unbalance the stack.
        imgui.TextColored(theme.col.textDim, 'Example macro');

        local blockX, blockY = imgui.GetCursorScreenPos();
        local blockW = imgui.GetContentRegionAvail();
        local lineH = imgui.GetTextLineHeight();
        local pad = 6;

        imgui.GetWindowDrawList():AddRectFilled({ blockX, blockY - 2 }, { blockX + blockW, blockY + lineH * 2 + pad * 2 }, imgui.GetColorU32(theme.inputBg), 3);

        imgui.Dummy({ 0, pad - 4 });
        imgui.Indent(pad);
        imgui.TextColored(theme.col.textFaint, '/pull');
        imgui.TextColored(theme.col.textFaint, '/ra <t>');
        imgui.SameLine();
        imgui.TextColored(theme.col.textFaint, '   or whatever you pull with');
        imgui.Unindent(pad);
        imgui.Dummy({ 0, pad - 4 });

        imgui.Spacing();
        imgui.Separator();

        if (imgui.Button('Reset', { 90, 0 })) then
            settings.reset();
            puller.templateBuf[1] = puller.settings.template;
        end

        imgui.SameLine();

        if (imgui.Button('Close', { 90, 0 })) then
            puller.configMenuOpen = false;
        end
    end

    imgui.End();
    theme.Pop(pushed);

    if (not p_open[1]) then
        puller.configMenuOpen = false;
    end
end

ashita.events.register('d3d_present', 'present_cb', function ()
    -- Ashita's own hide primitives, so one addon can hide every addon's rendering.
    if (AshitaCore:GetFontManager():GetVisible() == false)
        or (AshitaCore:GetGuiManager():GetVisible() == false)
        or (AshitaCore:GetPrimitiveManager():GetVisible() == false) then
        return;
    end

    if (puller.configMenuOpen) then
        renderConfigMenu();
    end
end);

ashita.events.register('unload', 'unload_cb', function ()
    settings.save();
end);
