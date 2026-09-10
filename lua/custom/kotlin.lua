local M = {}

function M.options()
  -- fwcd 1.3.13のコンパイラはJava 25で起動できない。
  -- サーバーだけJava 21で動かし、端末やプロジェクトのJava設定は保つ。
  local java_home = vim.env.VIEWER_KOTLIN_JAVA_HOME
  if not java_home and vim.fn.executable("mise") == 1 then
    local result = vim.system({ "mise", "where", "java@temurin-21" }, { text = true }):wait(3000)
    if result.code == 0 then java_home = vim.trim(result.stdout) end
  end
  local opts = {
    before_init = function(params, config)
      -- 索引を閲覧対象のリポジトリに作らない。
      local root = config.root_dir or vim.fn.getcwd()
      local path = vim.fn.stdpath("cache") .. "/kotlin-language-server/" .. vim.fn.sha256(root)
      vim.fn.mkdir(path, "p")
      params.initializationOptions = vim.tbl_extend("force", params.initializationOptions or {},
        { storagePath = path })
      config.init_options = params.initializationOptions
    end,
  }
  if java_home and vim.fn.executable(java_home .. "/bin/java") == 1 then
    opts.cmd_env = { JAVA_HOME = java_home }
  end
  return opts
end

return M
