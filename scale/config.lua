Config = {}

-- ─────────────────────────────────────────────────────────────────────
--  FRAMEWORK
--  Options: 'ESX' | 'QB' | 'Qbox' | 'Custom' | 'None'
-- ─────────────────────────────────────────────────────────────────────
Config.Framework = 'ESX'

-- ─────────────────────────────────────────────────────────────────────
--  SAVE TO CHARACTER
--  true  = player heights persist in the database per character
--  false = heights reset each session
--  Requires: oxmysql or mysql-async to be installed & running
-- ─────────────────────────────────────────────────────────────────────
Config.SaveToChar = true

-- ─────────────────────────────────────────────────────────────────────
--  COMMANDS
-- ─────────────────────────────────────────────────────────────────────
Config.Commands = {
    menu = {
        name = 'scalemenu',             -- Command to open menu
        help = 'Opens the ped scale menu'
    },
    give = {
        name = 'givescalemenu',         -- Command to give access to players
        help = 'Grant ped scale access to a player'
    },
    reset = {
        name = 'resetscale',            -- Command to reset player\'s scale
        help = 'Reset a player\'s ped scale'
    }
}

-- ─────────────────────────────────────────────────────────────────────
--  SCALE RANGE
--  Defaults represent realistic human height extremes.
--    MinScale  0.806  ≈  4'10" / 147 cm
--    MaxScale  1.194  ≈  7'2"  / 218 cm
--
--  WARNING: Values above ~4.5 may produce physics / animation issues.
-- ─────────────────────────────────────────────────────────────────────
Config.MinScale     = 0.806
Config.MaxScale     = 1.194
Config.DefaultScale = 1.0       -- 6'0" / 183 cm (GTA average)

-- ─────────────────────────────────────────────────────────────────────
--  GENDER RESTRICTION
--  false    = any gender may open the menu
--  'male'   = only male peds may open the menu
--  'female' = only female peds may open the menu
-- ─────────────────────────────────────────────────────────────────────
Config.GenderRestriction = false

-- ─────────────────────────────────────────────────────────────────────
--  WEAPON BLOCKING
--  Prevents weapon use while the player is at a non-default scale.
--  Recommended due to hitbox and animation discrepancies.
--  Also blocks Ox Inventory hotbar if ox_inventory is detected.
-- ─────────────────────────────────────────────────────────────────────
Config.BlockWeapons = true

-- ─────────────────────────────────────────────────────────────────────
--  UI THEME
--  Main accent colour used throughout the interface (hex with #)
--  Players can see a live preview of their accent via this setting.
-- ─────────────────────────────────────────────────────────────────────
Config.ThemeColor = '#1A6BFF'

-- ─────────────────────────────────────────────────────────────────────
--  PERMISSIONS / WHITELIST
-- ─────────────────────────────────────────────────────────────────────
Config.Permissions = {

    -- Set to true to restrict menu access (Discord roles OR identifiers)
    UseWhitelist = false,

    -- Discord Role IDs that are permitted to open the scale menu
    AllowedDiscordRoles = {
        -- '123456789012345678',
        -- '987654321098765432',
    },

    -- License / Discord identifiers that are permitted to open the menu
    AllowedIdentifiers = {
        -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
        -- 'discord:123456789012345678',
    },
}

-- ─────────────────────────────────────────────────────────────────────
--  DISCORD API  (only required when AllowedDiscordRoles is populated)
--
--  Setup:
--  1. Create a bot at https://discord.com/developers/applications
--  2. Copy the bot token and paste it into Token below
--  3. Right-click your server icon → Copy Server ID → paste into Guild
-- ─────────────────────────────────────────────────────────────────────
Config.Discord = {
    Token = '',     -- 'Bot token here'
    Guild = '',     -- 'Guild (server) ID here'
}
