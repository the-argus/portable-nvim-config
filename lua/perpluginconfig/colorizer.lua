local okay, colorizer = pcall(require, 'colorizer')

if not okay then
    return
end

_M = {
    config = {
        "*",
        "!txt",
    },
    defaults = {
        mode     = "foreground";
        RGB      = true; -- #RGB hex codes
        RRGGBB   = true; -- #RRGGBB hex codes
        names    = false;
        RRGGBBAA = true; -- #RRGGBBAA hex codes
        rgb_fn   = true; -- CSS rgb() and rgba() functions
        hsl_fn   = true; -- CSS hsl() and hsla() functions
        css      = true; -- Enable all CSS features: rgb_fn, hsl_fn, names, RGB, RRGGBB
        css_fn   = true; -- Enable all CSS *functions*: rgb_fn, hsl_fn
    }
}

colorizer.setup(_M.config, _M.defaults)
