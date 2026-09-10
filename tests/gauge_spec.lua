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

-- 起動時診断は一度だけビルドし、再通知・再起動でも繰り返さない。
local missing = { diagnostics = { { severity = 1, message = "Step implementation not found" } } }
local auto = vim.tbl_extend("force", deps, {
  client = { root_dir = temp .. "/auto-project", config = {} },
  source_stamp = "auto-v1",
  already_compiled = false,
})
local complete_build, complete_restart
sequence = {}
auto.compile = function(_, callback)
  sequence[#sequence + 1] = "compile"
  complete_build = callback
end
auto.restart = function(client, _, callback)
  sequence[#sequence + 1] = "restart"
  auto.client = { root_dir = client.root_dir, config = vim.deepcopy(client.config) }
  complete_restart = callback
end
gauge.on_diagnostics({ diagnostics = { { severity = 1, message = "Syntax error" } } }, auto)
gauge.on_diagnostics({ diagnostics = { { severity = 2, message = "Step implementation not found" } } }, auto)
assert(#sequence == 0, "未実装ステップのエラー以外でビルドした")
gauge.on_diagnostics(missing, auto)
assert(table.concat(sequence, ",") == "compile", "起動時の未実装診断でビルドしない")
gauge.on_diagnostics(missing, auto)
gauge.definition(jump, auto)
assert(table.concat(sequence, ",") == "compile,request", "ビルド中にgdが二重ビルドした")
complete_build(true)
assert(table.concat(sequence, ",") == "compile,request,restart")
gauge.on_diagnostics(missing, auto)
complete_restart(true)
gauge.on_diagnostics(missing, auto)
sequence = {}
gauge.definition(jump, auto)
assert(table.concat(sequence, ",") == "request,source", "自動ビルド直後のgdで再ビルドした")

auto.client = { root_dir = temp .. "/auto-failure", config = {} }
sequence = {}
gauge.on_diagnostics(missing, auto)
complete_build(false)
gauge.on_diagnostics(missing, auto)
assert(table.concat(sequence, ",") == "compile", "失敗後に自動リトライした")
-- 明示的なgdでの再試行は残す。
gauge.definition(jump, auto)
assert(table.concat(sequence, ",") == "compile,request,compile")
complete_build(false)

auto.client = { root_dir = temp .. "/auto-fresh", config = {} }
auto.already_compiled = true
sequence = {}
gauge.on_diagnostics(missing, auto)
assert(#sequence == 0, "起動前にコンパイルしたソースを再ビルドした")

-- 実際の受信口から、表示用の診断を保ちつつ開いたGaugeだけを処理する。
local original_publish = vim.lsp.diagnostic.on_publish_diagnostics
local original_client = vim.lsp.get_client_by_id
local original_diagnostics = gauge.on_diagnostics
local forwarded, checked = 0, 0
local buf = vim.api.nvim_create_buf(true, false)
local spec_path = temp .. "/project/example.spec"
vim.api.nvim_buf_set_name(buf, spec_path)
vim.bo[buf].filetype = "gauge"
local client = {
  id = 321, name = "gauge", root_dir = temp .. "/project",
  attached_buffers = { [buf] = true }, config = {},
}
vim.lsp.diagnostic.on_publish_diagnostics = function() forwarded = forwarded + 1 end
vim.lsp.get_client_by_id = function(id) return id == client.id and client or nil end
gauge.on_diagnostics = function(_, received)
  checked = checked + 1
  assert(received.bufnr == buf and received.client == client)
  assert(received.is_maven and type(received.compile) == "function"
    and type(received.restart) == "function")
end
local notification = vim.tbl_extend("force", missing, { uri = vim.uri_from_fname(spec_path) })
gauge.publish_diagnostics_handler(nil, notification, { client_id = 321 }, {})
assert(forwarded == 1 and checked == 1, "診断の表示または自動ビルドへの接続がない")
notification.uri = vim.uri_from_fname(temp .. "/project/unopened.spec")
gauge.publish_diagnostics_handler(nil, notification, { client_id = 321 }, {})
assert(checked == 1, "未表示ファイルの診断でビルドした")
notification.uri = vim.uri_from_fname(spec_path)
client.attached_buffers = {}
gauge.publish_diagnostics_handler(nil, notification, { client_id = 321 }, {})
client.attached_buffers[buf] = true
client.name = "another-language"
gauge.publish_diagnostics_handler(nil, notification, { client_id = 321 }, {})
assert(forwarded == 4 and checked == 1, "未接続バッファや他のLSPでビルドした")
vim.lsp.diagnostic.on_publish_diagnostics = original_publish
vim.lsp.get_client_by_id = original_client
gauge.on_diagnostics = original_diagnostics
vim.api.nvim_buf_delete(buf, { force = true })

vim.env.GAUGE_TEST_MVN_FAIL = nil
vim.env.GAUGE_TEST_ROOT = original_root
vim.fn.delete(temp, "rf")
print("gauge_spec: OK")
