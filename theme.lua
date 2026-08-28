-- Enums are read by name out of _G and nil guarded, so this loads with no imgui.

local imgui = require('imgui');
local compat = require('compat');

local M = {};

M.col = {
    bg          = { 0.09, 0.09, 0.11, 0.94 },
    panel       = { 0.13, 0.13, 0.16, 1.00 },
    panelSoft   = { 0.17, 0.17, 0.20, 1.00 },
    popupEdge   = { 0.24, 0.24, 0.28, 1.00 },
    border      = { 0.26, 0.26, 0.30, 1.00 },

    text        = { 0.90, 0.90, 0.92, 1.00 },
    textDim     = { 0.66, 0.66, 0.70, 1.00 },
    textFaint   = { 0.44, 0.44, 0.48, 1.00 },

    headerBg    = { 0.17, 0.18, 0.21, 1.00 },
    headerHover = { 0.22, 0.23, 0.27, 1.00 },
    headerOn    = { 0.20, 0.21, 0.25, 1.00 },

    accent      = { 0.36, 0.78, 0.45, 1.00 },
    accentDim   = { 0.24, 0.50, 0.30, 1.00 },
    accentBg    = { 0.16, 0.30, 0.20, 1.00 },
    accentSel   = { 0.20, 0.38, 0.25, 1.00 },

    caution     = { 0.95, 0.76, 0.36, 1.00 },

};

M.inputBg = { 0.03, 0.03, 0.04, 1.00 };

-- The game's own party-chat blue.
M.chatBg   = { 0.07, 0.09, 0.24, 1.00 };
M.chatText = { 0.60, 0.85, 1.00, 1.00 };

local StyleColors = {
    { 'ImGuiCol_WindowBg',            'bg' },
    { 'ImGuiCol_ChildBg',             'panel' },
    { 'ImGuiCol_PopupBg',             'panel' },
    { 'ImGuiCol_Border',              'border' },
    { 'ImGuiCol_FrameBg',             'panelSoft' },
    { 'ImGuiCol_FrameBgHovered',      'popupEdge' },
    { 'ImGuiCol_FrameBgActive',       'popupEdge' },
    { 'ImGuiCol_TitleBg',             'panel' },
    { 'ImGuiCol_TitleBgActive',       'panelSoft' },
    { 'ImGuiCol_TitleBgCollapsed',    'panel' },
    { 'ImGuiCol_MenuBarBg',           'panel' },
    { 'ImGuiCol_ScrollbarBg',         'bg' },
    { 'ImGuiCol_ScrollbarGrab',       'panelSoft' },
    { 'ImGuiCol_ScrollbarGrabHovered','popupEdge' },
    { 'ImGuiCol_ScrollbarGrabActive', 'border' },
    { 'ImGuiCol_CheckMark',           'accent' },
    { 'ImGuiCol_SliderGrab',          'accentDim' },
    { 'ImGuiCol_SliderGrabActive',    'accent' },
    { 'ImGuiCol_Button',              'panelSoft' },
    { 'ImGuiCol_ButtonHovered',       'popupEdge' },
    { 'ImGuiCol_ButtonActive',        'accentBg' },
    { 'ImGuiCol_Header',              'headerBg' },
    { 'ImGuiCol_HeaderHovered',       'headerHover' },
    { 'ImGuiCol_HeaderActive',        'headerOn' },
    { 'ImGuiCol_Separator',           'border' },
    { 'ImGuiCol_SeparatorHovered',    'accentDim' },
    { 'ImGuiCol_SeparatorActive',     'accent' },
    { 'ImGuiCol_ResizeGrip',          'panelSoft' },
    { 'ImGuiCol_ResizeGripHovered',   'accentDim' },
    { 'ImGuiCol_ResizeGripActive',    'accent' },
    { 'ImGuiCol_Text',                'text' },
    { 'ImGuiCol_TextDisabled',        'textFaint' },
    { 'ImGuiCol_TextSelectedBg',      'accentSel' },
    { 'ImGuiCol_Tab',                 'panel' },
    { 'ImGuiCol_TabHovered',          'accentSel' },
    { 'ImGuiCol_TabSelected',         'accentBg' },
};

local StyleVars = {
    { 'ImGuiStyleVar_FrameRounding',   3 },
    { 'ImGuiStyleVar_ChildRounding',   4 },
    { 'ImGuiStyleVar_PopupRounding',   4 },
    { 'ImGuiStyleVar_PopupBorderSize', 1 },
    { 'ImGuiStyleVar_GrabRounding',    3 },
    { 'ImGuiStyleVar_WindowRounding',  5 },
    { 'ImGuiStyleVar_TabBarBorderSize',0 },
};

-- A stale addons\libs misnumbers the style enums, so pushing them paints wrong slots.
function M.Push()
    if (compat.StaleLibs) then return nil; end

    local colors = 0;
    for _, entry in ipairs(StyleColors) do
        local enum = _G[entry[1]];
        if (enum ~= nil) then
            imgui.PushStyleColor(enum, M.col[entry[2]]);
            colors = colors + 1;
        end
    end
    local vars = 0;
    for _, entry in ipairs(StyleVars) do
        local enum = _G[entry[1]];
        if (enum ~= nil) then
            imgui.PushStyleVar(enum, entry[2]);
            vars = vars + 1;
        end
    end
    return { colors = colors, vars = vars };
end

function M.Pop(pushed)
    if (pushed == nil) then return; end
    if (pushed.vars > 0) then imgui.PopStyleVar(pushed.vars); end
    if (pushed.colors > 0) then imgui.PopStyleColor(pushed.colors); end
end

return M;
