local treesitter_parsers = {
  'bash',
  'go',
  'javascript',
  'json',
  'lua',
  'markdown',
  'markdown_inline',
  'nix',
  'python',
  'rust',
  'toml',
  'tsx',
  'typescript',
  'yaml',
}

return {
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = function()
      local treesitter = require('nvim-treesitter')
      local options = { max_jobs = 1 }

      treesitter.install(treesitter_parsers, options):wait(300000)
      treesitter.update(treesitter_parsers, options):wait(300000)
    end,
    parsers = treesitter_parsers,
    config = function()
      local treesitter = require('nvim-treesitter')
      treesitter.setup()
      vim.treesitter.language.register('bash', { 'sh', 'bash', 'zsh' })
    end,
  },
  {
    'saghen/blink.cmp',
    version = '1.*',
    opts = {
      keymap = { preset = 'default' },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 300 },
        menu = { border = 'rounded' },
      },
      signature = { enabled = true, window = { border = 'rounded' } },
    },
  },
  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = { 'saghen/blink.cmp' },
    config = function()
      vim.lsp.config('*', {
        capabilities = require('blink.cmp').get_lsp_capabilities(),
      })
      vim.lsp.enable({ 'basedpyright', 'gopls', 'bashls' })

      vim.diagnostic.config({
        severity_sort = true,
        signs = true,
        underline = true,
        update_in_insert = false,
        virtual_text = false,
        float = { border = 'rounded', source = true },
      })
    end,
    keys = {
      { 'K', vim.lsp.buf.hover, desc = 'Hover Documentation' },
      { '<leader>ca', vim.lsp.buf.code_action, desc = 'Code Action' },
      { '<leader>rn', vim.lsp.buf.rename, desc = 'Rename Symbol' },
      { '<leader>d', vim.diagnostic.open_float, desc = 'Line Diagnostics' },
    },
  },
  {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>cf',
        function() require('conform').format({ async = true, lsp_format = 'fallback' }) end,
        desc = 'Format Buffer',
      },
    },
    opts = {
      formatters_by_ft = {
        python = { 'ruff_format' },
        go = { 'goimports' },
        sh = { 'shfmt' },
        bash = { 'shfmt' },
        zsh = { 'shfmt' },
      },
      format_on_save = {
        timeout_ms = 1000,
        lsp_format = 'fallback',
      },
    },
  },
}
