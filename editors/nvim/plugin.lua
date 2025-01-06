local M = {}
M.setup = function()
    local autocmd = vim.api.nvim_create_autocmd
    autocmd("FileType", {
        pattern = "ghostty",
        callback = function()
            local client = vim.lsp.start({
                name = 'ghostty-ls',
                cmd = { 'ghostty-ls' },
            })
            if not client then
                vim.notify("Failed to start ghostty-ls")
            else
                vim.lsp.buf_attach_client(0, client)
            end
        end
    })
end
return M
