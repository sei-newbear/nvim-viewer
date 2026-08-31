-- ===================================================================
-- lua/plugins/markdown.lua
-- マークダウンをバッファ内で整形して表示する
--
-- 画像プロトコルを使わないため、どのターミナル・多重化環境でも動く。
-- 見出し・表・コードブロック・箇条書きがその場で装飾される。
-- ===================================================================
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    ft = { "markdown", "codecompanion" },
    opts = {
      -- 閲覧専用ビューアーなので常に描画したままにする
      -- （編集用途では insert モードで生に戻す設定が普通だが、ここでは不要）
      render_modes = { "n", "v", "i", "c", "V", "\22" },

      heading = {
        sign = false,
        width = "block",
        left_pad = 0,
        right_pad = 2,
        icons = { "# ", "## ", "### ", "#### ", "##### ", "###### " },
      },

      code = {
        sign = false,
        width = "block",
        right_pad = 2,
        left_pad = 1,
        language_pad = 1,
        border = "thick",
      },

      bullet = {
        icons = { "•", "◦", "▪", "▫" },
      },

      checkbox = {
        unchecked = { icon = "☐ " },
        checked   = { icon = "☑ " },
      },

      pipe_table = {
        preset = "round",   -- 罫線で表を組む
        alignment_indicator = "─",
      },

      link = {
        image = "󰥶 ",
        hyperlink = "󰌹 ",
      },

      -- 引用や区切り線
      quote = { icon = "▎" },
      dash = { icon = "─" },
    },
    keys = {
      {
        "<leader>m",
        function() require("custom.md_view").toggle() end,
        desc = "整形表示 ⇄ 生ファイル を切り替え",
        ft = "markdown",
      },
    },
  },
}
