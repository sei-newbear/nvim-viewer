-- ===================================================================
-- lua/plugins/which-key.lua
-- プレフィックスキーを押すと、続けて押せるキーの候補を表示する
--
-- 注意: herdr のキー（Ctrl+b 系）は Neovim の外で処理されるため、
-- which-key には出てこない。2層まとめて見たい場合は `?`（custom/cheatsheet.lua）。
-- ===================================================================
return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "helix",
      delay = 350, -- ミリ秒。押してからこの時間で候補が出る
      icons = {
        mappings = false, -- アイコン用フォントに依存しないようにする
        keys = {},
      },
      -- 説明の付いていないキーは出さない（ノイズを減らす）
      filter = function(mapping)
        return mapping.desc ~= nil and mapping.desc ~= ""
      end,
      spec = {
        -- グループ名は「実際にプレフィックスになっているキー」だけに付ける。
        -- 単独で機能するキー（<leader>f など）に group を付けると、
        -- 本来の説明が上書きされてしまう。
        { "<leader>d", group = "差分 (Diffview)" },
        { "g",         group = "ジャンプ (LSP)" },
        { "]",         group = "次へ" },
        { "[",         group = "前へ" },
      },
      win = {
        border = "rounded",
      },
    },
    keys = {
      {
        "<leader>?",
        function() require("snacks").picker.keymaps() end,
        desc = "全キーマップを検索する",
      },
    },
  },
}
