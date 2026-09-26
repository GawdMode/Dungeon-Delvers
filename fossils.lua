-- Dungeon Delvers fossil excavation / catalogue subsystem.
-- Kept separate from main.lua both for maintainability and to stay below
-- LuaJIT's strict 200-local-per-function compiler limit.

local Fossils={}
local C
local Theme=require("src.ui.Theme")

local MINING_SCREEN="PewterDungeonMining"
local CATALOGUE_SCREEN="PewterDungeonFossilCatalogue"
local CATALOGUE_DETAIL_SCREEN="PewterDungeonFossilCatalogueDetail"
local REVIVAL_FLASH_SCREEN="PewterDungeonRevivalFlash"
local EXHIBIT_SCREEN="PewterDungeonFossilExhibit"

local PARTS={"HEAD","UPPER","LOWER"}
local ORDER={
  "OMANYTE","KABUTO","AERODACTYL","RATTATA","SANDSHREW","ONIX","GEODUDE","CUBONE",
  "WOOPER","DUNSPARCE","GLIGAR","SHUCKLE","SLUGMA","SWINUB","CORSOLA","PHANPY",
}
local SPECIES={
  OMANYTE={label="OMANYTE",revive="OMANYTE",ancient=false,minDepth=1,weight=18},
  KABUTO={label="KABUTO",revive="KABUTO",ancient=false,minDepth=1,weight=18},
  AERODACTYL={label="AERODACTYL",revive="AERODACTYL",ancient=false,minDepth=7,weight=8},
  RATTATA={label="ANCIENT RATTATA",revive="RATTATA",ancient=true,minDepth=1,weight=14},
  SANDSHREW={label="ANCIENT SANDSHREW",revive="SANDSHREW",ancient=true,minDepth=3,weight=12},
  ONIX={label="ANCIENT ONIX",revive="ONIX",ancient=true,minDepth=2,weight=12},
  GEODUDE={label="ANCIENT GEODUDE",revive="GEODUDE",ancient=true,minDepth=1,weight=14},
  CUBONE={label="ANCIENT CUBONE",revive="CUBONE",ancient=true,minDepth=5,weight=10},
  WOOPER={label="ANCIENT WOOPER",revive="WOOPER",ancient=true,minDepth=4,weight=10},
  DUNSPARCE={label="ANCIENT DUNSPARCE",revive="DUNSPARCE",ancient=true,minDepth=6,weight=9},
  GLIGAR={label="ANCIENT GLIGAR",revive="GLIGAR",ancient=true,minDepth=8,weight=8},
  SHUCKLE={label="ANCIENT SHUCKLE",revive="SHUCKLE",ancient=true,minDepth=9,weight=7},
  SLUGMA={label="ANCIENT SLUGMA",revive="SLUGMA",ancient=true,minDepth=10,weight=7},
  SWINUB={label="ANCIENT SWINUB",revive="SWINUB",ancient=true,minDepth=11,weight=7},
  CORSOLA={label="ANCIENT CORSOLA",revive="CORSOLA",ancient=true,minDepth=12,weight=6},
  PHANPY={label="ANCIENT PHANPY",revive="PHANPY",ancient=true,minDepth=6,weight=10},
}

local EXHIBIT_ORDER={
  "OMANYTE","KABUTO","AERODACTYL","RATTATA","SANDSHREW","ONIX","GEODUDE","CUBONE",
  "WOOPER","DUNSPARCE","GLIGAR","SHUCKLE","SLUGMA","SWINUB","CORSOLA","PHANPY",
}
local EXHIBIT_ANCIENT={
  RATTATA=true,SANDSHREW=true,ONIX=true,GEODUDE=true,CUBONE=true,WOOPER=true,DUNSPARCE=true,
  GLIGAR=true,SHUCKLE=true,SLUGMA=true,SWINUB=true,CORSOLA=true,PHANPY=true,
}
local EXHIBIT_ART={
  OMANYTE="omanyte_fossil.png",KABUTO="kabuto_fossil.png",AERODACTYL="aerodactyl_fossil.png",
  RATTATA="rattata_fossil.png",SANDSHREW="sandshrew_fossil.png",ONIX="onix_fossil.png",
  GEODUDE="geodude_fossil.png",CUBONE="cubone_fossil.png",WOOPER="wooper_fossil.png",
  DUNSPARCE="dunsparce_fossil.png",GLIGAR="gligar_fossil.png",SHUCKLE="shuckle_fossil.png",
  SLUGMA="slugma_fossil.png",SWINUB="swinub_fossil.png",CORSOLA="corsola_fossil.png",
  PHANPY="phanpy_fossil.png",
}
local EXHIBIT_LORE={
  OMANYTE={
    "Its coiled shell helped it balance in ancient seas.",
    "Tentacles swept the seafloor for small prey.",
  },
  KABUTO={
    "A broad shell shielded it while it hugged the seafloor.",
    "It likely gathered in warm, shallow coastal waters.",
  },
  AERODACTYL={
    "Light bones and wide wings made it a powerful flier.",
    "It hunted above cliffs and ancient coastlines.",
  },
  RATTATA={
    "Heavy incisors suggest constant gnawing on roots and bark.",
    "It thrived wherever dense ground cover offered shelter.",
  },
  SANDSHREW={
    "Enlarged foreclaws were built for hard, mineral-rich soil.",
    "Its burrows may have stretched deep beneath dry flats.",
  },
  ONIX={
    "Segmented spinal rings suggest a tremendous burrower.",
    "It carved long shafts through old layers of stone.",
  },
  GEODUDE={
    "Dense mineral plates protected its compact stone body.",
    "It clung to steep cave walls and rocky ledges.",
  },
  CUBONE={
    "A reinforced skull protected it from falling stone.",
    "It crossed exposed badlands in search of sheltered dens.",
  },
  WOOPER={
    "Broad gill structures point to cool marshes and shallows.",
    "It moved between muddy pools as water levels changed.",
  },
  DUNSPARCE={
    "Its long ribs supported a body made for tunneling.",
    "It bored winding nests through loose ancient earth.",
  },
  GLIGAR={
    "Hooked claws gripped stone while broad membranes caught air.",
    "It glided between cavern shelves to ambush prey.",
  },
  SHUCKLE={
    "Its thick shell protected it inside narrow mineral cracks.",
    "It likely remained hidden for long stretches at a time.",
  },
  SLUGMA={
    "Heat-scarred deposits suggest life beside volcanic vents.",
    "Its body left mineral traces as it crossed hot stone.",
  },
  SWINUB={
    "A strengthened snout helped it root through frozen ground.",
    "It searched beneath snow and ash for buried food.",
  },
  CORSOLA={
    "Dense branches formed part of sprawling prehistoric reefs.",
    "Colonies created shelter for many smaller sea Pokemon.",
  },
  PHANPY={
    "Thick limb bones suggest long travel over dry riverbeds.",
    "Young herds may have followed seasonal water routes.",
  },
}
local exhibitImageCache={}
local function exhibitName(root)
  return tostring(root or "UNKNOWN")
end
local function exhibitTitle(root)
  if EXHIBIT_ANCIENT[root] then return "ANCIENT "..exhibitName(root) end
  return exhibitName(root)
end
local function exhibitImg(name)
  if not name then return nil end
  local cached=exhibitImageCache[name]
  if cached~=nil then return cached or nil end
  local ok,loaded=pcall(function() return C.mod.assets:image("assets/exhibits/"..name) end)
  if ok and loaded then
    if loaded.setFilter then pcall(function() loaded:setFilter("nearest","nearest") end) end
    exhibitImageCache[name]=loaded
    return loaded
  end
  exhibitImageCache[name]=false
  return nil
end

local function buildExhibitPages(rawLore)
  -- Fossil display dialogue must behave like vanilla Crystal dialogue: every
  -- explicit page is at most two short lines, with enough horizontal padding
  -- that the engine never wraps a line and triggers textbox auto-scroll.
  local pages={}
  local maxWidth=132
  for _,entry in ipairs(rawLore or {}) do
    local words={}
    local normalized=tostring(entry or ""):gsub("\n"," ")
    for word in normalized:gmatch("%S+") do words[#words+1]=word end
    if #words==0 then words={"Fossil","reconstruction","complete."} end

    local lines={}
    local current=""
    for _,word in ipairs(words) do
      local candidate=(current=="") and word or (current.." "..word)
      if current~="" and C.Font.width(candidate)>maxWidth then
        lines[#lines+1]=current
        current=word
      else
        current=candidate
      end
    end
    if current~="" then lines[#lines+1]=current end

    local i=1
    while i<=#lines do
      local first=lines[i] or ""
      local second=lines[i+1]
      pages[#pages+1]=second and (first.."\n"..second) or first
      i=i+2
    end
  end
  if #pages==0 then pages={"Fossil reconstruction\ncomplete."} end
  return pages
end

local SHAPES={
  HEAD={{0,0},{1,0},{-1,0},{0,1},{1,1},{-1,1}},
  UPPER={{-2,0},{-1,0},{0,0},{1,0},{2,0},{-1,1},{1,1}},
  LOWER={{-1,-1},{1,-1},{-1,0},{0,0},{1,0},{-2,1},{2,1}},
}

local function label(root)
  local d=SPECIES[root]
  return (d and d.label) or tostring(root or "UNKNOWN")
end

local function listLabel(root)
  local d=SPECIES[root]
  -- The list itself stays clean: discovery tells the player it is Ancient,
  -- while the detail screen carries the full ANCIENT label.
  if d and d.ancient then return tostring(d.revive or root) end
  return (d and d.label) or tostring(root or "UNKNOWN")
end

local function partLabel(part)
  if part=="UPPER" then return "UPPER BODY" end
  if part=="LOWER" then return "LOWER BODY" end
  return "HEAD"
end

local function quality(integrity)
  integrity=tonumber(integrity) or 0
  if integrity>=90 then return "PRISTINE" end
  if integrity>=65 then return "CLEAN" end
  return "DAMAGED"
end

local function researchValue(integrity)
  local q=quality(integrity)
  if q=="PRISTINE" then return 4 end
  if q=="CLEAN" then return 2 end
  return 1
end

-- DEV33 uses the user-supplied 8x8 mining tiles exactly: every cell begins
-- as a random DIGTILE, then advances SMALLCRACK -> BIGCRACK -> removed.
-- The permanent user background tile sits below buried objects and cover.
-- The board is widened to 14x9 with the cleaner bottom tool/control layout.
local ASSET_ROOT="assets/excavation/"
local imageCache={}
local function img(name)
  local v=imageCache[name]
  if v~=nil then return v or nil end
  local ok,loaded=pcall(function() return C.mod.assets:image(ASSET_ROOT..name) end)
  if ok and loaded then
    if loaded.setFilter then pcall(function() loaded:setFilter("nearest","nearest") end) end
    imageCache[name]=loaded
    return loaded
  end
  imageCache[name]=false
  return nil
end

local BOARD_W,BOARD_H,CELL=16,9,8
local BOARD_X,BOARD_Y=16,32
local DIG_VARIANTS=5

local FOSSIL_ART={
  HEAD={"fossil1.png","fossil2.png","fossil3.png","fossil4.png"},
  UPPER={"longfossil1.png","longfossil2.png","longfossil3.png"},
  LOWER={"tallfossil1.png","tallfossil2.png"},
}

-- The uploaded sprites stay at their native dimensions. Two supplied treasures
-- (NUGGET / STAR PIECE) are 16x16; the rest are 24x24. Nothing is resized.
local TREASURE_ART={
  {id="NUGGET",file="nugget.png",w=16,h=16,weight=13},
  {id="STAR_PIECE",file="starpiece.png",w=16,h=16,weight=7},
  {id="STARDUST",file="stardust.png",w=24,h=24,weight=13},
  {id="WATER_STONE",file="water_stone.png",w=24,h=24,weight=8},
  {id="SUN_STONE",file="sun_stone.png",w=24,h=24,weight=5},
  {id="MOON_STONE",file="moon_stone.png",w=24,h=24,weight=7},
  {id="KINGS_ROCK",file="kings_rock.png",w=24,h=24,weight=5},
  {id="FIRE_STONE",file="fire_stone.png",w=24,h=24,weight=8},
  {id="EVERSTONE",file="everstone.png",w=24,h=24,weight=8},
}

local function weightedTreasure(r)
  local total=0
  for _,v in ipairs(TREASURE_ART) do total=total+(v.weight or 1) end
  local roll=r(math.max(1,total))
  local at=0
  for _,v in ipairs(TREASURE_ART) do
    at=at+(v.weight or 1)
    if roll<=at then return v end
  end
  return TREASURE_ART[1]
end

local function drawMeter(G,x,y,ratio,pips)
  pips=pips or 4
  ratio=math.max(0,math.min(1,tonumber(ratio) or 0))
  local lit=math.floor(ratio*pips+.999)
  for i=0,pips-1 do
    G.setColor(.15,.12,.08,1); G.rectangle("fill",x+i*8,y,7,4)
    if i<lit then G.setColor(.53,.42,.22,1) else G.setColor(.84,.80,.68,1) end
    G.rectangle("fill",x+1+i*8,y+1,5,2)
  end
end

local function drawRiskMeter(G,x,y,ratio)
  local pips=14
  ratio=math.max(0,math.min(1,tonumber(ratio) or 0))
  local lit=math.floor(ratio*pips+.999)
  for i=0,pips-1 do
    local px=x+i*7
    G.setColor(.15,.12,.08,1); G.rectangle("fill",px,y,6,4)
    G.setColor(i<lit and .55 or .87,i<lit and .43 or .83,i<lit and .20 or .69,1)
    G.rectangle("fill",px+1,y+1,4,2)
  end
end

local function drawCursor(G,x,y)
  -- High-contrast square outline so the target stays visible over noisy dig art.
  G.setColor(.05,.04,.03,1)
  G.rectangle("line",x,y,CELL-1,CELL-1)
  G.setColor(1,1,1,1)
  G.rectangle("line",x+1,y+1,CELL-3,CELL-3)
end

local function objectCells(obj)
  local out={}
  for yy=obj.y,obj.y+obj.ch-1 do
    for xx=obj.x,obj.x+obj.cw-1 do out[#out+1]=(yy-1)*BOARD_W+xx end
  end
  return out
end

local function objectExposure(m,obj)
  local total,open=0,0
  for _,idx in ipairs(objectCells(obj)) do
    total=total+1
    if (m.cells[idx] or 0)<=0 then open=open+1 end
  end
  return total>0 and open/total or 0,open,total
end

local function objectAtCell(m,x,y,kind)
  for _,obj in ipairs(m.objects or {}) do
    if (not kind or obj.kind==kind)
        and x>=obj.x and x<obj.x+obj.cw and y>=obj.y and y<obj.y+obj.ch then
      return obj
    end
  end
  return nil
end

local function allRecovered(m)
  if not m or not m.objects then return false end
  for _,obj in ipairs(m.objects) do if not obj.recovered then return false end end
  return true
end

local function placeObject(m,obj,r,occupied)
  local maxX=BOARD_W-obj.cw+1
  local maxY=BOARD_H-obj.ch+1
  if maxX<1 or maxY<1 then return false end
  local function tryPlace(x,y)
    local clear=true
    for yy=y,y+obj.ch-1 do
      for xx=x,x+obj.cw-1 do
        if occupied[(yy-1)*BOARD_W+xx] then clear=false; break end
      end
      if not clear then break end
    end
    if not clear then return false end
    obj.x,obj.y=x,y
    for yy=y,y+obj.ch-1 do
      for xx=x,x+obj.cw-1 do occupied[(yy-1)*BOARD_W+xx]=true end
    end
    m.objects[#m.objects+1]=obj
    return true
  end

  -- Keep the random layout, but never let unlucky placement rolls silently
  -- reduce a deposit below its promised 2-4 finds. If 120 random tries miss
  -- the remaining opening, scan the board deterministically for a fit.
  for _=1,120 do
    if tryPlace(r(maxX),r(maxY)) then return true end
  end
  for y=1,maxY do
    for x=1,maxX do
      if tryPlace(x,y) then return true end
    end
  end
  return false
end

local function drawScreenBackground(G)
  -- DEV28 keeps DEV25's HUD geometry exactly as-is. Only the decorative layer
  -- behind it changes: the supplied square cave image is centered without
  -- distortion, with the requested #1b1615 mud-brown rails on either side.
  G.clear(27/255,22/255,21/255,1)
  local bg=img("cave_background.png")
  if bg then
    local iw,ih=bg:getDimensions()
    local scale=math.min(144/iw,144/ih)
    local dw,dh=iw*scale,ih*scale
    local dx=(160-dw)/2
    local dy=(144-dh)/2
    G.setColor(1,1,1,1)
    G.draw(bg,dx,dy,0,scale,scale)
  end
end

local function drawBoard(m,G)
  local bg=img("board_bg.png")
  local smallCount,bigCount=2,2
  -- permanent background, then buried objects, then mineable covering tiles
  for y=1,BOARD_H do
    for x=1,BOARD_W do
      local px=BOARD_X+(x-1)*CELL
      local py=BOARD_Y+(y-1)*CELL
      if bg then G.setColor(1,1,1,1); G.draw(bg,px,py)
      else G.setColor(.84,.80,.72,1); G.rectangle("fill",px,py,CELL,CELL) end
    end
  end

  for _,obj in ipairs(m.objects or {}) do
    local art=img(obj.file)
    if art then
      G.setColor(1,1,1,1)
      G.draw(art,BOARD_X+(obj.x-1)*CELL,BOARD_Y+(obj.y-1)*CELL)
    end
  end

  for y=1,BOARD_H do
    for x=1,BOARD_W do
      local idx=(y-1)*BOARD_W+x
      local stage=m.cells[idx] or 0
      if stage>0 then
        local seed=(m.variants and m.variants[idx]) or 1
        local art
        if stage>=3 then
          art=img("digtile"..tostring(((seed-1)%DIG_VARIANTS)+1)..".png")
        elseif stage==2 then
          art=img("smallcrack"..tostring(((seed-1)%smallCount)+1)..".png")
        else
          art=img("bigcrack"..tostring(((seed-1)%bigCount)+1)..".png")
        end
        local px=BOARD_X+(x-1)*CELL
        local py=BOARD_Y+(y-1)*CELL
        if art then G.setColor(1,1,1,1); G.draw(art,px,py)
        else
          G.setColor(stage>=3 and .58 or stage==2 and .48 or .37,.51,.39,1)
          G.rectangle("fill",px,py,CELL,CELL)
        end
      end
    end
  end
end

local function ensureCatalogue(s)
  s.fossilCatalogue=s.fossilCatalogue or {}

  -- DEV20 migration: an entry in ancientRegistry meant that the single fossil
  -- had already been restored, so preserve that accomplishment as a complete,
  -- revived catalogue entry rather than making old test saves start over.
  if type(s.ancientRegistry)=="table" then
    if s.ancientRegistry.ZUBAT and not s.ancientRegistry.ONIX then
      s.ancientRegistry.ONIX=s.ancientRegistry.ZUBAT
    end
    s.ancientRegistry.ZUBAT=nil
    for root,done in pairs(s.ancientRegistry) do
      if done and SPECIES[root] then
        local e=s.fossilCatalogue[root] or {parts={}}
        e.discovered=true
        e.revived=true
        e.parts=e.parts or {}
        for _,part in ipairs(PARTS) do
          e.parts[part]=e.parts[part] or {owned=true,count=1,bestIntegrity=75}
        end
        s.fossilCatalogue[root]=e
      end
    end
    s.ancientRegistry=nil
  end
  local legacyZubat=s.fossilCatalogue.ZUBAT
  if legacyZubat then
    local target=s.fossilCatalogue.ONIX or {discovered=false,parts={},revived=false}
    target.discovered=target.discovered or legacyZubat.discovered
    target.revived=target.revived or legacyZubat.revived
    target.parts=target.parts or {}
    for _,part in ipairs(PARTS) do
      local src=legacyZubat.parts and legacyZubat.parts[part]
      if src then
        local dst=target.parts[part] or {owned=false,count=0,bestIntegrity=0}
        dst.owned=dst.owned or src.owned
        dst.count=math.max(tonumber(dst.count) or 0,tonumber(src.count) or 0)
        dst.bestIntegrity=math.max(tonumber(dst.bestIntegrity) or 0,tonumber(src.bestIntegrity) or 0)
        target.parts[part]=dst
      end
    end
    s.fossilCatalogue.ONIX=target
    s.fossilCatalogue.ZUBAT=nil
  end
  return s.fossilCatalogue
end

local function entryFor(s,root)
  local cat=ensureCatalogue(s)
  cat[root]=cat[root] or {discovered=false,parts={},revived=false}
  cat[root].parts=cat[root].parts or {}
  return cat[root]
end

local function complete(entry)
  if not entry then return false end
  for _,part in ipairs(PARTS) do
    if not (entry.parts and entry.parts[part] and entry.parts[part].owned) then
      return false
    end
  end
  return true
end

local function discoveredRoots(s)
  local cat=ensureCatalogue(s)
  local out={}
  for _,root in ipairs(ORDER) do
    if cat[root] and cat[root].discovered then out[#out+1]=root end
  end
  return out
end

local function normalizeLegacyPending(s)
  if s.pendingFossil then
    s.pendingFossils=s.pendingFossils or {}
    local legacyRoot=s.pendingFossil=="ZUBAT" and "ONIX" or s.pendingFossil
    s.pendingFossils[#s.pendingFossils+1]={
      root=legacyRoot,part="HEAD",integrity=75,depth=1,
    }
    s.pendingFossil=nil
  end
  if s.pendingFossils then
    for _,specimen in ipairs(s.pendingFossils) do
      if specimen.root=="ZUBAT" then specimen.root="ONIX" end
    end
  end
end

function Fossils.rollDeposit(r,depth)
  depth=tonumber(depth) or 1

  -- Fossil species are tied to the dungeon's archaeological strata.  A player
  -- can complete the displays available to an expedition, but cannot grind
  -- B1-B20 forever and finish the entire museum without reaching deeper layers.
  local pool
  if depth<=20 then
    pool={
      {root="RATTATA",weight=16},
      {root="GEODUDE",weight=16},
      {root="SANDSHREW",weight=14},
      {root="ONIX",weight=10+(depth>=11 and 5 or 0)},
      {root="CUBONE",weight=8+(depth>=11 and 5 or 0)},
    }
  elseif depth<=40 then
    pool={
      {root="WOOPER",weight=15},
      {root="DUNSPARCE",weight=13},
      {root="PHANPY",weight=12},
      {root="GLIGAR",weight=10+(depth>=31 and 4 or 0)},
      {root="SHUCKLE",weight=8+(depth>=31 and 5 or 0)},
    }
  else
    pool={
      {root="SLUGMA",weight=14},
      {root="SWINUB",weight=13},
      {root="CORSOLA",weight=10},
      {root="OMANYTE",weight=8+(depth>=51 and 3 or 0)},
      {root="KABUTO",weight=8+(depth>=51 and 3 or 0)},
      {root="AERODACTYL",weight=3+(depth>=51 and 3 or 0)},
    }
  end

  local total=0
  for _,row in ipairs(pool) do total=total+(row.weight or 1) end
  local roll=r(math.max(1,total))
  local root=pool[1].root
  local at=0
  for _,row in ipairs(pool) do
    at=at+(row.weight or 1)
    if roll<=at then root=row.root; break end
  end
  return root,PARTS[r(#PARTS)]
end

function Fossils.clearRunLoot(s)
  if not s then return end
  s.carriedFossil=nil
  s.carriedFossils={}
  s.carriedTreasures={}
end

function Fossils.addRunFossil(game,root,part,depth,integrity)
  local ds=C.pdSave(game)
  part=(part=="UPPER" or part=="LOWER") and part or "HEAD"
  ds.carriedFossils=ds.carriedFossils or {}
  ds.carriedFossils[#ds.carriedFossils+1]={root=SPECIES[root] and root or "OMANYTE",part=part,
    integrity=C.clamp(integrity or 95,1,100),depth=depth or ds.floor or 1}
  -- Fossil fragments are case records, not PACK items. The old token item
  -- definitions remain registered only so legacy saves can be cleaned safely.
end

function Fossils.showFieldCase(game)
  local ds=C.pdSave(game); local counts={HEAD=0,UPPER=0,LOWER=0}
  for _,f in ipairs(ds.carriedFossils or {}) do
    counts[f.part or "HEAD"]=(counts[f.part or "HEAD"] or 0)+1
  end
  local pages={
    "FOSSILS FOUND:\nHEAD x"..tostring(counts.HEAD),
    "U BODY x"..tostring(counts.UPPER).."\nL BODY x"..tostring(counts.LOWER),
  }
  local finds={}
  for id,qty in pairs(ds.carriedTreasures or {}) do
    qty=tonumber(qty) or 0
    if qty>0 then
      local def=game.data.items and game.data.items[id]
      finds[#finds+1]={name=(def and def.name or tostring(id)),qty=qty}
    end
  end
  table.sort(finds,function(a,b) return a.name<b.name end)
  if #finds==0 then
    pages[#pages+1]="ITEMS:\nNONE"
  else
    pages[#pages+1]="ITEMS:"
    for _,row in ipairs(finds) do
      pages[#pages+1]=row.name.." x"..tostring(row.qty)
    end
  end
  C.showPages(game.world,pages)
end

function Fossils.extractRunLoot(s,extracted)
  if not s then return end
  if extracted then
    s.pendingFossils=s.pendingFossils or {}
    for _,specimen in ipairs(s.carriedFossils or {}) do
      s.pendingFossils[#s.pendingFossils+1]=C and C.deep and C.deep(specimen) or specimen
    end
    -- DEV20 compatibility for an expedition saved with its old one-slot case.
    if s.carriedFossil then
      s.pendingFossils[#s.pendingFossils+1]={
        root=s.carriedFossil,part="HEAD",integrity=75,depth=s.floor or 1,
      }
    end
    s.securedTreasures=s.securedTreasures or {}
    for id,qty in pairs(s.carriedTreasures or {}) do
      s.securedTreasures[id]=(s.securedTreasures[id] or 0)+(tonumber(qty) or 0)
    end
  end
end

-- Called only after the player's normal bag has been restored from escrow.
-- A full pocket never destroys a recovered find: anything that cannot fit
-- remains secured in museum storage and is retried next time this is called.
function Fossils.settleSecuredLoot(game)
  local s=C.pdSave(game)
  local pending=s.securedTreasures or {}
  local left={}
  local added=0
  for id,qty in pairs(pending) do
    local remaining=tonumber(qty) or 0
    while remaining>0 do
      if C.Bag and C.Bag.add(game.save,id,1,game.data) then
        remaining=remaining-1; added=added+1
      else break end
    end
    if remaining>0 then left[id]=remaining end
  end
  s.securedTreasures=left
  return added,next(left)~=nil
end

local function miningStateFor(e)
  if e.mining and e.mining.version==42 then return e.mining end
  local fs=C.getFloorState()
  local depth=(fs and fs.depth) or 1
  local r=C.rng(C.floorSeed(C.pdSave(C.mod.game),depth)+(e.index or 1)*3571)
  local part=e.fossilPart or PARTS[r(#PARTS)]
  e.fossilPart=part

  local m={
    version=42,cursorX=8,cursorY=5,tool="CHISEL",
    stress=0,maxStress=97,cells={},variants={},objects={},
    integrity=100,part=part,toast=nil,toastTimer=0,
  }
  for i=1,BOARD_W*BOARD_H do
    m.cells[i]=3
    m.variants[i]=r(DIG_VARIANTS)
  end

  local occupied={}
  local artList=FOSSIL_ART[part] or FOSSIL_ART.HEAD
  local fossilFile=artList[r(#artList)]
  local fw,fh=24,24
  if part=="UPPER" then fw,fh=48,24 elseif part=="LOWER" then fw,fh=24,48 end
  local fossil={
    kind="fossil",file=fossilFile,w=fw,h=fh,cw=math.ceil(fw/CELL),ch=math.ceil(fh/CELL),
    root=e.fossilRoot or "OMANYTE",part=part,recovered=false,
  }
  placeObject(m,fossil,r,occupied)
  m.mainObject=fossil

  -- Every mineable fossil wall now contains 2-4 total recoverable objects:
  -- the fossil plus 1-3 bonus treasures.
  local bonusRoll=r(100)
  local bonusCount=(bonusRoll<=20 and 3) or (bonusRoll<=65 and 2) or 1
  for _=1,bonusCount do
    local def=weightedTreasure(r)
    local obj={kind="item",file=def.file,id=def.id,w=def.w,h=def.h,
      cw=math.ceil(def.w/CELL),ch=math.ceil(def.h/CELL),recovered=false}
    placeObject(m,obj,r,occupied)
  end

  e.mining=m
  return m
end

local function registerMiningScreen()
  C.mod.content.screens:register(MINING_SCREEN,{
    new=function(game,opts)
      opts=opts or {}
      local e=opts.entity
      local m=e and miningStateFor(e) or nil
      local state={game=game,isOpaque=true}

      local function fossilExposure()
        if not (m and m.mainObject) then return 0 end
        return objectExposure(m,m.mainObject)
      end

      local function toast(text,time)
        m.toast=text; m.toastTimer=time or 1.25
      end

      local function storeObject(obj)
        if obj.recovered then return end
        obj.recovered=true
        if obj.kind=="fossil" then
          m.mainRecovered=true
          if not e.devPreview then
            local ds=C.pdSave(game)
            local root=obj.root or e.fossilRoot or "OMANYTE"
            local part=obj.part or e.fossilPart or "HEAD"
            local depth=(C.getFloorState() and C.getFloorState().depth) or ds.floor or 1
            local integrity=m.integrity or 100
            Fossils.addRunFossil(game,root,part,depth,integrity)
            if C.shareExcavationFind then
              C.shareExcavationFind(game,e,{kind="fossil",root=root,part=part,depth=depth,integrity=integrity})
            end
          end
          -- The dig impact SFX can outrank/drop the reward fanfare if it is
          -- still active. Clear it first, then hold the fossil banner long
          -- enough for the item-get cue to read cleanly.
          C.Sound.waitSfxDone()
          -- Route through Crystal's native `specialsound` implementation when
          -- possible. It performs the same WaitSFX + SFX_ITEM path used by
          -- verbosegiveitem, including the numeric fallback in older caches.
          if game.world and game.world.specialSound then
            game.world:specialSound(nil)
          elseif game.world and game.world.playSfxNamed then
            game.world:playSfxNamed("Sfx_Item")
          else
            C.Sound.play(game.data,"Sfx_Item")
          end
          local linger=math.max(2.8,(C.Sound.sfxRemaining() or 0)+0.45)
          toast("FOSSIL GET!",linger)
          m.toastLock=true
        else
          if not e.devPreview then
            local s=C.pdSave(game)
            s.carriedTreasures=s.carriedTreasures or {}
            s.carriedTreasures[obj.id]=(s.carriedTreasures[obj.id] or 0)+1
            if C.Bag then C.Bag.add(game.save,obj.id,1,game.data) end
            if C.shareExcavationFind then
              C.shareExcavationFind(game,e,{kind="item",id=obj.id,qty=1})
            end
          end
          C.Sound.play(game.data,"Sfx_Item")
          toast("ITEM GET!",1.4)
        end
      end

      local function checkRecovered()
        for _,obj in ipairs(m.objects or {}) do
          if not obj.recovered then
            local ratio=objectExposure(m,obj)
            if ratio>=1 then storeObject(obj) end
          end
        end
        if allRecovered(m) then m.completeTimer=m.completeTimer or 1.15 end
      end

      local function finishSession(collapsed)
        game.stack:pop()
        if not e then return end
        if e.devPreview then
          e.mining=nil
          if game.world and game.world.showText then
            game.world:showText(collapsed and "DEV wall collapsed." or "DEV excavation\npreview complete.")
          end
          return
        end
        local recoveredCount=0
        for _,obj in ipairs(m.objects or {}) do
          if obj.recovered then recoveredCount=recoveredCount+1 end
        end
        if recoveredCount>0 and not m.coopDoneNotified and C.shareExcavationDone then
          m.coopDoneNotified=true
          C.shareExcavationDone(game,e,{count=recoveredCount,collapsed=collapsed and true or false})
        end

        if collapsed then
          e.miningCollapsed=true
          C.Sound.play(game.data,"Sfx_Strength")
          C.removeEntity(game,e)
          C.showPages(game.world,{
            "The fossil rock crumbled away!",
            m.mainRecovered and "Recovered finds are safe in your DELVE CASE." or "The fossil was lost.",
          })
        elseif m.mainRecovered then
          C.removeEntity(game,e)
          C.showPages(game.world,{
            "Excavation complete!",
            "Your recovered finds are stored in the DELVE CASE.",
            "Check out safely at a REST STOP to bring them home.",
          })
        end
      end

      local function applyHit(x,y,power,exposedDamage,breakDamage)
        if x<1 or x>BOARD_W or y<1 or y>BOARD_H then return end
        local idx=(y-1)*BOARD_W+x
        local before=m.cells[idx] or 0
        local fossil=objectAtCell(m,x,y,"fossil")
        if before<=0 then
          if fossil and not fossil.recovered then
            m.integrity=math.max(0,(m.integrity or 100)-(exposedDamage or 0))
          end
          return
        end
        local after=math.max(0,before-(power or 1))
        m.cells[idx]=after
        if fossil and before>0 and after<=0 and (breakDamage or 0)>0 then
          m.integrity=math.max(0,(m.integrity or 100)-(breakDamage or 0))
        end
      end

      function state:update(dt)
        if not m then game.stack:pop(); return end
        dt=tonumber(dt) or 0
        if (m.toastTimer or 0)>0 then
          m.toastTimer=math.max(0,m.toastTimer-dt)
          if m.toastTimer<=0 then
            m.toast=nil
            m.toastLock=nil
          elseif m.toastLock then
            return
          end
        end
        if m.completeTimer then
          m.completeTimer=m.completeTimer-dt
          if m.completeTimer<=0 then finishSession(false); return end
        end

        local input=game.input
        if not input then return end
        if input:wasPressed("b") then
          game.stack:push(C.TextBox.new(game,"Abandon dig?",nil,{
            defaultNo=true,
            choice=function(yes)
              if yes then
                -- Preserve the partially-dug wall when abandoning before
                -- recovery so the same deposit can be revisited later.
                if m.mainRecovered then finishSession(false) else game.stack:pop() end
              end
            end,
          }))
          return
        end

        if input:wasPressed("left") then m.cursorX=math.max(1,m.cursorX-1)
        elseif input:wasPressed("right") then m.cursorX=math.min(BOARD_W,m.cursorX+1)
        elseif input:wasPressed("up") then m.cursorY=math.max(1,m.cursorY-1)
        elseif input:wasPressed("down") then m.cursorY=math.min(BOARD_H,m.cursorY+1)
        elseif input:wasPressed("select") then
          m.tool=(m.tool=="CHISEL") and "HAMMER" or "CHISEL"
        elseif input:wasPressed("a") and not m.completeTimer then
          if m.tool=="CHISEL" then
            applyHit(m.cursorX,m.cursorY,1,0,0)
            m.stress=m.stress+1
            C.Sound.play(game.data,"Sfx_Pound")
          else
            -- Hammer is faster because it advances a cross of cells at once,
            -- but every affected cell still visibly passes through all three
            -- cover stages: DIG -> SMALL CRACK -> BIG CRACK -> REMOVED.
            applyHit(m.cursorX,m.cursorY,1,18,5)
            applyHit(m.cursorX-1,m.cursorY,1,5,2)
            applyHit(m.cursorX+1,m.cursorY,1,5,2)
            applyHit(m.cursorX,m.cursorY-1,1,5,2)
            applyHit(m.cursorX,m.cursorY+1,1,5,2)
            m.stress=m.stress+3
            C.Sound.play(game.data,"Sfx_Strength")
          end

          local fs=C.getFloorState()
          if fs then
            fs.stability=math.max(0,fs.stability-2)
            C.pdSave(game).stability=fs.stability
          end
          checkRecovered()
          if m.integrity<=0 then
            if m.mainObject then m.mainObject.recovered=false end
            finishSession(true); return
          end
          if m.stress>=m.maxStress then finishSession(true); return end
        end
      end

      function state:draw()
        local G=love.graphics
        drawScreenBackground(G)

        -- Taller 16x9 mining field with cleaner bottom spacing.
        C.Chrome.box(0,0,20,3)
        C.Chrome.box(1,3,18,11)
        C.Chrome.box(1,14,4,4)
        C.Chrome.box(5,14,4,4)
        C.Chrome.box(9,14,11,4)

        G.setColor(0,0,0,1)
        C.Font.draw("RISK",8,8)
        drawRiskMeter(G,50,10,(m.stress or 0)/(m.maxStress or 1))

        drawBoard(m,G)
        drawCursor(G,BOARD_X+(m.cursorX-1)*CELL,BOARD_Y+(m.cursorY-1)*CELL)

        local function drawToolButton(boxX,boxY,selected,file,bgR,bgG,bgB)
          local px=boxX*8+4
          local py=boxY*8+4
          local w=24
          local h=24
          G.setColor(.08,.07,.05,1)
          G.rectangle("fill",px-1,py-1,w+2,h+2)
          G.setColor(bgR,bgG,bgB,1)
          G.rectangle("fill",px,py,w,h)
          if selected then
            G.setColor(1,1,1,1)
            G.rectangle("line",px-1,py-1,w+2,h+2)
          end
          local ic=img(file)
          if ic then
            local iw,ih=ic:getDimensions()
            local ix=px+math.floor((w-iw)/2)
            local iy=py+math.floor((h-ih)/2)
            G.setColor(1,1,1,1)
            G.draw(ic,ix,iy)
          end
        end

        -- Match the latest mockup: chisel on the left, hammer beside it.
        drawToolButton(1,14,m.tool=="CHISEL","chisel.png",0.72,0.16,0.16)
        drawToolButton(5,14,m.tool=="HAMMER","hammer.png",0.16,0.26,0.65)

        G.setColor(0,0,0,1)
        if m.toast and (m.toastTimer or 0)>0 then
          local t=m.toast; local w=76
          C.Font.draw(t,76+math.max(0,math.floor((w-C.Font.width(t))/2)),123)
        elseif m.completeTimer then
          local t="FINDS DONE!"; local w=76
          C.Font.draw(t,76+math.max(0,math.floor((w-C.Font.width(t))/2)),123)
        else
          local controlsLeft, controlsWidth = 80, 72
          local line1 = "A: DIG"
          local line2 = "SEL: TOOL"
          local x1 = controlsLeft + math.floor((controlsWidth - C.Font.width(line1)) / 2)
          local x2 = controlsLeft + math.floor((controlsWidth - C.Font.width(line2)) / 2)
          C.Font.draw(line1,x1,120)
          C.Font.draw(line2,x2,131)
        end
      end
      return state
    end,
  })
end

function Fossils.openMining(game,e)
  if e.miningCollapsed then
    return C.showPages(game.world,{"The fossil rock is already ruined."})
  end
  C.mod.ui.push(game,MINING_SCREEN,{entity=e})
end

local function registerRevivalFlashScreen()
  C.mod.content.screens:register(REVIVAL_FLASH_SCREEN,{
    new=function(game,opts)
      opts=opts or {}
      local state={game=game,isOpaque=false,t=0,secondPlayed=false,machinePlayed=false,fanfarePlayed=false}
      C.Sound.play(game.data,"Sfx_Spark")

      function state:update(dt)
        self.t=self.t+(dt or 0)
        if self.t>=0.22 and not self.secondPlayed then
          self.secondPlayed=true
          C.Sound.play(game.data,"Sfx_Spark")
        end
        if opts.ancient and self.t>=0.38 and not self.machinePlayed and not C.Sound.sfxBusy() then
          self.machinePlayed=true
          C.Sound.play(game.data,"Sfx_TwoPcBeeps")
        end
        local fanfareAt=opts.ancient and 0.58 or 0.50
        if self.t>=fanfareAt and (not opts.ancient or self.machinePlayed)
            and not self.fanfarePlayed and not C.Sound.sfxBusy() then
          self.fanfarePlayed=true
          C.Sound.play(game.data,"Sfx_Fanfare")
        end
        if self.fanfarePlayed and self.t>=0.54 then
          game.stack:pop()
          if opts.onDone then opts.onDone() end
        end
      end

      function state:draw()
        local t=self.t
        local white=(t<0.10) or (t>=0.22 and t<0.32)
        if white then
          love.graphics.setColor(1,1,1,1)
          love.graphics.rectangle("fill",0,0,160,144)
        end
      end
      return state
    end,
  })
end

local function registerExhibitScreen()
  C.mod.content.screens:register(EXHIBIT_SCREEN,{
    new=function(game,opts)
      opts=opts or {}
      local state={game=game,isOpaque=false,root=opts.root}

      -- This screen only draws the exhibit card. Lore uses Crystal's actual
      -- world:showText textbox above it, so spacing/arrow behavior is vanilla.
      function state:update(dt) end

      function state:draw()
        local G=love.graphics
        -- Do not clear the frame; keep the live museum/world visible.
        C.Chrome.box(0,0,20,3)
        C.Chrome.box(5,3,10,9)

        G.setColor(0,0,0,1)
        local title=exhibitTitle(self.root)
        C.Font.draw(title,math.max(8,math.floor((160-C.Font.width(title))/2)),8)

        local art=exhibitImg(EXHIBIT_ART[self.root])
        if art then
          local iw,ih=art:getDimensions()
          G.setColor(1,1,1,1)
          G.draw(art,math.floor((160-iw)/2),32)
        else
          G.setColor(0,0,0,1)
          C.Font.draw("DISPLAY ART",44,52)
          C.Font.draw("COMING SOON",40,68)
        end
      end
      return state
    end,
  })
end

local function registerCatalogueScreen()
  C.mod.content.screens:register(CATALOGUE_DETAIL_SCREEN,{
    new=function(game,opts)
      opts=opts or {}
      local state={game=game,isOpaque=true,root=opts.root}

      function state:update(dt)
        local input=game.input
        if not input then return end
        if input:wasPressed("b") or input:wasPressed("start") or input:wasPressed("a") then
          game.stack:pop(); return
        end
      end

      function state:draw()
        C.Chrome.clear()
        C.Chrome.box(0,0,20,3)
        C.Chrome.box(0,3,20,10)
        C.Chrome.box(0,13,20,5)
        love.graphics.setColor(0,0,0,1)

        local cat=ensureCatalogue(C.pdSave(game))
        local root=self.root
        local e=root and cat[root] or nil
        C.Font.draw(root and label(root) or "FOSSIL DETAILS",8,8)

        local function owned(part)
          return e and e.parts and e.parts[part] and e.parts[part].owned
        end
        C.Font.draw("HEAD",16,38)
        C.Font.draw(owned("HEAD") and "1/1" or "0/1",124,38)
        C.Font.draw("UPPER BODY",16,60)
        C.Font.draw(owned("UPPER") and "1/1" or "0/1",124,60)
        C.Font.draw("LOWER BODY",16,82)
        C.Font.draw(owned("LOWER") and "1/1" or "0/1",124,82)

        local n=0
        for _,part in ipairs(PARTS) do if owned(part) then n=n+1 end end
        C.Font.draw("COMPLETE "..tostring(n).."/3",16,112)
        if e and e.revived then
          C.Font.draw("REVIVED",16,128)
        elseif e and complete(e) then
          C.Font.draw("REVIVAL READY",16,128)
        else
          C.Font.draw("B: BACK",16,128)
        end
      end
      return state
    end,
  })

  C.mod.content.screens:register(CATALOGUE_SCREEN,{
    new=function(game)
      local state={game=game,isOpaque=true,cursor=1,top=1}
      ensureCatalogue(C.pdSave(game))
      local visible=6

      function state:update(dt)
        local input=game.input
        if not input then return end
        local roots=discoveredRoots(C.pdSave(game))
        if input:wasPressed("b") or input:wasPressed("start") then
          game.stack:pop(); return
        end
        if #roots==0 then return end
        self.cursor=math.max(1,math.min(self.cursor,#roots))
        if input:wasPressed("up") then self.cursor=math.max(1,self.cursor-1)
        elseif input:wasPressed("down") then self.cursor=math.min(#roots,self.cursor+1)
        elseif input:wasPressed("a") then
          C.mod.ui.push(game,CATALOGUE_DETAIL_SCREEN,{root=roots[self.cursor]})
          return
        end
        if self.cursor<self.top then self.top=self.cursor end
        if self.cursor>=self.top+visible then self.top=self.cursor-visible+1 end
      end

      function state:draw()
        C.Chrome.clear()
        C.Chrome.box(0,0,20,3)
        C.Chrome.box(0,3,20,10)
        C.Chrome.box(0,13,20,5)
        local G=love.graphics
        G.setColor(0,0,0,1)
        C.Font.draw("ANCIENT CATALOGUE",12,8)

        local s=C.pdSave(game)
        local cat=ensureCatalogue(s)
        local roots=discoveredRoots(s)
        if #roots==0 then
          C.Font.draw("NO SPECIMENS YET.",16,48)
          C.Font.draw("IDENTIFY FOSSILS.",16,64)
          C.Font.draw("B: BACK",16,116)
          return
        end

        self.cursor=math.max(1,math.min(self.cursor,#roots))
        self.top=math.max(1,math.min(self.top,math.max(1,#roots-visible+1)))
        local last=math.min(#roots,self.top+visible-1)
        for i=self.top,last do
          local root=roots[i]
          local e=cat[root]
          local y=32+(i-self.top)*12
          if i==self.cursor then
            -- Native-looking black pixel arrow; don't rely on a font glyph
            -- that some themes render as a square.
            G.setColor(0,0,0,1)
            G.polygon("fill",8,y+1,8,y+7,14,y+4)
          end
          C.Font.draw(listLabel(root),18,y)
          local n=0
          for _,part in ipairs(PARTS) do
            if e.parts and e.parts[part] and e.parts[part].owned then n=n+1 end
          end
          C.Font.draw(tostring(n).."/3",124,y)
        end

        -- Native-style black scroll arrows instead of text glyphs.
        G.setColor(0,0,0,1)
        if self.top>1 then G.polygon("fill",144,31,150,31,147,27) end
        if last<#roots then G.polygon("fill",144,94,150,94,147,98) end

        C.Font.draw("A: DETAILS",16,112)
        C.Font.draw("B: BACK",16,128)
      end
      return state
    end,
  })
end

local function identifyPending(game)
  local s=C.pdSave(game)
  local world=game.world
  normalizeLegacyPending(s)
  if #(s.pendingFossils or {})==0 then
    return C.showPages(world,{"No fossils await\nidentification."})
  end

  local function nextOne()
    local specimen=table.remove(s.pendingFossils,1)
    if not specimen then return end

    local root=SPECIES[specimen.root] and specimen.root or "OMANYTE"
    local part=(specimen.part=="UPPER" or specimen.part=="LOWER") and specimen.part or "HEAD"
    local entry=entryFor(s,root)
    local wasDiscovered=entry.discovered
    local wasComplete=complete(entry)
    local old=entry.parts[part]
    local duplicate=old and old.owned
    local oldBest=old and (tonumber(old.bestIntegrity) or 0) or 0
    local integrity=C.clamp(specimen.integrity or 75,1,100)

    entry.discovered=true
    entry.parts[part]=entry.parts[part] or {owned=true,count=0,bestIntegrity=0}
    local pe=entry.parts[part]
    pe.owned=true
    pe.count=(tonumber(pe.count) or 0)+1
    pe.bestIntegrity=math.max(tonumber(pe.bestIntegrity) or 0,integrity)

    local improved=duplicate and integrity>oldBest
    local nowComplete=complete(entry)
    local species=C.speciesName(game,SPECIES[root].revive or root)
    local reveal=SPECIES[root] and SPECIES[root].ancient
      and ("ANCIENT "..species.."\nidentified!")
      or (species.." fossil\nidentified!")
    local q=quality(integrity)
    local pages={reveal,partLabel(part).."\nregistered!","QUALITY: "..q}
    -- Every identified fossil now has research value, not only duplicates.
    -- Quality supplies the base RP; discovery/catalogue milestones stack on top.
    local rp=researchValue(integrity)
    if duplicate then
      pages[#pages+1]="Already in the\ncatalogue."
      if improved then
        pages[#pages+1]="Better specimen!\nExhibit upgraded."
        rp=rp+1
      end
    else
      pages[#pages+1]="New body part!\n+1 research bonus."
      rp=rp+1
    end
    if not wasDiscovered then
      pages[#pages+1]="New catalogue\nentry!"
      rp=rp+2
    end
    if nowComplete and not wasComplete and not entry.revived then
      pages[#pages+1]="All 3 pieces\ncatalogued!"
      pages[#pages+1]="REVIVAL is\nready!"
      rp=rp+5
    end
    if rp>0 then
      s.researchPoints=(tonumber(s.researchPoints) or 0)+rp
      pages[#pages+1]="RESEARCH +"..tostring(rp).." RP\nTOTAL "..tostring(s.researchPoints).." RP"
    end

    -- Keep every page two short lines so Crystal never auto-scrolls a third
    -- wrapped line into view. Identification uses the normal item-obtain SFX; the fanfare is reserved for revival.
    C.showPages(world,{"Cleaning the\nfossil..."},function()
      C.Sound.play(game.data,"Sfx_Item")
      C.showPages(world,pages,function()
        if #(s.pendingFossils or {})>0 then nextOne() end
      end)
    end)
  end
  nextOne()
end

local function openCatalogue(game)
  C.mod.ui.push(game,CATALOGUE_SCREEN,{})
end

local function revive(game,root)
  local s=C.pdSave(game)
  local world=game.world
  local d=SPECIES[root]
  local e=entryFor(s,root)
  if not (d and complete(e) and not e.revived) then
    return C.showPages(world,{"That revival is\nnot ready."})
  end

  local mon=C.buildMon(game,d.revive or root,5)
  if not mon then return C.showPages(world,{"The specimen could\nnot be restored."}) end
  if d.ancient then C.markAncient(game,mon,root) end

  local ok,dest=C.settleRestoredMon(game,mon)
  if not ok then return C.showPages(world,{dest}) end
  e.revived=true

  local where=(dest=="party") and "your party" or "the PC"
  local species=C.speciesName(game,mon.species)
  local pages
  if d.ancient then
    pages={"ANCIENT\n"..species,"Restoration\ncomplete!","Sent to "..where.."."}
  else
    pages={species.."\nrestored!","Sent to "..where.."."}
  end
  C.mod.ui.push(game,REVIVAL_FLASH_SCREEN,{ancient=d.ancient,onDone=function()
    local first=pages[1]
    local rest={}
    for i=2,#pages do rest[#rest+1]=pages[i] end
    game.stack:push(C.TextBox.new(game,first,function()
      if #rest>0 then C.showPages(world,rest) end
    end))
  end})
end

local function openRevivalMenu(game)
  local cat=ensureCatalogue(C.pdSave(game))
  local items={}
  for _,root in ipairs(ORDER) do
    local e=cat[root]
    if e and complete(e) and not e.revived then
      local selected=root
      items[#items+1]={label=label(selected),onSelect=function() revive(game,selected) end}
    end
  end
  if #items==0 then return C.showPages(game.world,{"No complete fossil\nset is ready."}) end
  game.stack:push(C.Menu.new(game,items,{tx=5,ty=2,tw=15,rowStep=2,cancelable=true,maxVisible=6}))
end

local RESEARCH_INTRO_PAGES={
  "Ah, good. I was hoping you'd come upstairs.",
  "I'm trying to bring these fossil displays back to life.",
  "The old Pewter Museum used to have a real sense of wonder to it.",
  "I'd like this room to feel that way again, but empty cases won't get us very far.",
  "If you find fossils below, bring them to me. I need a full set of bones before I can rebuild a display properly.",
  "And that's only half of what those bones can give us.",
  "There's still genetic material buried in them. Not much, but enough for the equipment I've put together here.",
  "Cinnabar once used machinery built around the same idea: recover the DNA, then rebuild the POKéMON from it.",
  "Help me complete a fossil set and restore its display, and I'll revive that POKéMON for you.",
  "Consider it my way of thanking you for helping this place feel like a museum again.",
  "One warning, though. What comes back isn't quite the same as the modern species you know.",
  "They look familiar, but these are ancient variants. They survived a harsher world than their descendants did.",
  "You'll notice they take elemental weaknesses better than a modern POKéMON would.",
  "Bring me a complete set when you find one. I'm very curious to see what wakes up.",
}

local EXPLANATION_PAGES={
  "MUSEUM PROJECT",
  "Bring fossil pieces back from the delve and have me IDENTIFY them.",
  "Every species needs three pieces: HEAD, UPPER BODY, and LOWER BODY.",
  "Complete all three and its museum display can be restored.",
  "A completed set also unlocks REVIVAL. The revived POKéMON is yours to keep.",
  "Ancient variants have ANCIENT RESILIENCE.",
  "A normal 2x weakness is treated as 1x. A 4x weakness is treated as 2x.",
  "Research Points come from deeper exploration and valuable fossil work.",
  "The front desk can exchange RP for useful supplies outside the delve.",
}

function Fossils.researchScientist(game)
  local s=C.pdSave(game)
  if not s.museumResearchIntroSeen then
    -- Mark it immediately so a reload/interruption cannot loop the one-time
    -- introduction forever. Every page is deliberately at most two short
    -- lines so Crystal never auto-scrolls or wraps the speech.
    s.museumResearchIntroSeen=true
    return C.showPages(game.world,RESEARCH_INTRO_PAGES,function()
      Fossils.researchDesk(game)
    end)
  end
  return Fossils.researchDesk(game)
end

function Fossils.researchDesk(game)
  Fossils.settleSecuredLoot(game)
  local s=C.pdSave(game)
  normalizeLegacyPending(s)
  local pending=#(s.pendingFossils or {})
  local items={}
  if pending>0 then
    items[#items+1]={label="IDENTIFY ("..tostring(pending)..")",onSelect=function() identifyPending(game) end}
  end
  items[#items+1]={label="CATALOGUE",onSelect=function() openCatalogue(game) end}
  items[#items+1]={label="REVIVAL",onSelect=function() openRevivalMenu(game) end}
  items[#items+1]={label="EXPLANATION",onSelect=function()
    C.showPages(game.world,EXPLANATION_PAGES)
  end}
  items[#items+1]={label="RESEARCH "..tostring(tonumber(s.researchPoints) or 0).." RP",onSelect=function()
    C.showPages(game.world,{"Deeper floors and valuable fossil work earn RP.","Spend Research Points at the front desk."})
  end}
  game.stack:push(C.Menu.new(game,items,{tx=5,ty=2,tw=15,rowStep=2,cancelable=true,maxVisible=6}))
end

function Fossils.tryExhibitInteraction(game,x,y)
  x=tonumber(x); y=tonumber(y)
  if x==nil or y==nil then return false end
  local slot
  if y==1 and x>=0 and x<=15 then
    slot=math.floor(x/2)+1
  -- The lower display protrudes into the row in front of the middle cases.
  -- Its left/right front-side cells are CORSOLA/PHANPY respectively; handle
  -- these before the middle-row ranges so both screenshot positions respond.
  elseif y==4 and x==5 then
    slot=15
  elseif y==4 and x==10 then
    slot=16
  elseif (y==3 or y==4) then
    if x>=1 and x<=4 then slot=9+math.floor((x-1)/2)
    elseif x>=6 and x<=9 then slot=11+math.floor((x-6)/2)
    elseif x>=11 and x<=14 then slot=13+math.floor((x-11)/2) end
  elseif (y==5 or y==6 or y==7) then
    -- Bottom case occupies the very bottom edge of the room, so its lowest
    -- side-facing cells are y=7.  Earlier builds stopped at y=6, which left
    -- exactly the Corsola/Phanpy side interactions shown in the screenshots
    -- dead.  Cover the complete visible case footprint here.
    if x>=5 and x<=7 then slot=15
    elseif x>=8 and x<=10 then slot=16 end
  end
  local root=slot and EXHIBIT_ORDER[slot] or nil
  if not root then return false end
  local cat=ensureCatalogue(C.pdSave(game))
  local e=cat[root]
  if not complete(e) then
    local pages={exhibitName(root).."\nSet not complete."}
    local missing={}
    local parts=(e and e.parts) or {}
    if not (parts.HEAD and parts.HEAD.owned) then missing[#missing+1]="NEED HEAD FOSSIL" end
    if not (parts.UPPER and parts.UPPER.owned) then missing[#missing+1]="NEED UPPER BODY" end
    if not (parts.LOWER and parts.LOWER.owned) then missing[#missing+1]="NEED LOWER BODY" end
    local i=1
    while i<=#missing do
      local first=missing[i]
      local second=missing[i+1]
      pages[#pages+1]=second and (first.."\n"..second) or first
      i=i+2
    end
    C.showPages(game.world,pages)
    return true
  end
  C.mod.ui.push(game,EXHIBIT_SCREEN,{root=root})
  local pages=buildExhibitPages(EXHIBIT_LORE[root] or {"Fossil reconstruction complete."})
  C.showPages(game.world,pages,function()
    -- Remove the static exhibit overlay after the final vanilla textbox page.
    game.stack:pop()
  end)
  return true
end

function Fossils.exhibitOrder()
  return EXHIBIT_ORDER
end

function Fossils.researchPoints(s)
  return tonumber((s or {}).researchPoints) or 0
end

function Fossils.catalogueSize()
  return #ORDER
end

function Fossils.catalogueCount(s)
  local n=0
  local cat=ensureCatalogue(s or {})
  for _,root in ipairs(ORDER) do
    if cat[root] and cat[root].discovered then n=n+1 end
  end
  return n
end

function Fossils.completeSetCount(s)
  local n=0
  local cat=ensureCatalogue(s or {})
  for _,root in ipairs(ORDER) do
    if complete(cat[root]) then n=n+1 end
  end
  return n
end

function Fossils.revivedCount(s)
  local n=0
  local cat=ensureCatalogue(s or {})
  for _,root in ipairs(ORDER) do
    if cat[root] and cat[root].revived then n=n+1 end
  end
  return n
end

function Fossils.init(ctx)
  C=ctx
  registerMiningScreen()
  registerRevivalFlashScreen()
  registerExhibitScreen()
  registerCatalogueScreen()
  ensureCatalogue(C.pdSave(C.mod.game))
end

return Fossils
