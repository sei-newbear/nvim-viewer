return {
  {
    "lewis6991/gitsigns.nvim",
    commit = "f2421c550618d257048afa650413d9e542ddbe67",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signcolumn = true,
      numhl = true,
      linehl = false,
      word_diff = false,
      attach_to_untracked = true,
      current_line_blame = false,
    },
    config = function(_, opts)
      local function highlights()
        for name, color in pairs({ Add = "#80c990", Change = "#6ca9ed", Delete = "#ef8791" }) do
          vim.api.nvim_set_hl(0, "GitSigns" .. name, { fg = color })
          vim.api.nvim_set_hl(0, "GitSigns" .. name .. "Nr", { fg = color })
        end
      end
      highlights()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("ViewerGitSigns", { clear = true }),
        callback = highlights,
      })
      -- 閲覧用途。ステージ／変更取り消し用のキーは設定しない。
      require("gitsigns").setup(opts)
    end,
  },
}
