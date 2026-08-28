--[[
* puller - Copyright (c) 2026 AddonsXI
*
* Thanks to atom0s. The check result packet layout and its message ids come from
* his Checker addon.
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
addon.version   = '1.2.1';
addon.link      = 'https://github.com/AddonsXI';
addon.desc      = 'Announces the mob you are pulling to party chat, with its level, difficulty and defenses.';

require('common');
local chat = require('chat');
local imgui = require('imgui');
local theme = require('theme');
local compat = require('compat');
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

local DEFAULT_TEMPLATE = 'Pulling ${name} - ${difficulty}, LVL ${level}, ${attributes} ${call}';

    -- An empty template means say nothing. Only a non string falls back.
local function validTemplate(t)
    if (type(t) ~= 'string') then
        return DEFAULT_TEMPLATE;
    end

    -- A newline truncates a chat command at the break.
    return (t:gsub('[\r\n]+', ' '));
end

-- ${attributes} is empty on an ordinary mob, ${call} on No Call.
local TOKENS = T{
    { key = 'name',       hint = 'Hill Lizard' },
    { key = 'level',      hint = '17, or ??? on a mob you cannot gauge' },
    { key = 'difficulty', hint = 'Incredibly Tough' },
    { key = 'attributes', hint = 'High EVA & DEF, empty on an ordinary mob' },
    { key = 'call',       hint = '<call12>, empty when no sound is picked' },
};

local defaultConfig = T{
    callSound = DEFAULT_CALL_SOUND,
    template = DEFAULT_TEMPLATE,
};

-- Preview values until a real check replaces them. The call tag comes from the dropdown.
local SAMPLE = {
    name = 'Hill Lizard',
    level = '17',
    difficulty = 'Incredibly Tough',
    attributes = 'High EVA & DEF',
};

local EXAMPLES = T{
    { name = 'Default',  text = DEFAULT_TEMPLATE },
    { name = 'No sound', text = 'Pulling ${name} - ${difficulty}, LVL ${level}, ${attributes}' },
    { name = 'Short',    text = 'Pulling ${name} - ${difficulty}, LVL ${level} ${call}' },
};

local puller = T{
    settings = settings.load(defaultConfig),
    configMenuOpen = false,

    -- InputText edits this in place. Rebuilding per frame would discard half typed text.
    templateBuf = T{ '' },

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

    -- Sent for a notorious or battlefield mob. Level and difficulty both arrive 0.
local UNGAUGEABLE = 0xF9;

    -- 117, measured in game. The packet field is 128 bytes but the client stops
    -- you first, and anything past it is dropped on the way out with no error.
local MAX_CHAT = 117;

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
        puller.fitPending = puller.configMenuOpen;
        e.blocked = true;
    end
end);

-- Drops a bracket pair left holding nothing, with the space in front of it.
-- Collapsing every run of spaces instead would eat a player's own spacing.
local function renderTemplate(template, values, keepFull)
        -- A comma or dash in front of a token is eaten with it when the token renders
        -- empty. Matched against the template, or a mob name holding a dash is cut.
    local text = template:gsub('(%s*)([,-]?)(%s*)%${(%w+)}', function (lead, sep, gap, key)
        local value = values[key];
        value = (value ~= nil) and tostring(value) or '';

        if (value == '') then
            return '';
        end

        return lead .. sep .. gap .. value;
    end);

    -- Bracket pairs still collapse, for a template that uses them by hand.
    text = text:gsub(' ?%(%s*%)', ''):gsub(' ?%[%s*%]', ''):gsub(' ?{%s*}', '');

    -- And a separator left with nothing after it, from a token at the very end.
    text = text:gsub('%s*[,-]%s*$', '');

    text = text:gsub('^%s+', ''):gsub('%s+$', '');

    -- Cut where the game cuts, so the preview cannot promise more than it sends.
    if (not keepFull) and (#text > MAX_CHAT) then
        text = text:sub(1, MAX_CHAT);
    end

    return text;
end


-- The tag number is one below the index. Never parsed back out of the display label.
local function callTag()
    if (puller.settings.callSound > 1) then
        return ('<call%d>'):format(puller.settings.callSound - 1);
    end

    return '';
end

    -- A level 1 mob arrives as -1: base level 1 carries a level modifier of -2.
    -- Both spellings reach here. 0 is the ungaugeable branch and is not a level.
local function levelText(level)
    if (level > 0) then
        return tostring(level);
    end

    if (level == -1) then
        return '1';
    end

    return '???';
end

    -- Longest mob name on a live server is 24 characters, average 13.
local MAX_NAME = 24;

local function widestValues()
    local out = { name = MAX_NAME, level = 3 };
    out.difficulty = 0;
    for _, v in pairs(DIFFICULTY) do out.difficulty = math.max(out.difficulty, #v); end
    out.difficulty = math.max(out.difficulty, #'Impossible to gauge');
    out.attributes = 0;
    for _, v in pairs(ATTRIBUTES) do out.attributes = math.max(out.attributes, #v); end
    out.call = #'<call20>';

    local values = { };
    for key, n in pairs(out) do values[key] = string.rep('x', n); end
    return values;
end

local function worstCaseLength(template)
    return #renderTemplate(template, widestValues(), true);
end

local function checkValues(name, level, difficulty, attributes)
    local call = callTag();

    return {
        name = name,
        level = levelText(level),
        difficulty = difficulty,
        attributes = attributes or '',
        call = call,
    };
end

local function buildMessage(name, level, difficulty, attributes)
    return renderTemplate(puller.settings.template, checkValues(name, level, difficulty, attributes));
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

-- A stale addons\libs shifts every style var number, so an inline push lands on
-- the wrong slot with the wrong type and the pop then over-pops. Every colour
-- puller pushes is same valued in both eras and needs no guard.
local function pushVar(enum, value)
    if (compat.StaleLibs) then return 0; end
    imgui.PushStyleVar(enum, value);
    return 1;
end

local function popVars(n)
    if (n > 0) then imgui.PopStyleVar(n); end
end

local function renderConfigMenu()
    local pushed = theme.Push();

    -- The field does not wrap, so a long template scrolls sideways inside it.
    -- Sized off what the default template renders to. No minimum size.
    local defaultW = imgui.CalcTextSize(renderTemplate(DEFAULT_TEMPLATE, SAMPLE)) + 130;

    -- Height is measured at the bottom of the previous frame. Always, or a size
    -- saved in imgui.ini wins. The width is kept so a dragged window stays put.
    if (puller.fitPending and puller.contentH ~= nil) then
        imgui.SetNextWindowSize({ puller.winW or defaultW, puller.contentH }, ImGuiCond_Always);
        puller.fitPending = false;
    else
        imgui.SetNextWindowSize({ defaultW, 400 }, ImGuiCond_FirstUseEver);
    end

    local p_open = T{ true };

    -- End is called even when Begin returns false, or the window stack unbalances.
    -- Three hashes so a version bump keeps the saved position. The id is hashed whole.
    local drawing = imgui.Begin(('Puller v%s###pullerwin'):format(addon.version), p_open);

    if (drawing) then
        imgui.TextColored(theme.col.textDim, 'What your party sees');

        -- Always the sample, so every token is filled while the line is being edited.
        local shown = { };
        for key, value in pairs(SAMPLE) do shown[key] = value; end
        shown.call = callTag();

        local line = renderTemplate(puller.templateBuf[1], shown);

            -- A borderless child ignores WindowPadding without AlwaysUseWindowPadding.
            -- Measured at the same wrap width it is drawn at.
        local chatPad = 6;
        local wrapAt = imgui.GetContentRegionAvail() - chatPad * 2;
        local _, lineH = imgui.CalcTextSize((line ~= '') and line or ' ', false, wrapAt);
        imgui.PushStyleColor(ImGuiCol_ChildBg, theme.chatBg);
        local padVars = pushVar(ImGuiStyleVar_WindowPadding, { 8, chatPad });
        imgui.BeginChild('##pullerpreview',
            { 0, lineH + chatPad * 2 },
            ImGuiChildFlags_AlwaysUseWindowPadding);
        imgui.PushTextWrapPos(0);

        if (line ~= '') then
            imgui.TextColored(theme.chatText, line);
            if (#line >= MAX_CHAT) then
                imgui.TextColored(theme.col.caution, '  cut here, the rest never arrives');
            end
        else
            imgui.TextColored(theme.col.textFaint, '(nothing)');
        end

        imgui.PopTextWrapPos();
        imgui.EndChild();
        popVars(padVars);
        imgui.PopStyleColor(1);

        imgui.Spacing();

        imgui.TextColored(theme.col.textDim, 'Edit the line');

        -- Push the padding before AlignTextToFramePadding, which measures the frame
        -- padding in force when it runs.
        local fieldVars = pushVar(ImGuiStyleVar_FrameBorderSize, 1)
            + pushVar(ImGuiStyleVar_FramePadding, { 8, 6 });

        imgui.Indent(3);
        imgui.AlignTextToFramePadding();
        imgui.TextColored(theme.col.accent, '✏');
        imgui.Unindent(3);
        imgui.SameLine(0, 8);

        imgui.PushStyleColor(ImGuiCol_FrameBg, theme.inputBg);
        imgui.PushStyleColor(ImGuiCol_FrameBgHovered, theme.inputBg);
        imgui.PushStyleColor(ImGuiCol_FrameBgActive, theme.inputBg);
        imgui.PushStyleColor(ImGuiCol_Border, theme.col.accentDim);

        -- Tokens can still expand a short template past MAX_CHAT.
        imgui.PushItemWidth(-1);
        if (imgui.InputText('##template', puller.templateBuf, MAX_CHAT)) then
            puller.settings.template = validTemplate(puller.templateBuf[1]);
            settings.save();
        end
        imgui.PopItemWidth();

        popVars(fieldVars);
        imgui.PopStyleColor(4);

        local worst = worstCaseLength(puller.templateBuf[1]);
        if (worst > MAX_CHAT) then
            imgui.TextColored(theme.col.caution,
                ('Too long for chat on a big mob name, by about %d characters. The end will be cut.')
                :format(worst - MAX_CHAT));
        end

        imgui.TextColored(theme.col.textDim, 'Templates');

        imgui.PushStyleColor(ImGuiCol_Button, theme.col.accentBg);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, theme.col.accentSel);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, theme.col.accentDim);
        imgui.PushStyleColor(ImGuiCol_Text, theme.col.accent);

        for _, example in ipairs(EXAMPLES) do
            imgui.SameLine();

            if (imgui.SmallButton(example.name)) then
                puller.templateBuf[1] = example.text;
                puller.settings.template = example.text;
                settings.save();
            end
        end

        imgui.PopStyleColor(4);

        imgui.TextColored(theme.col.textDim, 'Variables');

        for _, token in ipairs(TOKENS) do
            imgui.SameLine();
            imgui.TextColored(theme.col.text, '${' .. token.key .. '}');

            if (imgui.IsItemHovered()) then
                imgui.SetTooltip(token.hint);
            end
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        imgui.AlignTextToFramePadding();
        imgui.TextColored(theme.col.textDim, 'Call sound');
        imgui.SameLine();
        imgui.PushItemWidth(math.min(imgui.GetContentRegionAvail(), 300));

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

        imgui.TextColored(theme.col.textDim, 'Example macros');
        imgui.Indent(6);

        imgui.BeginGroup();
        imgui.TextColored(theme.col.textFaint, '/pull');
        imgui.TextColored(theme.col.textFaint, '/ja "Provoke" <t>');
        imgui.EndGroup();

            -- A group reports its own bounding box, so the rule follows where the first
            -- column ends rather than a guessed x.
        local leftX, ruleBottom = imgui.GetItemRectMax();
        local _, topY = imgui.GetItemRectMin();

        imgui.SameLine(0, 48);

        imgui.GetWindowDrawList():AddLine(
            { leftX + 16, topY + 1 },
            { leftX + 16, ruleBottom - 1 },
            imgui.GetColorU32(theme.col.border), 1);

        imgui.BeginGroup();
        imgui.TextColored(theme.col.textFaint, '/pull');
        imgui.TextColored(theme.col.textFaint, '/ra <t>');
        imgui.EndGroup();

        imgui.Unindent(6);

        imgui.Dummy({ 0, 10 });

        if (imgui.Button('Reset', { 90, 0 })) then
            settings.reset();
            puller.templateBuf[1] = puller.settings.template;
            -- imgui.ini is read at startup and rewritten from memory, so the remembered
            -- width is the only way back to the default size.
            puller.winW = nil;
            puller.fitPending = true;
        end

        imgui.SameLine();

        if (imgui.Button('Close', { 90, 0 })) then
            puller.configMenuOpen = false;
        end

        -- Where the content actually ended, plus the padding under it.
        puller.contentH = imgui.GetCursorPosY() + 10;

            -- Not while a refit is pending: Reset clears winW from a handler above this.
        if (not puller.fitPending) then
            puller.winW = imgui.GetWindowSize();
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

    -- theme.Push skips styling on a stale libs folder, so say why.
ashita.events.register('load', 'load_cb', function ()
    if (compat.StaleLibs) then
        print(chat.header(addon.name)
            :append(chat.message('your Ashita libs folder is outdated, so this window is unstyled. Update Ashita to fix it.')));
    end
end);

ashita.events.register('unload', 'unload_cb', function ()
    settings.save();
end);
