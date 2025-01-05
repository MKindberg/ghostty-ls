# Ghostty-ls
A language server providing the following features

|  |  |
|--- | ---|
| Hover | Show help text when hovering an option |
| Completion | Autocomplete options, themes, fonts and colors |
| Formatting | Add spaces around the first = after an option and after the # in comments |

## Installation
### Neovim
1. Download the binary from releases and put it in your PATH or use Mason by adding `"github:mkindberg/ghostty-ls"` as a registry in the config.
2. Install the plugin and run its setup function, eg in Lazy.nvim:
`{"mkindberg/ghostty-ls", config = true},`
or set it up manually by adding the following code to your config
   ```lua
    local function setup_ghostty_ls()
        local client = vim.lsp.start_client { name = "ghostty-ls", cmd = { "ghostty-ls" }, }

        if not client then
            vim.notify("Failed to start ghostty-ls")
        else
            vim.api.nvim_create_autocmd("FileType",
                { pattern = "ghostty", callback = function() vim.lsp.buf_attach_client(0, client) end }
            )
        end
    end
    setup_ghostty_ls()
   ```
### Visual Studio Code
1. Download the vsix file and install it with `code --install-extension ghostty-ls-0.0.1.vsix`
2. Open the config file and change the language to ghostty in the bottom right corner.
