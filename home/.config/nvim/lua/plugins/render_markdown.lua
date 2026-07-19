return {
  'MeanderingProgrammer/render-markdown.nvim',
  ft = { 'markdown' },
  cmd = { 'RenderMarkdown' },
  opts = {
    heading = {
      icons = { '󰎥 ', '󰎨 ', '󰎫 ', '󰎲 ', '󰎯 ', '󰎴 ' },
    },
  },
  keys = {
    {
      '<leader>mr',
      '<cmd>RenderMarkdown toggle<cr>',
      ft = 'markdown',
      desc = 'Toggle Markdown Render',
    },
  },
}
