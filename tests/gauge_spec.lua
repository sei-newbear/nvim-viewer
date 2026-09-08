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
vim.fn.writefile({ "<project/>" }, temp .. "/project/pom.xml")

write_executable(temp .. "/bin/mvn", {
  "#!/bin/sh",
  "printf '%s\\n' \"$*\" >> \"$GAUGE_TEST_ROOT/mvn.calls\"",
  "[ \"${GAUGE_TEST_MVN_FAIL:-}\" = 1 ] && exit 42",
  "mkdir -p target/test-classes",
  "printf '%s' '/tmp/kotlin.jar:/tmp/example.jar' > target/gauge-classpath.txt",
})
write_executable(temp .. "/bin/gauge", {
  "#!/bin/sh",
  "[ -d target/test-classes ] || exit 43",
  "[ \"$gauge_custom_build_path\" = target/test-classes ] || exit 44",
  "[ \"$gauge_additional_libs\" = '/tmp/kotlin.jar,/tmp/example.jar' ] || exit 45",
  "printf '%s\\n' \"$*\" >> \"$GAUGE_TEST_ROOT/gauge.calls\"",
})

local original_root = vim.env.GAUGE_TEST_ROOT
vim.env.GAUGE_TEST_ROOT = temp

local gauge = require("custom.gauge")
vim.fn.mkdir(temp .. "/plain-project", "p")
assert(vim.deep_equal(gauge.daemon_command(temp .. "/plain-project"), {
  "gauge", "daemon", "--lsp", "--dir", temp .. "/plain-project",
}), "Maven以外のGaugeプロジェクトまでコンパイル対象になった")

local command = gauge.daemon_command(temp .. "/project")
local result = run(command, temp .. "/project", temp .. "/bin:" .. vim.env.PATH)
assert(result.code == 0, result.stderr)
assert(result.stderr == "", "正常な初回コンパイルで警告が出た: " .. result.stderr)
assert(vim.fn.readfile(temp .. "/mvn.calls")[1]
  == "test-compile dependency:build-classpath -Dmdep.outputFile=target/gauge-classpath.txt "
    .. "-Dmdep.excludeArtifactIds=gauge-java")
assert(vim.fn.readfile(temp .. "/gauge.calls")[1]
  == "daemon --lsp --dir " .. temp .. "/project")
assert(vim.uv.fs_stat(temp .. "/project/target/nvim-viewer-compiled") ~= nil,
  "起動前コンパイルの完了印が作られなかった")

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

vim.fn.mkdir(temp .. "/project/src/test/kotlin/steps", "p")
vim.fn.writefile({
  "class ExampleSteps {",
  '  @Step("Say hello to <name>")',
  "  fun sayHello(name: String) {}",
  "}",
}, temp .. "/project/src/test/kotlin/steps/ExampleSteps.kt")
local definitions = gauge.find_step_definitions(temp .. "/project",
  'Say hello to "Alice"')
assert(#definitions == 1)
assert(definitions[1].line == 2)
assert(gauge.is_expected_source_message(
  "implementation source not found: Step implementation referred from an external project or library"))
assert(not gauge.is_expected_source_message("Step implementation not found"))
assert(not gauge.is_expected_source_message(
  "other: implementation source not found: Step implementation referred from an external project or library"))

local sequence = {}
local jump_count = 0
local deps = {
  bufnr = 1,
  is_gauge = true,
  is_maven = true,
  client = { root_dir = temp .. "/project" },
  is_step_line = true,
  source_stamp = "source-v1",
  request_definition = function(callback)
    sequence[#sequence + 1] = "request"
    callback(false)
  end,
  compile = function(_, callback)
    sequence[#sequence + 1] = "compile"
    callback(true)
  end,
  restart = function(_, _, callback)
    sequence[#sequence + 1] = "restart"
    callback(true)
  end,
  after_restart = function(fallback)
    sequence[#sequence + 1] = "retry"
    fallback()
  end,
}
local function jump()
  jump_count = jump_count + 1
  sequence[#sequence + 1] = "jump"
end

gauge.definition(jump, deps)
assert(table.concat(sequence, ",") == "request,compile,restart,retry,jump")
assert(jump_count == 1)

sequence = {}
gauge.definition(jump, deps)
assert(table.concat(sequence, ",") == "request,jump",
  "同じソース状態で未定義の手順を再コンパイルした")

sequence = {}
deps.source_stamp = "source-v2"
deps.request_definition = function(callback)
  sequence[#sequence + 1] = "request"
  callback(true)
end
gauge.definition(jump, deps)
assert(table.concat(sequence, ",") == "request,jump",
  "定義が見つかったのにコンパイルした")

sequence = {}
deps.source_stamp = "source-v3"
deps.already_compiled = true
deps.request_definition = function(callback)
  sequence[#sequence + 1] = "request"
  callback(false)
end
deps.no_definition = function()
  sequence[#sequence + 1] = "source"
end
gauge.definition(jump, deps)
assert(table.concat(sequence, ",") == "request,source",
  "起動直後に同じソースを再コンパイルした")

sequence = {}
deps.source_stamp = "source-v4"
deps.already_compiled = false
deps.compile = function(_, callback)
  sequence[#sequence + 1] = "compile"
  callback(false)
end
gauge.definition(jump, deps)
assert(table.concat(sequence, ",") == "request,compile,source",
  "コンパイル失敗時にソース検索へフォールバックしなかった")

sequence = {}
deps.source_stamp = "source-v5"
deps.compile = function(_, callback)
  sequence[#sequence + 1] = "compile"
  callback(true)
end
deps.restart = function(_, _, callback)
  sequence[#sequence + 1] = "restart"
  callback(false)
end
gauge.definition(jump, deps)
assert(table.concat(sequence, ",") == "request,compile,restart,source",
  "LSP再起動失敗時にソース検索へフォールバックしなかった")

vim.env.GAUGE_TEST_MVN_FAIL = nil
vim.env.GAUGE_TEST_ROOT = original_root
vim.fn.delete(temp, "rf")
print("gauge_spec: OK")
