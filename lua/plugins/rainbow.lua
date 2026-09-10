return {
  {
    "HiPhish/rainbow-delimiters.nvim",
    -- 実行時コードとClojure queryを安全性確認した版に固定する。
    commit = "3a0fc08dd39e8bf034a4cfef3f2845bd5f565a2e",
    lazy = false,
    init = function()
      vim.g.rainbow_delimiters = {
        whitelist = { "clojure" },
        strategy = { [""] = "rainbow-delimiters.strategy.global" },
      }
    end,
  },
}
