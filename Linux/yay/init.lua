-- yay Lua configuration (~/.config/yay/init.lua)
--
-- Minimum release-age gate for AUR packages.
--
-- After the mid-2025 AUR malware flood (malicious PKGBUILDs pushed to popular
-- packages and pulled within hours), yay v13 exposes an `UpgradeSelect` hook so
-- users can hold back freshly-modified AUR packages until they've "aged" enough
-- for the compromise to be noticed and removed. There is no built-in config key
-- for this; it is implemented here via Lua.
--
-- Behaviour: during `yay -Syu` / `yay -Sua`, any AUR package whose PKGBUILD was
-- last modified less than MIN_AGE_DAYS ago is excluded from this upgrade. It will
-- be offered again automatically once it crosses the age threshold. Repo (pacman)
-- packages are never affected. The native exclude menu is still shown so the
-- decision can be reviewed/overridden interactively.

local MIN_AGE_DAYS = 7

yay.create_autocmd("UpgradeSelect", {
  desc = "hold back AUR packages modified in the last " .. MIN_AGE_DAYS .. " days",
  callback = function(event)
    local exclude = {}
    local cutoff = os.time() - (MIN_AGE_DAYS * 24 * 60 * 60)

    for _, pkg in ipairs(event.data.upgrades) do
      if pkg.repository == "aur"
        and pkg.last_modified ~= nil
        and pkg.last_modified >= cutoff
      then
        table.insert(exclude, pkg.name)
      end
    end

    -- skip_menu = false: still show yay's native selection menu so a held-back
    -- package can be re-included manually if you've verified it yourself.
    return { exclude = exclude, skip_menu = false }
  end,
})
