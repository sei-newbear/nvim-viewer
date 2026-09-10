local M = {}

local compile_log = "logs/nvim-viewer-compile.log"
local classpath_file = "target/gauge-classpath.txt"
local compile_marker = "target/nvim-viewer-compiled"
local compiled_sources = {}
local compiling_roots = {}

--- Gauge LSPを起動するコマンドを返す。
--- Kotlinの手順実装はコンパイル済みclassから読み取られるため、
--- 成果物がない初回だけMavenの差分コンパイルを先に実行する。
function M.daemon_command(root)
  if not vim.uv.fs_stat(root .. "/pom.xml") then
    return { "gauge", "daemon", "--lsp", "--dir", root }
  end
  local compiler = vim.uv.fs_stat(root .. "/mvnw") and "./mvnw" or "mvn"
  local script = ([[
root=$2
cd "$root" || exit 1
if [ ! -d target/test-classes ] || [ ! -f %s ]; then
  mkdir -p logs target
  snapshot=target/nvim-viewer-compile-start
  touch "$snapshot"
  "$1" test-compile dependency:build-classpath \
    -Dmdep.outputFile=%s \
    -Dmdep.excludeArtifactIds=gauge-java > %s 2>&1
  status=$?
  if [ "$status" -ne 0 ]; then
    rm -f "$snapshot"
    cat %s >&2
    exit "$status"
  fi
  if [ -z "$(find pom.xml src/test -type f -newer "$snapshot" -print -quit 2>/dev/null)" ]; then
    find pom.xml src/test -type f \( -name pom.xml -o -name '*.kt' -o -name '*.java' \) \
      2>/dev/null | wc -l > %s
  fi
  rm -f "$snapshot"
fi
additional_libs=$(tr ':' ',' < %s)
exec env gauge_custom_build_path=target/test-classes \
  gauge_additional_libs="$additional_libs" \
  gauge daemon --lsp --dir "$root"
]]):format(classpath_file, classpath_file, compile_log, compile_log,
  compile_marker, classpath_file)

  return { "sh", "-c", script, "nvim-viewer-gauge", compiler, root }
end

local function has_definition(results)
  for _, response in pairs(results or {}) do
    local result = response.result
    if result and (result.uri or next(result) ~= nil) then
      return true
    end
  end
  return false
end

local function source_files(root)
  local files = { root .. "/pom.xml" }
  vim.list_extend(files, vim.fs.find(function(name)
    return name:match("%.kt$") ~= nil or name:match("%.java$") ~= nil
  end, {
    path = root .. "/src/test",
    type = "file",
    limit = 100000,
  }))
  table.sort(files)
  return files
end

local function source_stamp(root)
  local parts = {}
  for _, path in ipairs(source_files(root)) do
    local stat = vim.uv.fs_stat(path)
    if stat then
      parts[#parts + 1] = table.concat({
        path,
        stat.size,
        stat.mtime.sec,
        stat.mtime.nsec,
      }, ":")
    end
  end
  return vim.fn.sha256(table.concat(parts, "\n"))
end

local function build_is_fresh(root)
  local marker = vim.uv.fs_stat(root .. "/" .. compile_marker)
  if not marker then return false end
  local files = source_files(root)
  local ok, marker_lines = pcall(vim.fn.readfile, root .. "/" .. compile_marker)
  if not ok or tonumber(marker_lines[1]) ~= #files then return false end
  for _, path in ipairs(files) do
    local stat = vim.uv.fs_stat(path)
    if stat and (stat.mtime.sec > marker.mtime.sec
      or (stat.mtime.sec == marker.mtime.sec
        and stat.mtime.nsec > marker.mtime.nsec)) then
      return false
    end
  end
  return true
end

local function current_step(bufnr)
  local line = vim.api.nvim_get_current_line()
  if vim.api.nvim_get_current_buf() ~= bufnr then return nil end
  return line:match("^%s*%*%s+(.+)%s*$")
end

local function step_pattern(template)
  local parts = { "^" }
  local offset = 1
  while true do
    local first, last = template:find("<[^>]+>", offset)
    if not first then
      parts[#parts + 1] = vim.pesc(template:sub(offset))
      break
    end
    parts[#parts + 1] = vim.pesc(template:sub(offset, first - 1))
    parts[#parts + 1] = ".+"
    offset = last + 1
  end
  parts[#parts + 1] = "$"
  return table.concat(parts)
end

--- Gaugeの手順文に一致するJava/Kotlinの@Step定義を探す。
function M.find_step_definitions(root, step)
  local files = vim.fs.find(function(name)
    return name:match("%.kt$") ~= nil or name:match("%.java$") ~= nil
  end, {
    path = root .. "/src/test",
    type = "file",
    limit = 100000,
  })
  local definitions = {}
  for _, path in ipairs(files) do
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok then
      for number, line in ipairs(lines) do
        local template = line:match('@Step%s*%(%s*"(.*)"%s*%)')
        if template then
          template = template:gsub('\\"', '"'):gsub("\\\\", "\\")
          if step:match(step_pattern(template)) then
            definitions[#definitions + 1] = { path = path, line = number }
          end
        end
      end
    end
  end
  return definitions
end

function M.is_expected_source_message(message)
  return message
    == "implementation source not found: Step implementation referred from an external project or library"
end

function M.show_message_handler(error, result, context, config)
  if result and M.is_expected_source_message(result.message) then return end
  return vim.lsp.handlers["window/showMessage"](error, result, context, config)
end

local function open_step_definition(root, step)
  local definitions = M.find_step_definitions(root, step)
  local function open(item)
    if not item then return end
    vim.cmd.edit(vim.fn.fnameescape(item.path))
    vim.api.nvim_win_set_cursor(0, { item.line, 0 })
  end

  if #definitions == 0 then
    vim.notify("Gaugeの手順実装が見つかりません", vim.log.levels.WARN)
  elseif #definitions == 1 then
    open(definitions[1])
  else
    vim.ui.select(definitions, {
      prompt = "Gaugeの手順実装",
      format_item = function(item)
        return vim.fn.fnamemodify(item.path, ":.") .. ":" .. item.line
      end,
    }, open)
  end
end

local function request_definition(client, bufnr, params, callback)
  local sent = client:request("textDocument/definition", params, function(error, result)
    callback(not error and has_definition({ { result = result } }))
  end, bufnr)
  if not sent then callback(false) end
end

local function compile(root, callback)
  local compiler = vim.uv.fs_stat(root .. "/mvnw") and "./mvnw" or "mvn"
  local before = source_stamp(root)
  vim.fn.mkdir(root .. "/logs", "p")
  vim.uv.fs_unlink(root .. "/" .. classpath_file)
  vim.notify("Gaugeの手順実装をコンパイルしています…", vim.log.levels.INFO)
  vim.system({
    compiler,
    "test-compile",
    "dependency:build-classpath",
    "-Dmdep.outputFile=" .. classpath_file,
    "-Dmdep.excludeArtifactIds=gauge-java",
  }, {
    cwd = root,
    text = true,
  }, function(result)
    vim.schedule(function()
      local output = (result.stdout or "") .. (result.stderr or "")
      vim.fn.writefile(vim.split(output, "\n", { plain = true }),
        root .. "/" .. compile_log)
      if result.code ~= 0 then
        vim.notify("Gaugeのコンパイルに失敗しました: " .. root .. "/" .. compile_log,
          vim.log.levels.ERROR)
      elseif before ~= source_stamp(root) then
        vim.notify("コンパイル中にGaugeの手順実装が更新されました。もう一度gdを実行してください",
          vim.log.levels.WARN)
      else
        vim.fn.writefile({ tostring(#source_files(root)) },
          root .. "/" .. compile_marker)
      end
      callback(result.code == 0 and before == source_stamp(root))
    end)
  end)
end

local function restart(client, bufnr, callback)
  local config = vim.deepcopy(client.config)
  -- ビルド後の再起動で同じ診断から自動ビルドを繰り返さない。
  config._viewer_gauge_auto_attempted = true
  local root = client.root_dir
  local buffers = vim.tbl_keys(client.attached_buffers)
  local group = vim.api.nvim_create_augroup(
    "ViewerGaugeRestart" .. client.id, { clear = true })
  local finished = false

  local function finish(ok)
    if finished then return end
    finished = true
    pcall(vim.api.nvim_del_augroup_by_id, group)
    callback(ok)
  end

  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      local attached = vim.lsp.get_client_by_id(ev.data.client_id)
      if attached and attached.name == "gauge" and attached.root_dir == root then
        for _, buffer in ipairs(buffers) do
          if vim.api.nvim_buf_is_valid(buffer) and buffer ~= ev.buf then
            vim.lsp.buf_attach_client(buffer, attached.id)
          end
        end
        finish(true)
      end
    end,
  })

  client:stop()
  local attempts = 0
  local function start_when_stopped()
    attempts = attempts + 1
    if client:is_stopped() then
      local id = vim.lsp.start(config, {
        bufnr = bufnr,
        reuse_client = function() return false end,
      })
      if not id then
        vim.notify("Gauge LSPを再起動できませんでした", vim.log.levels.ERROR)
        finish(false)
      end
      return
    end
    if attempts >= 100 then
      vim.notify("停止中のGauge LSPが終了しませんでした", vim.log.levels.ERROR)
      finish(false)
      return
    end
    vim.defer_fn(start_when_stopped, 50)
  end
  start_when_stopped()

  vim.defer_fn(function()
    if not finished then
      vim.notify("Gauge LSPの再起動がタイムアウトしました", vim.log.levels.ERROR)
      finish(false)
    end
  end, 15000)
end

local function has_missing_step(result)
  for _, diagnostic in ipairs(result.diagnostics or {}) do
    if diagnostic.severity == 1 and diagnostic.message == "Step implementation not found" then
      return true
    end
  end
  return false
end

--- 起動時の未実装診断に対して一度だけビルドする。
--- 状態は再起動時にも引き継ぐclient.configに保持する。
function M.on_diagnostics(result, deps)
  if not deps.client or not deps.is_maven then return end
  local config = deps.client.config
  if config._viewer_gauge_auto_attempted or not has_missing_step(result) then return end
  config._viewer_gauge_auto_attempted = true
  local root = deps.client.root_dir
  local key = root .. "\n" .. deps.source_stamp
  if deps.already_compiled or compiled_sources[key] or compiling_roots[root] then return end
  compiling_roots[root] = true
  deps.compile(root, function(ok)
    if not ok then
      compiling_roots[root] = nil
      return
    end
    compiled_sources[key] = true
    deps.restart(deps.client, deps.bufnr, function()
      compiling_roots[root] = nil
    end)
  end)
end

function M.publish_diagnostics_handler(error, result, context, config)
  vim.lsp.diagnostic.on_publish_diagnostics(error, result, context, config)
  if error or not result or not result.uri or not has_missing_step(result) then return end
  local client = vim.lsp.get_client_by_id(context.client_id)
  local bufnr = vim.fn.bufnr(vim.uri_to_fname(result.uri))
  -- Gaugeは未表示のspecにも診断を送る。開いたGaugeバッファだけ対象にする。
  if not client or client.name ~= "gauge" or client.config._viewer_gauge_auto_attempted or bufnr < 1
      or not vim.api.nvim_buf_is_loaded(bufnr) or vim.bo[bufnr].filetype ~= "gauge"
      or not client.attached_buffers[bufnr] then return end
  local root = client.root_dir
  if not root or not vim.uv.fs_stat(root .. "/pom.xml") then return end
  M.on_diagnostics(result, {
    client = client, bufnr = bufnr, is_maven = true,
    source_stamp = source_stamp(root), already_compiled = build_is_fresh(root),
    compile = compile, restart = restart,
  })
end

local function default_dependencies()
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "gauge" })
  local client = clients[1]
  local step = current_step(bufnr)
  local params
  if client then
    local win = vim.fn.bufwinid(bufnr)
    params = vim.lsp.util.make_position_params(
      win == -1 and 0 or win, client.offset_encoding)
  end
  return {
    bufnr = bufnr,
    is_gauge = vim.bo[bufnr].filetype == "gauge",
    is_maven = client and vim.uv.fs_stat(client.root_dir .. "/pom.xml") ~= nil,
    client = client,
    is_step_line = step ~= nil,
    source_stamp = client and source_stamp(client.root_dir) or "",
    already_compiled = client and build_is_fresh(client.root_dir) or false,
    request_definition = function(callback)
      if not client then
        callback(false)
        return
      end
      request_definition(client, bufnr, params, callback)
    end,
    compile = compile,
    restart = restart,
    after_restart = function(fallback)
      local restarted = vim.lsp.get_clients({ bufnr = bufnr, name = "gauge" })[1]
      if not restarted then
        fallback()
        return
      end
      request_definition(restarted, bufnr, params, function(found)
        if found then
          fallback()
        else
          open_step_definition(restarted.root_dir, step)
        end
      end)
    end,
    no_definition = function()
      open_step_definition(client.root_dir, step)
    end,
  }
end

--- Gaugeの定義を開く。LSPが手順実装を見つけられない場合だけ、
--- Kotlinを差分コンパイルしてLSPを再起動し、ジャンプを一度再試行する。
function M.definition(fallback, dependencies)
  local deps = dependencies or default_dependencies()
  if not deps.is_gauge or not deps.is_maven or not deps.client then
    fallback()
    return
  end

  deps.request_definition(function(found)
    if found or not deps.is_step_line then
      fallback()
      return
    end

    local root = deps.client.root_dir
    local compile_key = root .. "\n" .. deps.source_stamp
    if compiled_sources[compile_key] or deps.already_compiled then
      compiled_sources[compile_key] = true
      if deps.no_definition then
        deps.no_definition()
      else
        fallback()
      end
      return
    end
    if compiling_roots[root] then
      vim.notify("Gaugeの手順実装をコンパイル中です", vim.log.levels.INFO)
      return
    end

    compiling_roots[root] = true
    deps.compile(root, function(ok)
      if not ok then
        compiling_roots[root] = nil
        if deps.no_definition then deps.no_definition() end
        return
      end
      compiled_sources[compile_key] = true
      deps.restart(deps.client, deps.bufnr, function(restarted)
        compiling_roots[root] = nil
        if restarted and deps.after_restart then
          deps.after_restart(fallback)
        elseif deps.no_definition then
          deps.no_definition()
        else
          fallback()
        end
      end)
    end)
  end)
end

return M
