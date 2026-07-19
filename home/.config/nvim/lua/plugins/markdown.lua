return {
  'brianhuster/live-preview.nvim',
  ft = { 'markdown' },
  cmd = { 'LivePreview' },
  keys = {
    {
      '<leader>mp',
      '<cmd>LivePreview start<cr>',
      ft = 'markdown',
      desc = 'Markdown Preview',
    },
  },
}
