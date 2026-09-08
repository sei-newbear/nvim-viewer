local repo = vim.fn.getcwd()
package.path = repo .. "/lua/?.lua;" .. package.path

local temp = vim.fn.tempname()
local project = temp .. "/project"
vim.fn.mkdir(project .. "/.venv/bin", "p")
vim.fn.writefile({ "#!/bin/sh" }, project .. "/.venv/bin/python")
vim.fn.setfperm(project .. "/.venv/bin/python", "rwxr-xr-x")

local python = require("custom.python")
assert(python.venv_path(project) == project .. "/.venv/bin/python",
  "プロジェクト直下のuv仮想環境を検出できなかった")

local settings = { python = { analysis = { diagnosticMode = "openFilesOnly" } } }
local config = {
  root_dir = project,
  settings = settings,
}
python.configure(config)
assert(config.settings.python.pythonPath == project .. "/.venv/bin/python",
  "Pyrightへuv仮想環境のPythonパスを設定できなかった")
assert(settings.python.pythonPath == project .. "/.venv/bin/python",
  "Neovimが保持する送信用設定を更新できなかった")
assert(config.settings.python.analysis.diagnosticMode == "openFilesOnly",
  "既存のPyright設定を壊した")

vim.fn.setfperm(project .. "/.venv/bin/python", "rw-r--r--")
assert(python.venv_path(project) == nil,
  "実行できないファイルをPythonとして検出した")

vim.fn.delete(project .. "/.venv", "rf")
assert(python.venv_path(project) == nil,
  ".venvがないプロジェクトでPythonパスを上書きした")

vim.fn.delete(temp, "rf")
print("python_spec: OK")
