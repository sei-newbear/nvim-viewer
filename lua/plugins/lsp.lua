-- ===================================================================
-- lua/plugins/lsp.lua : コード追跡(定義ジャンプ)用のLSP設定
-- ビューアー用途なので「読む」機能のみ有効化する
-- （補完・フォーマット・コード修正は入れない）
-- ===================================================================
return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      -- 検出対象: { lspconfig名, 実行ファイル名, skip_if = 先に採る方 }
      -- 実際にインストールされているものだけを有効化する。
      -- ここに無い言語サーバは、そのマシンに入っていても有効にならない。
      -- 使いたいものがあれば、この表に足すこと（名前は lspconfig の
      -- `lsp/<名前>.lua` に一致していないと黙って無視される）。
      --
      -- skip_if は「同じ言語に複数のサーバが入っている」ときの優先順位。
      -- 両方を有効にすると診断が二重に出て読みにくくなる。
      local candidates = {
        -- スクリプト・設定
        { "lua_ls",         "lua-language-server" },
        { "bashls",         "bash-language-server" },
        { "jsonls",         "vscode-json-language-server" },
        { "yamlls",         "yaml-language-server" },
        { "taplo",          "taplo" },                     -- TOML
        { "marksman",       "marksman" },                  -- Markdown
        { "dockerls",       "docker-langserver" },
        { "terraformls",    "terraform-ls" },

        -- JavaScript / TypeScript 系
        { "vtsls",          "vtsls" },
        { "ts_ls",          "typescript-language-server", skip_if = "vtsls" },
        { "denols",         "deno" },                      -- Deno プロジェクトでのみ接続する
        { "eslint",         "vscode-eslint-language-server" },
        { "html",           "vscode-html-language-server" },
        { "cssls",          "vscode-css-language-server" },
        { "tailwindcss",    "tailwindcss-language-server" },
        { "svelte",         "svelteserver" },

        -- コンパイル言語
        { "gopls",          "gopls" },
        { "rust_analyzer",  "rust-analyzer" },
        { "clangd",         "clangd" },                    -- C / C++
        { "zls",            "zls" },                       -- Zig
        { "jdtls",          "jdtls" },                     -- Java
        { "kotlin_language_server", "kotlin-language-server" },
        { "hls",            "haskell-language-server-wrapper" },
        { "ocamllsp",       "ocamllsp" },
        { "metals",         "metals" },                    -- Scala
        -- Dart は実行ファイルが SDK 本体（dart language-server）
        { "dartls",         "dart" },

        -- 動的言語
        { "pyright",        "pyright-langserver" },
        { "ruff",           "ruff" },                      -- pyright と併用してよい（役割が違う）
        { "ruby_lsp",       "ruby-lsp" },
        { "solargraph",     "solargraph",   skip_if = "ruby_lsp" },
        { "intelephense",   "intelephense" },              -- PHP
        { "phpactor",       "phpactor",     skip_if = "intelephense" },
        { "clojure_lsp",    "clojure-lsp" },
      }

      local enabled = {}
      for _, c in ipairs(candidates) do
        local name, bin = c[1], c[2]
        if vim.fn.executable(bin) == 1
          and not (c.skip_if and vim.tbl_contains(enabled, c.skip_if)) then
          table.insert(enabled, name)
        end
      end

      if #enabled > 0 then
        -- Neovim 0.11+ / nvim-lspconfig v2 の新API
        if vim.lsp.enable then
          vim.lsp.enable(enabled)
        else
          local ok, lspconfig = pcall(require, "lspconfig")
          if ok then
            for _, name in ipairs(enabled) do
              pcall(function() lspconfig[name].setup({}) end)
            end
          end
        end
      end

      vim.g.viewer_lsp_enabled = enabled

      -- 有効なLSPを確認するコマンド
      vim.api.nvim_create_user_command("LspEnabled", function()
        local list = vim.g.viewer_lsp_enabled or {}
        if #list == 0 then
          vim.notify("有効な言語サーバはありません（定義ジャンプにはLSPのインストールが必要です）",
            vim.log.levels.WARN)
        else
          vim.notify("有効な言語サーバ: " .. table.concat(list, ", "), vim.log.levels.INFO)
        end
      end, { desc = "有効になっている言語サーバを表示" })

      -- ---- 診断表示（閲覧向けに控えめに） ----
      vim.diagnostic.config({
        virtual_text = { spacing = 2, prefix = "●" },
        signs = true,
        underline = true,
        severity_sort = true,
        float = { border = "rounded", source = true },
      })

      -- ---- コード追跡用キーマップ ----
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("ViewerLspAttach", { clear = true }),
        callback = function(ev)
          local function map(keys, fn, desc)
            vim.keymap.set("n", keys, fn, { buffer = ev.buf, silent = true, desc = "LSP: " .. desc })
          end
          -- 注意: gd / gD / gy / gi / gr は「候補が複数なら一覧を出す」版を
          -- plugins/snacks.lua でグローバルに定義している。ここでバッファローカルに
          -- 定義すると そちらが優先されてピッカーが効かなくなるため定義しない。
          map("K",  vim.lsp.buf.hover,           "ホバー表示")
          map("[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, "前の診断へ")
          map("]d", function() vim.diagnostic.jump({ count = 1, float = true }) end,  "次の診断へ")
          map("<leader>i", vim.diagnostic.open_float, "診断の詳細")
          -- ジャンプ元へ戻る
          map("<C-o>", "<C-o>", "前の位置へ戻る")
        end,
      })
    end,
  },
}
