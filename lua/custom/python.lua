local M = {}

function M.venv_path(root)
  if not root then
    return nil
  end

  local path = root .. "/.venv/bin/python"
  return vim.fn.executable(path) == 1 and path or nil
end

function M.configure(config)
  local path = M.venv_path(config.root_dir)
  if not path then
    return
  end

  config.settings = config.settings or {}
  config.settings.python = vim.tbl_deep_extend("force", config.settings.python or {}, {
    pythonPath = path,
  })
end

return M
