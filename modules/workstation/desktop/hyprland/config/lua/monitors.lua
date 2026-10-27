-- Known monitors, matched by description (stable across ports and docks; see
-- `hyprctl monitors all`). Plain data: monitor_policy.lua applies it.
--
-- `priority` picks the primary monitor (bar, notifications, workspaces 1-5):
-- the enabled monitor with the highest one wins. Unknown monitors get
-- `unknown_priority`. `internal = true` marks a laptop panel, which the policy
-- switches off while an external monitor is connected.
--
-- Monique (or any experiment) can go in monitors.local.lua next to this file
-- (git-ignored); it's applied after these and wins.
return {
    unknown_priority = 20,

    -- Anything not listed below.
    fallback = { mode = "preferred", position = "auto", scale = "auto" },

    list = {
        {
            name = "acer", -- hephaestus' main screen, 4K 144 Hz
            desc = "Acer Technologies X32Q FS 1414012CC3E00",
            priority = 100,
            mode = "3840x2160@143.98",
            position = "1600x0",
            scale = 2,
            bitdepth = 10,
        },
        {
            name = "tv", -- Philips TV downstairs
            desc = "Philips Consumer Electronics Company Philips FTV 0x01010101",
            priority = 90,
            mode = "3840x2160@120",
            position = "1440x0",
            scale = 2.5,
            bitdepth = 10,
            cm = "srgb",
            sdr_min_luminance = 0.2,
            sdr_max_luminance = 80,
        },
        {
            name = "nreal", -- Nreal Air 2 Pro glasses
            desc = "Nreal Air 2 Pro 0x88888800",
            priority = 80,
            mode = "1920x1080@120",
            position = "auto",
            scale = 1,
        },
        {
            name = "lg", -- hephaestus' second screen, left of the acer
            desc = "LG Electronics LG ULTRAGEAR 111MAXSP2986",
            priority = 50,
            mode = "2560x1440@144",
            position = "0x90",
            scale = 1.6,
        },
        {
            name = "laptop", -- hermes' panel (Framework 13)
            desc = "BOE NE135A1M-NY1",
            priority = 10,
            internal = true,
            mode = "preferred",
            position = "auto",
            scale = "auto",
        },
    },
}
