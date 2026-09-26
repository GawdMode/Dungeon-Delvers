-- Dungeon Delvers
-- Gen 2 Summary Page 4: Ancient Resilience
--
-- Based directly on Crystal National Dex Randomizer DEV15's orange Ability
-- summary page. Ancient Dungeon Delvers Pokemon get a fourth page showing
-- Ancient Resilience. If Crystal National Dex Randomizer is also enabled,
-- its ordinary ability-page behavior is preserved for non-Ancient Pokemon.

local M = {}

local ABILITY_PAGE = 4

local PAGE_PALETTES = {
  { { 255, 255, 255 }, { 255, 156, 255 }, { 255, 123, 255 }, { 0, 0, 0 } },
  { { 255, 255, 255 }, { 173, 255, 115 }, { 140, 255,   0 }, { 0, 0, 0 } },
  { { 255, 255, 255 }, { 140, 255, 255 }, { 140, 255, 255 }, { 0, 0, 0 } },
  { { 255, 255, 255 }, { 255, 206, 123 }, { 255, 156,   0 }, { 0, 0, 0 } },
}

local ORANGE_TINT = { 255, 206, 123 }
local ORANGE_LOWER = {
  ORANGE_TINT, ORANGE_TINT, ORANGE_TINT, { 0, 0, 0 },
}

local function normalizeAbilityId(value)
  if type(value) ~= "string" or value == "" then return nil end
  local id = value:upper():gsub("[^%w]", "")
  if id == "" or id == "NONE" or id == "NOABILITY" then return nil end
  return id
end

local function sanitize(text)
  text = tostring(text or "")
  text = text:gsub("×", "x")
  text = text:gsub("’", "'")
  text = text:gsub("‘", "'")
  text = text:gsub("“", '"')
  text = text:gsub("”", '"')
  text = text:gsub("–", "-")
  text = text:gsub("—", "-")
  return text
end

local function findMod(mod, id)
  local ok, found = pcall(function() return mod:find(id) end)
  if ok then return found end
  return nil
end

local function g9Ability(mod, mon)
  local g9 = findMod(mod, "g9-battle-engine")
  local exports = g9 and g9.exports
  local fn = exports and exports.abilityIdOf
  if type(fn) ~= "function" then return nil end

  -- Gen9Dex's public resolver is written to accept a battler or its raw mon.
  -- Try the raw party mon first, then the same lightweight battler shape its
  -- own combat helpers commonly use.
  local ok, value = pcall(fn, mon)
  local id = ok and normalizeAbilityId(value) or nil
  if id then return id end

  ok, value = pcall(fn, { mon = mon })
  id = ok and normalizeAbilityId(value) or nil
  return id
end

local function explicitMonAbility(mon)
  if type(mon) ~= "table" then return nil end
  local fields = {
    "abilityId", "ability", "g9Ability", "modernAbility",
  }
  for _, key in ipairs(fields) do
    local id = normalizeAbilityId(mon[key])
    if id then return id end
  end
  if type(mon.modern) == "table" then
    local id = normalizeAbilityId(mon.modern.abilityId or mon.modern.ability)
    if id then return id end
  end
  return nil
end

local function speciesFallback(dexMod, mon)
  if not (dexMod and dexMod.exports and
      type(dexMod.exports.statsBySpecies) == "function" and
      type(mon) == "table" and type(mon.species) == "string") then
    return nil
  end

  local ok, stats = pcall(dexMod.exports.statsBySpecies, mon.species)
  if not ok or type(stats) ~= "table" or type(stats.abilities) ~= "table" then
    return nil
  end

  -- If another modern-stat implementation persisted an ability slot, respect
  -- it. National Dex uses slots 1/2/3 (3 = hidden).
  local wanted = tonumber(mon.abilitySlot or mon.abilityIndex)
  if wanted then
    for _, entry in ipairs(stats.abilities) do
      if tonumber(entry.slot) == wanted and entry.name then
        return normalizeAbilityId(entry.name)
      end
    end
  end

  -- Safe display fallback when no individual assignment API exists: the
  -- species' first ordinary ability, matching the conventional slot-1 default.
  for _, entry in ipairs(stats.abilities) do
    if not entry.hidden and entry.name then
      return normalizeAbilityId(entry.name)
    end
  end
  local first = stats.abilities[1]
  return first and normalizeAbilityId(first.name) or nil
end

local function isAncient(mon)
  return type(mon) == "table" and type(mon.pewterAncient) == "table"
end

local function abilityInfo(mod, dexMod, mon)
  if isAncient(mon) then
    return "ANCIENT RESILIENCE",
      "Reduces super-effective damage by one type tier."
  end

  local id = g9Ability(mod, mon)
    or explicitMonAbility(mon)
    or speciesFallback(dexMod, mon)

  if not id then
    return "-----", "No ability data is available for this Pokemon."
  end

  local rec
  if dexMod and dexMod.exports and type(dexMod.exports.abilityById) == "function" then
    local ok, value = pcall(dexMod.exports.abilityById, id)
    if ok and type(value) == "table" then rec = value end
  end

  local name = rec and rec.name or id:gsub("_", " ")
  local desc = rec and (rec.shortEffect or rec.effect)
    or "No description is available for this ability."

  return sanitize(name):upper(), sanitize(desc)
end

local function isEgg(mon)
  return type(mon) == "table" and mon.isEgg == true
end

local function wrapLines(TextBox, text, width)
  local pages = TextBox.paginate(text or "", width)
  return (pages and pages[1]) or {}
end


local moveDescriptionCache = {}

local function cleanMoveDescription(record)
  if type(record) ~= "table" then return nil end
  local text = tostring(record.shortEffect or record.effect or "")
  if text == "" then return nil end

  local chance = tonumber(record.effectChance) or tonumber(record.ailmentChance)
    or tonumber(record.flinchChance) or tonumber(record.statChance)
  text = text:gsub("%$effect_chance%%", chance and (tostring(chance) .. "%%") or "")
  text = text:gsub("%$([^%s]+)", "")
  text = text:gsub("Pok[eé]mon", "POKéMON")
  text = text:gsub("Inflicts regular damage with no additional effect%.",
                   "Inflicts regular damage.")
  text = text:gsub("Inflicts regular damage%.", "Inflicts damage.")
  text = text:gsub("%s+", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

local function twoLineDescription(text, width)
  width = width or 18
  if type(text) ~= "string" or text == "" then return nil end
  local words = {}
  for word in text:gmatch("%S+") do words[#words + 1] = word end
  local lines, line = {}, ""
  for _, word in ipairs(words) do
    local candidate = line == "" and word or (line .. " " .. word)
    if #candidate <= width then
      line = candidate
    else
      if line ~= "" then lines[#lines + 1] = line end
      line = word
      if #lines >= 2 then break end
    end
  end
  if #lines < 2 and line ~= "" then lines[#lines + 1] = line end

  if #lines == 0 then return nil end
  -- The vanilla detail box only has two description rows.
  if #lines > 2 then lines[3] = nil end
  return table.concat(lines, "<NEXT>")
end

function M.install(mod)
  local randomizerMod = findMod(mod, "crystal_ndex_randomizer")
  local dexMod = findMod(mod, "national_dex")
  local preserveRandomizerAbilities = randomizerMod ~= nil and dexMod ~= nil

  local okSummary, Builtin = pcall(require, "src.ui.gen2.SummaryMenu")
  local okChrome, Chrome = pcall(require, "src.ui.gen2.Chrome")
  local okFont, Font = pcall(require, "src.render.Font")
  local okPalette, GbcPalette = pcall(require, "src.render.GbcPalette")
  local okText, TextBox = pcall(require, "src.render.TextBox")

  if not (okSummary and Builtin and Builtin.new and
      okChrome and Chrome and okFont and Font and
      okPalette and GbcPalette and okText and TextBox) then
    return false, "Gen 2 SummaryMenu dependencies unavailable"
  end

  local pinkPage = Builtin.PINK_PAGE or 1
  local greenPage = Builtin.GREEN_PAGE or 2

  local function wrapSummary(game, opts)
    local self = Builtin.new(game, opts)
    -- Capture the live downstream renderer at summary creation time. Other
    -- mods (for example Viridian Vivarium's Prime/insect badge) can wrap the
    -- stock SummaryMenu after Dungeon Delvers loads. Ordinary Pokemon should
    -- keep that downstream upper-half renderer intact; only Ancient Pokemon
    -- need our custom four-page upper half.
    local downstreamDrawUpperHalf = self.drawUpperHalf

    -- Vanilla Crystal move detail already has a two-line description area.
    -- National Dex carries modern move prose outside the live move registry,
    -- so fill only blank descriptions lazily when that page asks for one.
    local baseMoveDef = self.moveDef
    function self:moveDef(id)
      local def = baseMoveDef(self, id)
      if not def or (def.description and def.description ~= "") then return def end
      if moveDescriptionCache[id] == nil then
        local desc = false
        if dexMod and dexMod.exports and type(dexMod.exports.moveById) == "function" then
          local ok, record = pcall(dexMod.exports.moveById, id)
          if ok then
            desc = twoLineDescription(cleanMoveDescription(record), 18) or false
          end
        end
        moveDescriptionCache[id] = desc
      end
      local desc = moveDescriptionCache[id]
      if not desc then return def end
      local copy = {}
      for k, v in pairs(def) do copy[k] = v end
      copy.description = desc
      return copy
    end

    local function hasFourthPage()
      -- Dungeon Delvers only adds page 4 for Ancient Pokemon. Ordinary
      -- Pokemon must retain Crystal's stock three-page summary layout.
      return isAncient(self.mon)
    end

    function self:turnPage(delta)
      local maxPage = hasFourthPage() and ABILITY_PAGE or 3
      local page = self.page + delta
      if page > maxPage then page = pinkPage end
      if page < pinkPage then page = maxPage end
      self.page = page
    end

    -- Ancient Pokemon use the Randomizer's four-tab spacing. Ordinary Pokemon
    -- use Crystal's exact stock positions: tabs 13/15/17, arrows 12/19.
    function self:drawPageIndicators()
      local columns = hasFourthPage() and { 10, 12, 14, 16 } or { 13, 15, 17 }
      for i, tx in ipairs(columns) do
        self:drawPageSquare(tx, 5, i == self.page, PAGE_PALETTES[i])
      end
    end

    local ancientIconLoaded = false
    local ancientIcon = nil
    local function getAncientIcon()
      if ancientIconLoaded then return ancientIcon end
      ancientIconLoaded = true
      local ok, icon = pcall(function()
        return mod.assets:image("assets/ancientsymbol.png")
      end)
      if ok and icon then
        if icon.setFilter then pcall(function() icon:setFilter("nearest", "nearest") end) end
        ancientIcon = icon
      end
      return ancientIcon
    end

    function self:drawUpperHalf()
      local mon = self.mon or {}
      if not isAncient(mon) then
        return downstreamDrawUpperHalf(self)
      end
      self:drawPic()
      self:drawPlacements(self:upperPlacements())
      self:drawHorizontalDivider()
      if hasFourthPage() then
        Chrome.print("◀", 9, 6)
        Chrome.print("▶", 18.5, 6)
      else
        -- Stock Gen-II SummaryMenu alignment.
        Chrome.print("◀", 12, 6)
        Chrome.print("▶", 19, 6)
      end
      if isAncient(mon) then
        -- Ancient specimens use Crystal's shiny-icon slot for the fossil-bone
        -- marker. Draw it here on the wrapped summary instance so the custom
        -- fourth-page renderer cannot bypass the icon hook.
        local icon = getAncientIcon()
        if icon then
          local G = love.graphics
          G.setColor(1, 1, 1, 1)
          G.rectangle("fill", 19 * 8, 0, 8, 8)
          G.draw(icon, 19 * 8, 0)
        end
      elseif mon.shiny then
        self:pageTile(0x3f, 19, 0)
      end
      self:drawPageIndicators()
    end

    local function drawAbilityPage()
      local G = love.graphics
      local tint = GbcPalette.color(ORANGE_LOWER, 1) or ORANGE_TINT
      G.setColor(tint[1] / 255, tint[2] / 255, tint[3] / 255, 1)
      G.rectangle("fill", 0, 8 * 8, Chrome.SCREEN_W * 8, 10 * 8)
      G.setColor(0, 0, 0, 1)

      local name, desc = abilityInfo(mod, dexMod, self.mon)
      local nameLines = wrapLines(TextBox, name, 18)
      local descLines = wrapLines(TextBox, desc, 18)

      Chrome.printThrough("ABILITY/", 0, 8, ORANGE_LOWER)
      Chrome.printThrough(nameLines[1] or name, 1, 9, ORANGE_LOWER)
      if nameLines[2] then Chrome.printThrough(nameLines[2], 1, 10, ORANGE_LOWER) end

      Chrome.printThrough("EFFECT/", 0, 11, ORANGE_LOWER)
      for i = 1, math.min(#descLines, 6) do
        Chrome.printThrough(descLines[i], 1, 11 + i, ORANGE_LOWER)
      end
    end

    local baseDrawPanel = self.drawPanel
    function self:drawPanel()
      if self.page == ABILITY_PAGE and hasFourthPage() and not self.moveDetail and not isEgg(self.mon) then
        local wasBattle = Font.useBattleExtra(true)
        Chrome.clear()
        drawAbilityPage()
        self:drawUpperHalf()
        Font.useBattleExtra(wasBattle)
        love.graphics.setColor(1, 1, 1, 1)
        return
      end
      return baseDrawPanel(self)
    end

    -- Stock Crystal input flow, extended so page 4 is the final page.
    function self:update(_dt)
      self:stepPicAnim()
      local input = self.game and self.game.input
      if not input then return end
      if self:tickRepeatSfx() then return end

      if self.moveDetail then
        self:updateMoveDetail(input)
        return
      end

      if isEgg(self.mon) then
        if input:wasPressed("a") or input:wasPressed("b") then
          self:close()
        elseif input:wasPressed("up") then
          self:switchMon(-1)
        elseif input:wasPressed("down") then
          self:switchMon(1)
        end
        return
      end

      if input:wasPressed("b") then
        self:close()
        return
      end
      if input:wasPressed("left") then
        self:turnPage(-1)
        return
      end
      if input:wasPressed("right") then
        self:turnPage(1)
        return
      end
      if input:wasPressed("a") then
        if self.page == ABILITY_PAGE then
          self:close()
        else
          self:turnPage(1)
        end
        return
      end
      if input:wasPressed("up") then
        self:switchMon(-1)
        if self.page == ABILITY_PAGE and not hasFourthPage() then self.page = 3 end
        return
      end
      if input:wasPressed("down") then
        self:switchMon(1)
        if self.page == ABILITY_PAGE and not hasFourthPage() then self.page = 3 end
        return
      end
      if input:wasPressed("select") and self.page == greenPage then
        self.moveDetail = true
        self.moveIndex = 1
      end
    end

    return self
  end

  mod.content.screens:register("Gen2SummaryMenu", {
    new = function(game, opts)
      return wrapSummary(game, opts)
    end,
  })

  return true
end

return M
