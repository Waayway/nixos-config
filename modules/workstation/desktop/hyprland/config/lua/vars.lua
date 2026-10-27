-- Programs and the main modifier, shared by binds.lua and autostart.lua.
return {
    mod = "SUPER",
    terminal = "ghostty",
    browser = "firefox",
    files = "nemo",
    launcher = "rofi -show drun -theme ~/.config/rofi/theme.rasi",
    scripts = os.getenv("HOME") .. "/.config/hypr/scripts",
}
