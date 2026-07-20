return {
  'MeanderingProgrammer/render-markdown.nvim',
  dependencies = {
    {
      'nvim-tree/nvim-web-devicons',
      opts = {
        color_icons = true,
        override = {
          sh = {
            icon = '',
            color = '#f6c177',
            name = 'Sh',
          },
        },
      },
    },
  },
  ft = { 'markdown' },
  cmd = { 'RenderMarkdown' },
  opts = {
    code = {
      style = 'full',
      language = true,
      position = 'right',
      language_icon = true,
      language_name = true,
      width = 'full',
      border = 'hide',
    },
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
