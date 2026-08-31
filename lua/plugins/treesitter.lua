-- ===================================================================
-- lua/plugins/treesitter.lua : 高精度シンタックスハイライト
-- （コードビューアーの視認性のために追加）
--
-- 注意: Neovim 0.11+ では `main` ブランチを使うこと。
-- 旧 `master` ブランチは query_predicates が 0.12 の treesitter API と
-- 噛み合わず、マークダウンの injection 解析で実行時エラーになる:
--   treesitter.lua: attempt to call method 'range' (a nil value)
-- main ブランチではハイライトが自動で有効にならないため、
-- FileType で vim.treesitter.start() を自分で呼ぶ必要がある。
-- ===================================================================

local ENSURE = {
  -- 注意: main ブランチに jsonc は無い（json が jsonc も扱う）
  "bash", "c", "css", "diff", "go", "html", "javascript", "json",
  "lua", "luadoc", "markdown", "markdown_inline", "python", "query", "regex",
  "ruby", "rust", "sql", "toml", "tsx", "typescript", "vim", "vimdoc", "yaml",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    priority = 900,
    build = ":TSUpdate",
    config = function()
      local ok, ts = pcall(require, "nvim-treesitter")
      if not ok then return end
      ts.setup({})

      -- 未導入のパーサーだけをまとめて入れる
      local installed = {}
      if ts.get_installed then
        for _, name in ipairs(ts.get_installed() or {}) do
          installed[name] = true
        end
      end
      local missing = {}
      for _, lang in ipairs(ENSURE) do
        if not installed[lang] then table.insert(missing, lang) end
      end
      if #missing > 0 then
        pcall(function() ts.install(missing) end)
      end

      -- ファイルを開いたらハイライトを開始する
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("ViewerTreesitter", { clear = true }),
        callback = function(ev)
          -- 特殊バッファ（プラグインのUI）ではハイライトしない
          if vim.bo[ev.buf].buftype ~= "" then return end
          local lang = vim.treesitter.language.get_lang(vim.bo[ev.buf].filetype)
          if not lang then return end
          pcall(vim.treesitter.start, ev.buf, lang)
        end,
      })

      -- 導入済みパーサーを確認するコマンド
      vim.api.nvim_create_user_command("TSInstalled", function()
        local list = ts.get_installed and ts.get_installed() or {}
        table.sort(list)
        vim.notify(("パーサー %d 件:\n%s"):format(#list, table.concat(list, ", ")),
          vim.log.levels.INFO)
      end, { desc = "導入済みの treesitter パーサーを表示" })
    end,
  },
}
