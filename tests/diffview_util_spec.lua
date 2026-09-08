local repo = vim.fn.getcwd()
package.path = repo .. "/lua/?.lua;" .. package.path

local diffview_util = require("custom.diffview_util")

local current_tab = vim.api.nvim_get_current_tabpage()
local open = true
package.loaded["diffview.lib"] = {
  views = {
    {
      tabpage = current_tab,
      panel = {
        is_open = function() return open end,
      },
    },
  },
}

assert(diffview_util.file_panel_label(current_tab) == "一覧を隠す")
open = false
assert(diffview_util.file_panel_label(current_tab) == "一覧を表示")
assert(diffview_util.file_panel_label(current_tab + 100) == nil,
  "差分ビューではないタブに一覧操作を表示した")

local toggled = 0
package.loaded["diffview.actions"] = {
  toggle_files = function()
    toggled = toggled + 1
    open = not open
  end,
}
assert(diffview_util.toggle_file_panel() == true)
assert(toggled == 1, "ファイル一覧のトグル操作を実行していない")

package.loaded["custom.blame"] = { nav_state = function() return nil end }
package.loaded["custom.toolbar"] = {
  context_buf = function() return vim.api.nvim_get_current_buf() end,
}
local statusline = require("custom.statusline")
assert(statusline.render():find("一覧を隠す", 1, true),
  "開いているファイル一覧を隠す導線が下部バーにない")
open = false
assert(statusline.render():find("一覧を表示", 1, true),
  "隠れているファイル一覧を表示する導線が下部バーにない")
open = true

local options = {
  [11] = { diff = false, winfixwidth = true },
  [12] = { diff = true, winfixwidth = true },
  [13] = { diff = true, winfixwidth = false },
}
local set_calls = {}
local widths = { [12] = 20, [13] = 40 }
local fake = {
  list_wins = function() return { 11, 12, 13 } end,
  get_option = function(win, name) return options[win][name] end,
  set_option = function(win, name, value)
    options[win][name] = value
    set_calls[#set_calls + 1] = { win, name, value }
  end,
  get_width = function(win) return widths[win] end,
  set_width = function(win, width)
    assert(options[11].winfixwidth == true,
      "ファイル一覧の幅を固定せず均等化した")
    assert(options[12].winfixwidth == false)
    assert(options[13].winfixwidth == false)
    widths[win] = width
  end,
}

assert(diffview_util.equalize_diff_windows(7, fake) == true)
assert(widths[12] == 30 and widths[13] == 30, "差分窓を均等幅にしていない")
assert(options[11].winfixwidth == true, "一覧の幅固定状態を復元していない")
assert(options[12].winfixwidth == true, "差分窓の幅固定状態を復元していない")
assert(options[13].winfixwidth == false, "差分窓の幅固定状態を復元していない")
assert(#set_calls == 6, "各窓の一時設定と復元を行っていない")

local one_diff_equalized = false
local one_diff = {
  list_wins = function() return { 21, 22 } end,
  get_option = function(win, name)
    if name == "diff" then return win == 22 end
    return false
  end,
  set_option = function() error("差分窓が1つなのに設定を変更した") end,
  get_width = function() return 10 end,
  set_width = function() one_diff_equalized = true end,
}

assert(diffview_util.equalize_diff_windows(7, one_diff) == false)
assert(one_diff_equalized == false, "差分窓が1つなのに均等化した")

local failing_options = {
  [31] = { diff = false, winfixwidth = false },
  [32] = { diff = true, winfixwidth = true },
  [33] = { diff = true, winfixwidth = false },
}
local failed_once = false
local failing = {
  list_wins = function() return { 31, 32, 33 } end,
  get_option = function(win, name) return failing_options[win][name] end,
  set_option = function(win, name, value)
    if win == 33 and value == false and not failed_once then
      failed_once = true
      error("想定した設定失敗")
    end
    failing_options[win][name] = value
  end,
  get_width = function() return 20 end,
  set_width = function() error("想定した幅変更失敗") end,
}
assert(diffview_util.equalize_diff_windows(7, failing) == false)
assert(failing_options[31].winfixwidth == false)
assert(failing_options[32].winfixwidth == true)
assert(failing_options[33].winfixwidth == false)

local panel = vim.api.nvim_get_current_win()
vim.cmd("vsplit")
local diff_left = vim.api.nvim_get_current_win()
vim.cmd("vsplit")
local diff_right = vim.api.nvim_get_current_win()
vim.wo[panel].winfixwidth = true
vim.api.nvim_win_set_width(panel, 18)
vim.wo[diff_left].diff = true
vim.wo[diff_right].diff = true
vim.api.nvim_win_set_width(diff_left, 10)
vim.api.nvim_set_current_win(panel)
vim.cmd("split")
local panel_bottom = vim.api.nvim_get_current_win()
local heights = {
  [panel] = vim.api.nvim_win_get_height(panel),
  [panel_bottom] = vim.api.nvim_win_get_height(panel_bottom),
}

local panel_width = vim.api.nvim_win_get_width(panel)
assert(diffview_util.equalize_diff_windows(0) == true)
assert(vim.api.nvim_win_get_width(panel) == panel_width,
  "実際の均等化でファイル一覧の幅が変わった")
local left_width = vim.api.nvim_win_get_width(diff_left)
local right_width = vim.api.nvim_win_get_width(diff_right)
assert(math.abs(left_width - right_width) <= 1,
  ("実際の差分窓が均等幅にならなかった: %d / %d"):format(left_width, right_width))
assert(vim.api.nvim_win_get_height(panel) == heights[panel])
assert(vim.api.nvim_win_get_height(panel_bottom) == heights[panel_bottom],
  "差分の幅調整で高さまで変わった")
vim.cmd("only")

print("diffview_util_spec: OK")
