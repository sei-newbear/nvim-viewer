local repo = vim.fn.getcwd()
package.path = repo .. "/lua/?.lua;" .. package.path

local function write_executable(path, lines)
  vim.fn.writefile(lines, path)
  vim.fn.setfperm(path, "rwxr-xr-x")
end

local function run(command, cwd, path)
  return vim.system(command, {
    cwd = cwd,
    env = { PATH = path },
    text = true,
  }):wait()
end

local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/bin", "p")
vim.fn.mkdir(temp .. "/project", "p")

write_executable(temp .. "/bin/mvn", {
  "#!/bin/sh",
  "printf '%s\\n' \"$*\" >> \"$GAUGE_TEST_ROOT/mvn.calls\"",
  "[ \"${GAUGE_TEST_MVN_FAIL:-}\" = 1 ] && exit 42",
  "mkdir -p target/test-classes",
})
write_executable(temp .. "/bin/gauge", {
  "#!/bin/sh",
  "[ -d target/test-classes ] || exit 43",
  "[ \"$gauge_custom_build_path\" = target/test-classes ] || exit 44",
  "printf '%s\\n' \"$*\" >> \"$GAUGE_TEST_ROOT/gauge.calls\"",
})

local original_root = vim.env.GAUGE_TEST_ROOT
vim.env.GAUGE_TEST_ROOT = temp

local gauge = require("custom.gauge")
local command = gauge.daemon_command(temp .. "/project")
local result = run(command, temp .. "/project", temp .. "/bin:" .. vim.env.PATH)
assert(result.code == 0, result.stderr)
assert(vim.fn.readfile(temp .. "/mvn.calls")[1] == "test-compile")
assert(vim.fn.readfile(temp .. "/gauge.calls")[1]
  == "daemon --lsp --dir " .. temp .. "/project")

local second = run(command, temp .. "/project", temp .. "/bin:" .. vim.env.PATH)
assert(second.code == 0, second.stderr)
assert(#vim.fn.readfile(temp .. "/mvn.calls") == 1,
  "成果物がある場合にもMavenが再実行された")

vim.fn.delete(temp .. "/project/target", "rf")
vim.env.GAUGE_TEST_MVN_FAIL = "1"
local failed = run(command, temp .. "/project", temp .. "/bin:" .. vim.env.PATH)
assert(failed.code == 42, "Mavenの終了コードが保持されなかった")
assert(#vim.fn.readfile(temp .. "/gauge.calls") == 2,
  "コンパイル失敗後にGaugeが起動された")

vim.env.GAUGE_TEST_MVN_FAIL = nil
vim.env.GAUGE_TEST_ROOT = original_root
vim.fn.delete(temp, "rf")
print("gauge_spec: OK")
