local M = {}
M.setup = function()
    local client = vim.lsp.start_client { name = "ghostty-ls", cmd = { "ghostty-ls" }, }

    if not client then
        vim.notify("Failed to start ghostty-ls")
    else
        vim.api.nvim_create_autocmd("FileType",
            { pattern = { "ghostty", }, callback = function() vim.lsp.buf_attach_client(0, client) end }
        )
    end
end
return M

