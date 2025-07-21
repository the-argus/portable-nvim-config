local is_okay, configs = pcall(require, 'nvim-treesitter.configs')
if not is_okay then
    return
end

-- check if parsers are successfully installed with
-- :echo nvim_get_runtime_file('parser/*.so', v:true)
configs.setup {
    ensure_installed = {}, -- installed and build with portable nvim config
    sync_install = false,

    highlight = {
        -- `false` will disable the whole extension
        enable = true,

        -- list of language that will be disabled
        -- disable = { "c", "rust" },
    },

    rainbow = {
        enable = true,
        -- disable = { "jsx", "cpp" }, list of languages you want to disable the plugin for
        extended_mode = true, -- Also highlight non-bracket delimiters like html tags, boolean or table: lang -> boolean
        max_file_lines = nil, -- Do not enable for files with more than n lines, int
        -- colors = {}, -- table of hex strings
        -- termcolors = {} -- table of colour name strings
    }
}
