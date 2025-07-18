local di_present, devicons = pcall(require, 'nvim-web-devicons')
if not di_present then
    return
end

local function make_monochrome()
    -- get all icons
    local icons = devicons.get_icons()

    -- make all icons monochrome, base05 in the current colorscheme
    for _, icon_style in pairs(icons) do
        local higroupname = "DevIcon" .. icon_style.name
        local style = "ctermfg=7 guifg=#" .. require('base16-colorscheme').colors.base05
        vim.cmd(string.format("highlight %s %s", higroupname, style))
    end

    devicons.setup({
        override = icons
    })
end

local augroup = vim.api.nvim_create_augroup("DeviconsConfig", {})

-- autocommand to make monochrome whenever the color scheme is changed
vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = make_monochrome,
})

make_monochrome()
