vim.opt.rtp:prepend(vim.fn.getcwd())
local kotlin = require("custom.kotlin")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/jdk/bin", "p")
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, temp .. "/jdk/bin/java")
vim.fn.setfperm(temp .. "/jdk/bin/java", "rwxr-xr-x")
local original = vim.env.VIEWER_KOTLIN_JAVA_HOME
local original_java = vim.env.JAVA_HOME
vim.env.VIEWER_KOTLIN_JAVA_HOME = temp .. "/jdk"
local opts = kotlin.options()
assert(opts.cmd_env.JAVA_HOME == temp .. "/jdk", "指定したJavaをサーバーに渡していない")
assert(vim.env.JAVA_HOME == original_java, "Neovim全体のJava設定を変更した")

local params = { initializationOptions = { storagePath = temp .. "/project", other = true } }
local config = { root_dir = temp .. "/project" }
opts.before_init(params, config)
local cache = params.initializationOptions.storagePath
assert(cache:find(vim.fn.stdpath("cache"), 1, true) == 1,
  "サーバーに送る索引保存先がキャッシュ領域ではない")
assert(cache ~= config.root_dir and vim.fn.isdirectory(cache) == 1)
assert(params.initializationOptions.other == true, "既存の初期化オプションを失った")
local other = {}
opts.before_init(other, { root_dir = temp .. "/another-project" })
assert(cache ~= other.initializationOptions.storagePath, "別プロジェクトの索引を共有した")
vim.fn.delete(cache, "rf")
vim.fn.delete(other.initializationOptions.storagePath, "rf")
vim.env.VIEWER_KOTLIN_JAVA_HOME = original
vim.fn.delete(temp, "rf")
print("kotlin_spec: OK")
