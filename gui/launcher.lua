-- The DFHack in-game command launcher
--@module=true
--[====[
gui/launcher
============

Stub documentation.
]====]

local gui = require('gui')
local helpdb = require('helpdb')
local json = require('json')
local script = require('gui.script')
local utils = require('utils')
local widgets = require('gui.widgets')

local AUTOCOMPLETE_PANEL_WIDTH = 20
local EDIT_PANEL_HEIGHT = 4

local HISTORY_SIZE = 5000
local HISTORY_ID = 'gui/launcher'
local HISTORY_FILE = 'dfhack-config/launcher.history'
local CONSOLE_HISTORY_FILE = 'dfhack-config/dfhack.history'
local CONSOLE_HISTORY_FILE_OLD = 'dfhack.history'
local BASE_FREQUENCY_FILE = 'hack/data/base_command_counts.json'
local USER_FREQUENCY_FILE = 'dfhack-config/command_counts.json'

-- trims the history down to its maximum size, if needed
local function trim_history(hist, hist_set)
    if #hist <= HISTORY_SIZE then return end
    -- we can only ever go over by one, so no need to loop
    -- This is O(N) in the HISTORY_SIZE. if we need to make this more efficient,
    -- we can use a ring buffer.
    local line = table.remove(hist, 1)
    -- since all lines are guaranteed to be unique, we can just remove the hash
    -- from the set instead of, say, decrementing a counter
    hist_set[line] = nil
end

-- removes duplicate existing history lines and adds the given line to the front
local function add_history(hist, hist_set, line)
    if hist_set[line] then
        for i,v in ipairs(hist) do
            if v == line then
                table.remove(hist, i)
                break
            end
        end
    end
    table.insert(hist, line)
    hist_set[line] = true
    trim_history(hist, hist_set)
end

local function file_exists(fname)
    return dfhack.filesystem.mtime(fname) ~= -1
end

-- history files are written with the most recent entry on *top*, which the
-- opposite of what we want. add the file contents to our history in reverse.
local function add_history_lines(lines, hist, hist_set)
    for i=#lines,1,-1 do
        add_history(hist, hist_set, lines[i])
    end
end

local function add_history_file(fname, hist, hist_set)
    if not file_exists(fname) then
        return
    end
    local lines = {}
    for line in io.lines(fname) do
        table.insert(lines, line)
    end
    add_history_lines(lines, hist, hist_set)
end

local function init_history()
    local hist, hist_set = {}, {}
    -- snarf the console history into our active history. it would be better if
    -- both the launcher and the console were using the same history object so
    -- the sharing would be "live", but we can address that later.
    add_history_file(CONSOLE_HISTORY_FILE_OLD, hist, hist_set)
    add_history_file(CONSOLE_HISTORY_FILE, hist, hist_set)

    -- read in our own command history
    add_history_lines(dfhack.getCommandHistory(HISTORY_ID, HISTORY_FILE),
                      hist, hist_set)

    return hist, hist_set
end

if not history then
    history, history_set = init_history()
end

local function get_frequency_data(fname)
    local ok, data = pcall(json.decode_file, fname)
    return ok and data or {}
end

local function get_first_word(text)
    return text:trim():split(' +')[1]
end

command_bias = command_bias or get_frequency_data(BASE_FREQUENCY_FILE)
command_counts = command_counts or get_frequency_data(USER_FREQUENCY_FILE)

local function get_command_count(command)
    return (command_bias[command] or 0) + (command_counts[command] or 0)
end

local function record_command(line)
    add_history(history, history_set, line)
    local firstword = get_first_word(line)
    command_counts[firstword] = (command_counts[firstword] or 0) + 1
    json.encode_file(command_counts, USER_FREQUENCY_FILE)
end

----------------------------------
-- AutocompletePanel
--
AutocompletePanel = defclass(AutocompletePanel, widgets.Panel)
AutocompletePanel.ATTRS{
    on_autocomplete=DEFAULT_NIL,
}

function AutocompletePanel:init()
    self:addviews{
        widgets.Label{
            frame={l=0, t=0},
            text='Autocomplete'
        },
        widgets.HotkeyLabel{
            frame={l=1, t=1},
            key='CHANGETAB',
            key_sep='/',
            label='',
            on_activate=self:callback('advance', 1)},
        widgets.HotkeyLabel{
            frame={l=5, t=1},
            key='SEC_CHANGETAB',
            key_sep='',
            label='',
            on_activate=self:callback('advance', -1)},
        widgets.List{
            view_id='autocomplete_list',
            scroll_keys={},
            on_select=self.on_autocomplete,
            frame={l=0, t=3}},
    }
end

function AutocompletePanel:set_options(options, initially_selected)
    local list = self.subviews.autocomplete_list
    -- disable on_select while we reset the options so we don't automatically
    -- trigger the callback
    list.on_select = nil
    list:setChoices(options, 1)
    list.on_select = self.on_autocomplete
    list.cursor_pen = initially_selected and COLOR_LIGHTCYAN or COLOR_CYAN
    self.first_advance = not initially_selected
end

function AutocompletePanel:advance(delta)
    local list = self.subviews.autocomplete_list
    if self.first_advance then
        if list.cursor_pen == COLOR_CYAN and delta > 0 then
            delta = 0
        end
        self.first_advance = false
    end
    list.cursor_pen = COLOR_LIGHTCYAN -- enable highlight
    list:moveCursor(delta, true)
end

function AutocompletePanel:onInput(keys)
    if keys._MOUSE_L and self.subviews.autocomplete_list:getMousePos() then
        -- enable highlight
        self.subviews.autocomplete_list.cursor_pen = COLOR_LIGHTCYAN
    end
    return AutocompletePanel.super.onInput(self, keys)
end

----------------------------------
-- EditPanel
--
EditPanel = defclass(EditPanel, widgets.Panel)
EditPanel.ATTRS{
    on_change=DEFAULT_NIL,
    on_submit=DEFAULT_NIL,
    on_submit2=DEFAULT_NIL
}

function EditPanel:init()
    self.stack = {}
    self:reset_history_idx()

    self:addviews{
        widgets.EditField{
            view_id='editfield',
            frame={l=1, t=1, r=1},
            -- ignore the backtick from the hotkey. otherwise if it is still
            -- held down as the launcher appears, it will be read and be added
            -- to the commandline
            ignore_keys={'STRING_A096'},
            on_change=self.on_change,
            on_submit=self.on_submit,
            on_submit2=self.on_submit2},
        widgets.HotkeyLabel{
            frame={l=1, t=3, w=10},
            key='SELECT',
            label='run',
            on_activate=function()
                if dfhack.internal.getModifiers().shift then
                    self.on_submit2(self.subviews.editfield.text)
                else
                    self.on_submit(self.subviews.editfield.text)
                end
                end},
        widgets.EditField{
            view_id='search',
            frame={l=13, t=3, r=1},
            key='CUSTOM_ALT_S',
            label_text='history search: ',
            on_change=function(text) self:on_search_text(text) end,
            on_unfocus=function()
                self.subviews.search:setText('')
                self.subviews.editfield:setFocus(true) end,
            on_submit=function()
                self.on_submit(self.subviews.editfield.text) end,
            on_submit2=function()
                self.on_submit2(self.subviews.editfield.text) end},
    }
end

function EditPanel:reset_history_idx()
    self.history_idx = #history + 1
end

-- set the edit field text and save the current text in the stack in case the
-- user wants it back
function EditPanel:set_text(text, push)
    local editfield = self.subviews.editfield
    if push and #editfield.text > 0 then
        table.insert(self.stack, editfield.text)
    end
    editfield:setText(text)
    self:reset_history_idx()
end

function EditPanel:pop_text()
    local editfield = self.subviews.editfield
    local text = self.stack[#self.stack]
    if text then
        self.stack[#self.stack] = nil
        self:reset_history_idx()
        editfield:setText(text)
        self.on_change(text)
    end
end

function EditPanel:move_history(delta)
    local history_idx = self.history_idx + delta
    if history_idx < 1 or history_idx > #history + 1 or delta == 0 then
        return
    end
    local editfield = self.subviews.editfield
    if self.history_idx == #history + 1 then
        -- we're moving off the initial buffer. save it so we can get it back.
        self.saved_buffer = editfield.text
    end
    self.history_idx = history_idx
    local text
    if history_idx == #history + 1 then
        -- we're moving onto the initial buffer. restore it.
        text = self.saved_buffer
    else
        text = history[history_idx]
    end
    editfield:setText(text)
    self.on_change(text)
end

function EditPanel:on_search_text(search_str, next_match)
    local start_idx = math.min(self.history_idx - (next_match and 1 or 0),
                               #history)
    for history_idx = start_idx, 1, -1 do
        if history[history_idx]:find(search_str, 1, true) then
            self:move_history(history_idx - self.history_idx)
            return
        end
    end
    -- no matches. restart at the saved input buffer for the next search.
    self:move_history(#history + 1 - self.history_idx)
end

function EditPanel:onInput(keys)
    if EditPanel.super.onInput(self, keys) then return true end

    if keys.STANDARDSCROLL_UP then
        self:move_history(-1)
        return true
    elseif keys.STANDARDSCROLL_DOWN then
        self:move_history(1)
        return true
    elseif keys.CUSTOM_ALT_S then
        -- search to the next match with the current search string
        -- only reaches here if the search field is already active
        self:on_search_text(self.subviews.search.text, true)
        return true
    elseif keys.A_CARE_MOVE_W then -- Alt-Left
        self:pop_text()
        return true
    end
end

----------------------------------
-- HelpPanel
--
HelpPanel = defclass(HelpPanel, widgets.Panel)

local DEFAULT_HELP_TEXT = [[Welcome to DFHack!

Type a command to see its help text here. Hit ENTER
to run the command, or Shift-ENTER to run the
command and close this dialog. The dialog also
closes automatically if you run a command that shows
a new GUI screen.

Not sure what to do? Run the "help" command to get
started!

To see help for this command launcher, type
"launcher" and hit the TAB key or click on
"gui/launcher" to autocomplete.]]

function HelpPanel:init()
    self.cur_entry = ""

    self:addviews{
        widgets.WrappedLabel{
            view_id='help_label',
            frame={l=0, t=0},
            auto_height=false,
            scroll_keys={
                A_MOVE_N_DOWN=-1, -- Ctrl-Up
                A_MOVE_S_DOWN=1,  -- Ctrl-Down
                STANDARDSCROLL_PAGEUP='-halfpage',
                STANDARDSCROLL_PAGEDOWN='+halfpage',
            },
            text_to_wrap=DEFAULT_HELP_TEXT}
    }
end

function HelpPanel:set_help(help_text)
    local label = self.subviews.help_label
    label.text_to_wrap = help_text
    label:postComputeFrame()
    label:updateLayout() -- to update the scroll arrows after rewrapping text
end

function HelpPanel:set_entry(entry_name)
    if not helpdb.is_entry(entry_name) then
        entry_name = ""
    end
    if #entry_name == 0 or entry_name == self.cur_entry then
        return
    end
    self.cur_entry = entry_name
    self:set_help(helpdb.get_entry_long_help(entry_name))
end

function HelpPanel:onInput(keys)
    if HelpPanel.super.onInput(self, keys) then
        return true
    elseif keys._MOUSE_L and self:getMousePos() then
        self.subviews.help_label:scroll('+halfpage')
        return true
    elseif keys._MOUSE_R and self:getMousePos() then
        self.subviews.help_label:scroll('-halfpage')
        return true
    end
end

----------------------------------
-- LauncherUI
--
LauncherUI = defclass(LauncherUI, gui.FramedScreen)
LauncherUI.ATTRS{
    frame_title='DFHack Launcher',
    frame_style = gui.GREY_LINE_FRAME,
    focus_path='launcher',
    parent_focus=DEFAULT_NIL,
}

function LauncherUI:init()
    self.firstword = ""

    self:addviews{
        AutocompletePanel{
            view_id='autocomplete',
            frame={t=0, r=0, w=AUTOCOMPLETE_PANEL_WIDTH},
            on_autocomplete=self:callback('on_autocomplete')},
        EditPanel{
            view_id='edit',
            frame={t=0, l=0, r=AUTOCOMPLETE_PANEL_WIDTH+2, h=EDIT_PANEL_HEIGHT},
            on_change=self:callback('on_edit_input'),
            on_submit=self:callback('run_command', true),
            on_submit2=self:callback('run_command', false)},
        HelpPanel{
            view_id='help',
            frame={t=EDIT_PANEL_HEIGHT+2, l=0, r=AUTOCOMPLETE_PANEL_WIDTH+2}},
    }
end

function LauncherUI:update_help(text, firstword)
    local firstword = firstword or get_first_word(text)
    if firstword == self.firstword then
        return
    end
    self.firstword = firstword
    self.subviews.help:set_entry(firstword)
end

local function extract_entry(entries, firstword)
    for i,v in ipairs(entries) do
        if v == firstword then
            table.remove(entries, i)
            return true
        end
    end
end

local function sort_by_freq(entries)
    -- remember starting position of each entry so we can sort stably
    local indices = utils.invert(entries)
    local stable_sort_by_frequency = function(a, b)
        local acount, bcount = get_command_count(a), get_command_count(b)
        if acount > bcount then return true
        elseif acount == bcount then
            return indices[a] < indices[b]
        end
        return false
    end
    table.sort(entries, stable_sort_by_frequency)
end

-- track whether the user has enabled dev mode
dev_mode = dev_mode or false
local DEV_FILTER = {tag={'dev'}}

-- adds the n most closely affiliated peer entries for the given entry that
-- aren't already in the entries list. affiliation is determined by how many
-- tags the entries share.
local function add_top_related_entries(entries, entry, n)
    local dev_ok = dev_mode or helpdb.get_entry_tags(entry).dev
    local tags = helpdb.get_entry_tags(entry)
    local affinities, buckets = {}, {}
    for i,tag in ipairs(tags) do
        for _,peer in ipairs(helpdb.get_tag_data(tag)) do
            affinities[peer] = (affinities[peer] or 0) + 1
        end
        buckets[i] = {}
    end
    for peer,affinity in pairs(affinities) do
        if helpdb.get_entry_types(peer).command then
            table.insert(buckets[affinity], peer)
        end
    end
    local entry_set = utils.invert(entries)
    for i=#buckets,1,-1 do
        sort_by_freq(buckets[i])
        for _,peer in ipairs(buckets[i]) do
            if not entry_set[peer] then
                entry_set[peer] = true
                if dev_ok or not helpdb.get_entry_tags(peer).dev then
                    table.insert(entries, peer)
                    n = n - 1
                    if n < 1 then return end
                end
            end
        end
    end
end

function LauncherUI:update_autocomplete(firstword)
    local entries = helpdb.search_entries(
        {str=firstword, types='command'},
        dev_mode and {} or DEV_FILTER)
    -- if firstword is in the list, extract it so we can add it to the top later
    -- even if it's not in the list, add it back anyway if it's a valid db entry
    -- (e.g. if it's a dev script that we masked out) to show that it's a valid
    -- command
    local found = extract_entry(entries,firstword) or helpdb.is_entry(firstword)
    sort_by_freq(entries)
    if found then
        table.insert(entries, 1, firstword)
        add_top_related_entries(entries, firstword, 20)
    end
    self.subviews.autocomplete:set_options(entries, found)
end

function LauncherUI:on_edit_input(text)
    self.input_is_worth_saving = true
    local firstword = get_first_word(text)
    self:update_help(text, firstword)
    self:update_autocomplete(firstword)
end

function LauncherUI:on_autocomplete(_, option)
    self.subviews.edit:set_text(option.text, self.input_is_worth_saving)
    self:update_help(option.text)
    self.input_is_worth_saving = false
end

local function launch(kwargs)
    view = LauncherUI{parent_focus=dfhack.gui.getCurFocus(true)}
    view:show()
    view:on_edit_input('')
    if kwargs.initial_help then
        view.subviews.help:set_help(kwargs.initial_help)
    end
    if kwargs.command then
        view.subviews.edit:set_text(kwargs.command)
        view:on_edit_input(kwargs.command)
    end
end

function LauncherUI:onDismiss()
    view = nil
end

-- expected to be run under script.start()
local function safe_run(reappear, command, prev_parent_focus)
    -- allow our dismissed viewscreen to be removed from the stack. this allows
    -- hotkey guards and tools that detect the top viewscreen to work reliably.
    script.sleep(2, 'frames')
    local output = dfhack.run_command_silent(command)
    -- if we displayed a new dfhack screen, don't come back up even if reappear
    -- is true. otherwise, the user can't interact with the new screen. if we're
    -- not reappearing with the output, print the output to the console.
    local parent_focus = dfhack.gui.getCurFocus(true)
    if not reappear or (parent_focus:startswith('dfhack/') and
                        parent_focus ~= prev_parent_focus) then
        if #output > 0 then
            print('Output from command run from gui/launcher:')
            print('> ' .. command)
            print()
            print(output)
        end
        return
    end
    -- reappear and show the command output
    local initial_help = ('> %s\n\n%s'):format(command, output)
    launch({initial_help=initial_help})
end

function LauncherUI:run_command(reappear, text)
    text = text:trim()
    if #text == 0 then return end
    dfhack.addCommandToHistory(HISTORY_ID, HISTORY_FILE, text)
    record_command(text)
    self:dismiss()
    script.start(safe_run, reappear, text, self.parent_focus)
end

function LauncherUI:getWantedFrameSize()
    local width, height = dfhack.screen.getWindowSize()
    return math.max(76, width-10), math.max(24, height-10)
end

local H_SPLIT_PEN = dfhack.pen.parse{ch=205, fg=COLOR_GREY, bg=COLOR_BLACK}
local V_SPLIT_PEN = dfhack.pen.parse{ch=186, fg=COLOR_GREY, bg=COLOR_BLACK}
local TOP_SPLIT_PEN = dfhack.pen.parse{ch=203, fg=COLOR_GREY, bg=COLOR_BLACK}
local BOTTOM_SPLIT_PEN = dfhack.pen.parse{ch=202, fg=COLOR_GREY, bg=COLOR_BLACK}
local LEFT_SPLIT_PEN = dfhack.pen.parse{ch=204, fg=COLOR_GREY, bg=COLOR_BLACK}
local RIGHT_SPLIT_PEN = dfhack.pen.parse{ch=185, fg=COLOR_GREY, bg=COLOR_BLACK}

-- paint autocomplete panel border
local function paint_vertical_border(rect)
    local x = rect.x2 - (AUTOCOMPLETE_PANEL_WIDTH + 2)
    local y1, y2 = rect.y1, rect.y2
    dfhack.screen.paintTile(TOP_SPLIT_PEN, x, y1)
    dfhack.screen.paintTile(BOTTOM_SPLIT_PEN, x, y2)
    for y=y1+1,y2-1 do
        dfhack.screen.paintTile(V_SPLIT_PEN, x, y)
    end
end

-- paint border between edit area and help area
local function paint_horizontal_border(rect)
    local panel_height = EDIT_PANEL_HEIGHT + 1
    local x1, x2 = rect.x1, rect.x2
    local v_border_x = x2 - (AUTOCOMPLETE_PANEL_WIDTH + 2)
    local y = rect.y1 + panel_height
    dfhack.screen.paintTile(LEFT_SPLIT_PEN, x1, y)
    dfhack.screen.paintTile(RIGHT_SPLIT_PEN, v_border_x, y)
    for x=x1+1,v_border_x-1 do
        dfhack.screen.paintTile(H_SPLIT_PEN, x, y)
    end
end

function LauncherUI:onRenderFrame(dc, rect)
    LauncherUI.super.onRenderFrame(self, dc, rect)
    paint_vertical_border(rect)
    paint_horizontal_border(rect)
end

function LauncherUI:onInput(keys)
    if self:inputToSubviews(keys) then
        return true
    elseif keys.LEAVESCREEN then
        self:dismiss()
        return true
    elseif keys.CUSTOM_CTRL_C then
        self.subviews.edit:set_text('', self.input_is_worth_saving)
        self:on_edit_input('')
    elseif keys.CUSTOM_CTRL_D then
        dev_mode = not dev_mode
        self:update_autocomplete(get_first_word(self.subviews.editfield.text))
    end
end

if dfhack_flags.module then
    return
end

if view then
    -- running the launcher while it is open (e.g. from hitting the launcher
    -- hotkey a second time) should close the dialog
    view:dismiss()
else
    local args = {...}
    launch({command=table.concat(args, ' ')})
end
