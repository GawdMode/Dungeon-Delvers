-- Dungeon Delvers 1.0 for Pokemon Crystal / gen1recomp 0.3.8+.

return function(mod)
  local Map=require("src.world.gen2.Map")
  local World=require("src.world.gen2.World")
  local Trainers=require("src.world.gen2.Trainers")
  local Movement=require("src.script.gen2.Movement")
  local Mon=require("src.battle.gen2.Mon")
  local Bag=require("src.inventory.Bag")
  local Boxes=require("src.core.gen2.Boxes")
  local Menu=require("src.ui.Menu")
  local Font=require("src.render.Font")
  local Sound=require("src.core.Sound")
  local Palettes=require("src.world.gen2.Palettes")
  local SpriteRenderer=require("src.render.SpriteRenderer")
  local Permissions=require("src.world.gen2.Permissions")
  local Assets=require("src.render.Assets")
  local Chrome=require("src.ui.gen2.Chrome")
  local GbcPalette=require("src.render.GbcPalette")
  local Sprites=require("src.pokemon.Sprites")
  local Battle=require("src.battle.gen2.Battle")
  mod._ddRollTypes=assert(load(assert(mod:read("type_variants.lua")),"@pewter_dungeon/type_variants.lua"))().install(mod,Mon,Battle)
  local Pipelines=require("src.render.Pipelines")
  local TextBox=require("src.render.TextBox")
  local Fossils=assert(load(assert(mod:read("fossils.lua")),"@pewter_dungeon/fossils.lua"))()
  local Museum2F=assert(load(assert(mod:read("museum2f_tiles.lua")),"@pewter_dungeon/museum2f_tiles.lua"))()

  -- Reuse Crystal National Dex Randomizer's orange fourth-summary
  -- page presentation for Ancient Pokemon. Kept in its own module so this does
  -- not add pressure to main.lua's LuaJIT local-variable limit.
  do
    local source=mod:read("ancient_summary.lua")
    if source then
      local chunk,err=load(source,"@pewter_dungeon/ancient_summary.lua")
      if chunk then
        local ok,module=pcall(chunk)
        if ok and type(module)=="table" and type(module.install)=="function" then
          local installed,why=module.install(mod)
          if installed~=true and mod.log then
            mod.log:warn("Ancient summary page skipped: %s",tostring(why))
          end
        elseif mod.log then
          mod.log:warn("Ancient summary module failed: %s",tostring(module))
        end
      elseif mod.log then
        mod.log:warn("Ancient summary module load failed: %s",tostring(err))
      end
    end
  end

  local PEWTER="PEWTER_CITY"
  local LOBBY="PEWTER_DUNGEON_MUSEUM"
  local UPSTAIRS="PEWTER_DUNGEON_MUSEUM_2F"
  local MUSEUM_2F_TILESET="PEWTER_DUNGEON_MUSEUM_2F_TILESET"
  local FLOOR="PEWTER_DUNGEON_FLOOR"
  local OWNER="pewter_dungeon_dev"
  local MUSEUM_SIGN_X,MUSEUM_SIGN_Y=15,9
  local MUSEUM_DOOR_X,MUSEUM_DOOR_Y=14,7
  -- Numeric index from Crystal's landmarkOrder. Custom maps must use the
  -- numeric landmark byte here; BattleMusic performs numeric region checks.
  -- DEV3 used the string "LANDMARK_SPECIAL", which crashed every battle.
  local PEWTER_LANDMARK=51
  local DELVE_MAP_MUSIC="Music_UnionCave"

  local GEAR_BOOTS="PD_MINER_BOOTS"
  local GEAR_ROPE="PD_SAFETY_ROPE"
  local GEAR_CHARM="PD_RELIC_CHARM"
  local GEAR_TRAP_WARD="PD_TRAP_WARD"
  local GEAR_PP_CHARM="PD_ECHO_CHARM"
  local ITEM_SURVEY_CHART="PD_SURVEY_CHART" -- legacy save compatibility; no longer generated
  local ITEM_DELVE_BALL="PD_DELVE_BALL"
  local SPECIAL={
    ESCAPE_LENS="PD_ESCAPE_LENS", ESCAPE_HATCH="PD_ESCAPE_HATCH", FIELD_CASE="PD_FIELD_CASE",
    FOSSIL_SCANR="PD_FOSSIL_SCANR", TRAP_SCANR="PD_TRAP_SCANR",
    WORKS_KEY="PD_WORKS_KEY", MEGALITH_KEY="PD_MEGALITH_KEY",
    HEAD_FOSSIL="PD_HEAD_FOSSIL", UBODY_FOSSIL="PD_UBODY_FOSSIL", LBODY_FOSSIL="PD_LBODY_FOSSIL",
  }
  SPECIAL.COOP=assert(load(assert(mod:read("coop.lua")),"@pewter_dungeon/coop.lua"))()
  local SWAP_SCREEN="PewterDungeonSwap"
  local BLIND_PIPELINE="pewter_dungeon_blind"
  local MAP_SCREEN="PewterDungeonMap"

  local function deep(v,seen)
    if type(v)~="table" then return v end
    seen=seen or {}
    if seen[v] then return seen[v] end
    local out={}; seen[v]=out
    for k,x in pairs(v) do out[deep(k,seen)]=deep(x,seen) end
    return out
  end

  local function clamp(v,a,b)
    v=tonumber(v) or 0
    if v<a then return a elseif v>b then return b end
    return v
  end

  -- All custom Dungeon Delvers dialogue is normalized before it reaches the
  -- Crystal textbox. Each page is at most two lines, and each line is wrapped
  -- by the actual Gen-II font width rather than hand-estimated spacing.
  local function dialoguePages(pages)
    local out={}
    local maxWidth=136
    local function pushWrappedLine(raw,lines)
      raw=tostring(raw or "")
      if raw=="" then lines[#lines+1]=""; return end
      local current=""
      for word in raw:gmatch("%S+") do
        local candidate=(current=="") and word or (current.." "..word)
        if current~="" and Font.width(candidate)>maxWidth then
          lines[#lines+1]=current
          current=word
        else
          current=candidate
        end
      end
      if current~="" then lines[#lines+1]=current end
    end
    for _,body in ipairs(pages or {}) do
      local lines={}
      local text=tostring(body or "")
      local start=1
      while true do
        local pos=text:find("\n",start,true)
        if pos then
          pushWrappedLine(text:sub(start,pos-1),lines)
          start=pos+1
        else
          pushWrappedLine(text:sub(start),lines)
          break
        end
      end
      if #lines==0 then lines[1]="" end
      local i=1
      while i<=#lines do
        local page=lines[i] or ""
        if lines[i+1]~=nil then page=page.."\n"..lines[i+1] end
        out[#out+1]=page
        i=i+2
      end
    end
    return out
  end

  local function showPages(world,pages,onDone)
    pages=dialoguePages(pages or {})
    local i=1
    local function nextPage()
      local body=pages[i]
      if not body then if onDone then onDone() end return end
      i=i+1
      world:showText(body,nextPage)
    end
    nextPage()
  end

  local function pdSave(game)
    game.save.pewterDungeon=game.save.pewterDungeon or {}
    return game.save.pewterDungeon
  end

  local function isActive(game)
    local s=game and game.save and game.save.pewterDungeon
    return s and s.active==true
  end

  -- Tiny deterministic RNG so a floor can be rebuilt from run seed + depth.
  local function rng(seed)
    local state=(math.floor(tonumber(seed) or 1)%2147483647)
    if state<=0 then state=1 end
    return function(n)
      state=(state*48271)%2147483647
      if not n then return state/2147483647 end
      return (state%n)+1
    end
  end

  -- DEV8 moves away from a narrow eligible roster.  Starters are drawn from
  -- essentially every non-legendary first-stage/single-stage species, while
  -- wilds and Delver trainers use an expanding power band that reaches nearly
  -- the entire non-legendary Gen-I/II roster as depth increases.
  local LEGENDARY={
    ARTICUNO=true,ZAPDOS=true,MOLTRES=true,MEWTWO=true,MEW=true,
    RAIKOU=true,ENTEI=true,SUICUNE=true,LUGIA=true,HO_OH=true,CELEBI=true,
  }

  -- DEV3 cave assembly sources.  Floors no longer clone an entire native map.
  -- Instead, we harvest compatible cave blocks from these maps and assemble a
  -- fresh room/corridor layout.  Rock Tunnel and Victory Road are preferred,
  -- with Johto caves as fallbacks when a cache names/tilesets differ.
  local CAVE_SOURCES={
    {id="ROCK_TUNNEL_1F",label="ROCK TUNNEL"},
    {id="ROCK_TUNNEL_B1F",label="ROCK TUNNEL"},
    {id="VICTORY_ROAD",label="VICTORY ROAD"},
    {id="UNION_CAVE_1F",label="UNION CAVE"},
    {id="UNION_CAVE_B1F",label="UNION CAVE"},
    {id="UNION_CAVE_B2F",label="UNION CAVE"},
    {id="DARK_CAVE_VIOLET_ENTRANCE",label="DARK CAVE"},
    {id="DARK_CAVE_BLACKTHORN_ENTRANCE",label="DARK CAVE"},
  }

  -- Dungeon strata. B1-B20 are four five-floor "Caves" layers using the
  -- familiar cave geometry with distinct private palette hues. Deeper strata
  -- stop cycling back to the beginning: DEV23 leaves a DEEP CAVES placeholder
  -- for the later roadmap pass that will introduce genuinely new tilesets.
  local HUE_BANDS={
    {label="SLATE CAVES",shift=0},
    {label="LIMESTONE CAVES",shift=28},
    {label="MOSS CAVES",shift=92},
    {label="AZURE CAVES",shift=188},
    {label="DEEP CAVES",shift=274},
  }

  local FLOOR_EFFECT_CHANCE=.15
  local MODIFIERS={
    {id="UNSTABLE",label="UNSTABLE CAVERN",desc="The floor gives way faster. More traps are active.",stability=.72,extraTraps=1},
    {id="RICH",label="RICH VEINS",desc="More valuables and fossil deposits can be found here.",extraLoot=2,fossilBonus=.12},
    {id="FOG",label="DENSE FOG",desc="Visibility and map discovery are greatly reduced.",visionMul=.68,exploreRadius=0},
    {id="HIDDEN",label="HIDDEN FLOOR",desc="The dungeon interferes with your minimap. Navigate this floor by sight.",hideMinimap=true},
    {id="NEST",label="NESTING GROUND",desc="More wild POKéMON and Delvers are roaming this floor.",extraMonsters=3,extraTrainers=1},
    {id="QUIET",label="QUIET FLOOR",desc="Fewer encounters and fewer loose supplies appear here.",extraMonsters=-2,extraTrainers=-1,extraLoot=-1},
    {id="ANCIENT",label="ANCIENT STRATA",desc="Fossils are more common, especially from ancient species.",extraLoot=1,fossilBonus=.18,ancientBias=.55},
    {id="TREMOR",label="TREMORS",desc="The cavern is shaking. Traps and collapse come sooner.",stability=.88,extraTraps=1},
    {id="FORTUNE",label="FORTUNE FLOOR",desc="Extra treasure has been exposed throughout the cavern.",extraLoot=3,extraTrainers=-1},
  }

  local ANCIENT={
    RATTATA={
      line={RATTATA=true,RATICATE=true},
      palette={{255,255,255},{190,145,85},{100,70,48},{0,0,0}},
      scale=1.14, adds={hp=8,attack=8,defense=5}, move="PURSUIT",
    },
    GEODUDE={
      line={GEODUDE=true,GRAVELER=true,GOLEM=true},
      palette={{255,255,255},{177,125,79},{82,91,93},{0,0,0}},
      scale=1.16, adds={hp=10,attack=5,specialDefense=10}, move="ANCIENTPOWER",
    },
    ONIX={
      line={ONIX=true,STEELIX=true},
      palette={{255,255,255},{188,171,144},{112,99,84},{0,0,0}},
      scale=1.18, adds={hp=10,attack=5,defense=10}, move="ROCK_THROW",
    },
    SANDSHREW={
      line={SANDSHREW=true,SANDSLASH=true},
      palette={{255,255,255},{184,139,79},{96,76,54},{0,0,0}},
      scale=1.15, adds={hp=5,attack=8,defense=10}, move="FURY_CUTTER",
    },
    CUBONE={
      line={CUBONE=true,MAROWAK=true},
      palette={{255,255,255},{166,128,86},{82,67,55},{0,0,0}},
      scale=1.13, adds={hp=5,attack=10,defense=8}, move="BONE_RUSH",
    },
    WOOPER={
      line={WOOPER=true,QUAGSIRE=true},
      palette={{255,255,255},{150,181,178},{78,105,105},{0,0,0}},
      scale=1.12, adds={hp=10,defense=8,specialDefense=5}, move="MUD_SLAP",
    },
    DUNSPARCE={
      line={DUNSPARCE=true},
      palette={{255,255,255},{198,173,120},{104,85,62},{0,0,0}},
      scale=1.15, adds={hp=12,attack=5,defense=5,speed=3}, move="ANCIENTPOWER",
    },
    GLIGAR={
      line={GLIGAR=true},
      palette={{255,255,255},{159,143,171},{78,67,94},{0,0,0}},
      scale=1.14, adds={attack=8,defense=8,speed=8}, move="WING_ATTACK",
    },
    SHUCKLE={
      line={SHUCKLE=true},
      palette={{255,255,255},{190,154,112},{100,76,58},{0,0,0}},
      scale=1.12, adds={hp=10,defense=8,specialDefense=8}, move="ROLLOUT",
    },
    SLUGMA={
      line={SLUGMA=true,MAGCARGO=true},
      palette={{255,255,255},{191,119,83},{101,65,54},{0,0,0}},
      scale=1.12, adds={hp=8,defense=8,specialAttack=8}, move="ROCK_THROW",
    },
    SWINUB={
      line={SWINUB=true,PILOSWINE=true},
      palette={{255,255,255},{187,170,145},{91,81,69},{0,0,0}},
      scale=1.14, adds={hp=10,attack=10,speed=5}, move="ANCIENTPOWER",
    },
    CORSOLA={
      line={CORSOLA=true},
      palette={{255,255,255},{193,158,151},{105,82,82},{0,0,0}},
      scale=1.13, adds={hp=10,defense=8,specialDefense=8}, move="RECOVER",
    },
    PHANPY={
      line={PHANPY=true,DONPHAN=true},
      palette={{255,255,255},{187,176,143},{91,87,78},{0,0,0}},
      scale=1.13, adds={hp=10,attack=10,specialDefense=5}, move="ANCIENTPOWER",
    },
  }

  local function ancientProfileForSpecies(species)
    for root,p in pairs(ANCIENT) do
      if p.line[species] then return root,p end
    end
  end

  local function monName(game,mon)
    local d=game and game.data and game.data.pokemon and game.data.pokemon[mon.species]
    return (d and d.name) or tostring(mon.species or "POKéMON")
  end

  local function speciesName(game,species)
    local d=game and game.data and game.data.pokemon and game.data.pokemon[species]
    return (d and d.name) or tostring(species)
  end

  local function healMon(mon)
    if not mon then return end
    mon.hp=mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp
    mon.status=nil
    for _,m in ipairs(mon.moves or {}) do m.pp=m.maxPp or m.pp end
  end

  local function healParty(save)
    for _,mon in ipairs((save and save.party) or {}) do healMon(mon) end
  end

  local function addMove(game,mon,id)
    if not (mon and id and game.data.moves and game.data.moves[id]) then return end
    for _,m in ipairs(mon.moves or {}) do if m.id==id then return end end
    mon.moves=mon.moves or {}
    if #mon.moves>=4 then table.remove(mon.moves,1) end
    local md=game.data.moves[id]
    mon.moves[#mon.moves+1]={id=id,pp=md.pp or 5,maxPp=md.pp or 5}
  end

  local function applyAncientStats(game,mon)
    local a=mon and mon.pewterAncient
    if not a then return end
    local _,profile=ancientProfileForSpecies(mon.species)
    profile=profile or ANCIENT[a.root]
    local def=game.data.pokemon and game.data.pokemon[mon.species]
    if not (profile and def and def.baseStats) then return end
    local bs=deep(def.baseStats)
    for k,v in pairs(profile.adds or {}) do bs[k]=(tonumber(bs[k]) or 1)+v end
    local oldMax=math.max(1,tonumber(mon.maxHp) or tonumber(mon.stats and mon.stats.hp) or 1)
    local ratio=clamp((tonumber(mon.hp) or oldMax)/oldMax,0,1)
    local st=Mon.stats(bs,mon.dvs or {},mon.level or 5,mon.statExp or {})
    mon.stats=st; mon.maxHp=st.hp; mon.hp=math.max(1,math.floor(st.hp*ratio+.5))
    a.palette=deep(profile.palette); a.scale=profile.scale; a.adds=deep(profile.adds)
  end

  local function markAncient(game,mon,root)
    local p=ANCIENT[root]
    if not (mon and p) then return mon end
    mon.pewterAncient={root=root,palette=deep(p.palette),scale=p.scale,adds=deep(p.adds)}
    applyAncientStats(game,mon)
    mon.pewterAncientStatsApplied=true
    addMove(game,mon,p.move)
    return mon
  end

  -- ANCIENT RESILIENCE: reduce super-effective damage by one type tier.
  -- 2x weaknesses become neutral; 4x weaknesses become 2x.
  mod.hooks:wrap("battle.damage",function(next,ctx)
    local damage,info=next(ctx)
    local target=ctx and ctx.target
    local eff=info and (info.effectiveness or info.typeMult)
    if target and target.pewterAncient and type(damage)=="number"
        and type(eff)=="number" and eff>10 then
      damage=math.max(1,math.floor(damage/2))
      local reduced=math.max(10,math.floor(eff/2))
      info.effectiveness=reduced
      if info.typeMult~=nil then info.typeMult=reduced end
    end
    return damage,info
  end)

  -- Register the three exploration gear pieces now. They are normal held items
  -- whose prototype effects are read by the dungeon systems below.
  mod.content.items:register(GEAR_BOOTS,{
    id=GEAR_BOOTS,name="MINER BOOTS",price=0,pocket="ITEM",
    fieldMenu="ITEMMENU_NOUSE",battleMenu="ITEMMENU_NOUSE",
    description="Held: often avoids\ndelve traps.",
  })
  mod.content.items:register(GEAR_ROPE,{
    id=GEAR_ROPE,name="SAFETY ROPE",price=0,pocket="ITEM",
    fieldMenu="ITEMMENU_NOUSE",battleMenu="ITEMMENU_NOUSE",
    description="Held: blocks one\ncollapse penalty.",
  })
  mod.content.items:register(GEAR_CHARM,{
    id=GEAR_CHARM,name="RELIC CHARM",price=0,pocket="ITEM",
    fieldMenu="ITEMMENU_NOUSE",battleMenu="ITEMMENU_NOUSE",
    description="Held: fossil odds\nrise slightly.",
  })
  mod.content.items:register(GEAR_TRAP_WARD,{
    id=GEAR_TRAP_WARD,name="WARD CHARM",price=0,pocket="ITEM",
    fieldMenu="ITEMMENU_NOUSE",battleMenu="ITEMMENU_NOUSE",
    description="Held: blocks one\ndelve trap.",
  })
  mod.content.items:register(GEAR_PP_CHARM,{
    id=GEAR_PP_CHARM,name="ECHO CHARM",price=0,pocket="ITEM",
    fieldMenu="ITEMMENU_NOUSE",battleMenu="ITEMMENU_NOUSE",
    description="Held: refills one\nmove at 0 PP.",
  })
  mod.content.items:register(ITEM_SURVEY_CHART,{
    id=ITEM_SURVEY_CHART,name="SURVEY CHART",price=0,pocket="ITEM",
    fieldMenu="ITEMMENU_CLOSE",battleMenu="ITEMMENU_NOUSE",
    description="Reveals the whole\ncurrent delve map.",
  })
  mod.content.items:register(ITEM_DELVE_BALL,{
    id=ITEM_DELVE_BALL,name="DELVE BALL",price=0,pocket="BALL",
    fieldMenu="ITEMMENU_NOUSE",battleMenu="ITEMMENU_USE",
    description="Delve-only Ball.\nFully heals the catch.",
  })
  mod.content.items:register(SPECIAL.ESCAPE_LENS,{
    id=SPECIAL.ESCAPE_LENS,name="ESCAPE LENS",price=0,pocket="ITEM",
    fieldMenu="ITEMMENU_CLOSE",battleMenu="ITEMMENU_NOUSE",
    description="Reveals the ladder\non this delve floor.",
  })
  mod.content.items:register(SPECIAL.ESCAPE_HATCH,{
    id=SPECIAL.ESCAPE_HATCH,name="ESCAPE HATCH",price=0,pocket="ITEM",
    fieldMenu="ITEMMENU_CLOSE",battleMenu="ITEMMENU_NOUSE",
    description="Drops you straight\nto the next floor.",
  })
  mod.content.items:register(SPECIAL.FOSSIL_SCANR,{
    id=SPECIAL.FOSSIL_SCANR,name="FOSSIL SCANR",price=0,pocket="ITEM",
    fieldMenu="ITEMMENU_CLOSE",battleMenu="ITEMMENU_NOUSE",
    description="Marks fossil rocks\non this floor's map.",
  })
  mod.content.items:register(SPECIAL.TRAP_SCANR,{
    id=SPECIAL.TRAP_SCANR,name="TRAP SCANR",price=0,pocket="ITEM",
    fieldMenu="ITEMMENU_CLOSE",battleMenu="ITEMMENU_NOUSE",
    description="Reveals hidden traps\non this delve floor.",
  })
  -- Keep the internal PD_FIELD_CASE id for save compatibility, but expose it
  -- as a delve-only Key Item so it no longer clutters the consumable pocket.
  mod.content.items:register(SPECIAL.FIELD_CASE,{
    id=SPECIAL.FIELD_CASE,name="DELVE CASE",price=0,pocket="KEY_ITEM",
    tossable=false,canToss=false,
    fieldMenu="ITEMMENU_CLOSE",battleMenu="ITEMMENU_NOUSE",
    description="Fossils and finds\nfrom this delve.",
  })
  mod.content.items:register(SPECIAL.WORKS_KEY,{
    id=SPECIAL.WORKS_KEY,name="WORKS KEY",price=0,pocket="KEY_ITEM",
    tossable=false,canToss=false,
    fieldMenu="ITEMMENU_NOUSE",battleMenu="ITEMMENU_NOUSE",
    description="A key to the sealed\nB20 deeper route.",
  })
  mod.content.items:register(SPECIAL.MEGALITH_KEY,{
    id=SPECIAL.MEGALITH_KEY,name="MEGALITH KEY",price=0,pocket="KEY_ITEM",
    tossable=false,canToss=false,
    fieldMenu="ITEMMENU_NOUSE",battleMenu="ITEMMENU_NOUSE",
    description="A key to the sealed\nB40 deeper route.",
  })
  for id,name in pairs({
    [SPECIAL.HEAD_FOSSIL]="HEAD FOSSIL",[SPECIAL.UBODY_FOSSIL]="UBODY FOSSIL",
    [SPECIAL.LBODY_FOSSIL]="LBODY FOSSIL",
  }) do
    mod.content.items:register(id,{id=id,name=name,price=0,pocket="ITEM",
      fieldMenu="ITEMMENU_NOUSE",battleMenu="ITEMMENU_NOUSE",
      description="A fossil piece kept\nin your DELVE CASE."})
  end
  if mod.content.balls then
    mod.content.balls:register(ITEM_DELVE_BALL,{randMax=255,multiplier=1.5})
  end

  -- Delves use the same world-only darkness architecture as PhasmoPokea.
  -- The normal delve beam is intentionally close to Powerlight scale: roughly
  -- 50% wider than DEV14 and with a subtle two-wave "breathing" pulse.  The
  -- area outside the aperture is almost black.  Because this is worldPresent,
  -- Crystal menus/text are still composited cleanly on top by the engine.
  local blindWorldCanvas=nil
  local blindPresentCanvas=nil
  mod.content.render_pipelines:register(BLIND_PIPELINE,{
    label="DELVE BLIND",levels={"OFF","ON"},priority=88,
    drawWorld=function(ctx)
      local ow=ctx and ctx.state
      local s=mod.game and mod.game.save and mod.game.save.pewterDungeon
      if not (ow and ow.map and ow.map.id==FLOOR and s and s.active) then return nil end
      local G=love.graphics; local w,h=ctx.width,ctx.height
      if not blindWorldCanvas or blindWorldCanvas:getWidth()~=w or blindWorldCanvas:getHeight()~=h then
        blindWorldCanvas=G.newCanvas(w,h)
      end
      local prev=G.getCanvas()
      G.push("all"); G.origin(); G.setCanvas(blindWorldCanvas)
      G.clear(.035,.035,.045,1); G.setColor(1,1,1,1)
      ow:drawWorldBody(ctx.scale)
      G.setCanvas(prev); G.pop()
      return blindWorldCanvas
    end,
    worldPresent=function(canvas,ctx)
      local ow=ctx and ctx.state
      local s=mod.game and mod.game.save and mod.game.save.pewterDungeon
      if not (canvas and ow and ow.map and ow.map.id==FLOOR and s and s.active) then return canvas end
      local G=love.graphics; local w,h=canvas:getDimensions()
      if not blindPresentCanvas or blindPresentCanvas:getWidth()~=w or blindPresentCanvas:getHeight()~=h then
        blindPresentCanvas=G.newCanvas(w,h)
      end
      local prev=G.getCanvas()
      G.push("all"); G.origin(); G.setCanvas(blindPresentCanvas); G.clear(0,0,0,1)
      G.setColor(1,1,1,1); G.draw(canvas,0,0)

      -- Give the visible patch a slightly murky cave cast without obscuring it.
      G.setColor(.055,.070,.085,.22); G.rectangle("fill",0,0,w,h)

      local blinded=(tonumber(s.blindSteps) or 0)>0
      local now=love.timer and love.timer.getTime and love.timer.getTime() or 0
      local radiusTiles
      if blinded then
        radiusTiles=2.6 + 0.12*math.sin(now*2.6)
      else
        -- DEV28 opens normal delve visibility another ~25% beyond DEV25.
        -- Blindness remains intentionally tight so the trap/status still matters.
        radiusTiles=9.75 + 0.475*math.sin(now*1.85) + 0.175*math.sin(now*4.9)
        local fs=s and s.floorState
        local modf=fs and fs.modifier
        if modf and tonumber(modf.visionMul) then
          radiusTiles=radiusTiles*tonumber(modf.visionMul)
        end
      end

      local p,cam=ow.player,ow.camera
      local scale=ctx.scale or ((ow.zoomScale and ow:zoomScale()) or 1)
      local cx,cy=w/2,h/2
      if p and cam then
        cx=(p.px-cam.x+8)*scale; cy=(p.py-cam.y+4)*scale
      end
      cx,cy=math.floor(cx+.5),math.floor(cy+.5)
      local tile=math.max(4,math.floor(8*scale+.5))
      local r=math.max(tile*1.5,radiusTiles*tile)
      local band=math.max(2,math.floor(r/4))
      local top=math.floor(cy-r); local bottom=math.ceil(cy+r)
      local edges={
        {-4,-3,.48},{-3,-2,.72},{-2,-1,.90},{-1,1,1.00},
        {1,2,.90},{2,3,.72},{3,4,.48},
      }

      -- Outside the light should be functionally unreadable rather than merely
      -- dim.  Keep a tiny amount of world color so the mask does not look like
      -- a hard black UI rectangle on LCD-style scaling.
      G.setColor(.0015,.003,.010,.985)
      if top>0 then G.rectangle("fill",0,0,w,top) end
      if bottom<h then G.rectangle("fill",0,bottom,w,h-bottom) end
      for edgeIndex,e in ipairs(edges) do
        local y1=(edgeIndex==1) and top or math.max(top,math.floor(cy+e[1]*band))
        local y2=(edgeIndex==#edges) and bottom or math.min(bottom,math.ceil(cy+e[2]*band))
        if y2>y1 then
          local half=math.floor(r*e[3])
          local left=math.max(0,math.floor(cx-half))
          local right=math.min(w,math.ceil(cx+half))
          if left>0 then G.rectangle("fill",0,y1,left,y2-y1) end
          if right<w then G.rectangle("fill",right,y1,w-right,y2-y1) end
        end
      end

      G.setCanvas(prev); G.pop()
      return blindPresentCanvas
    end,
  })

  -- Ancient visuals. Mutant Monster Lab can coexist: this wrapper only acts on
  -- pewterAncient and composes with whatever renderer is already downstream.
  do
    local BattleState=require("src.ui.gen2.BattleState")
    if not BattleState.__pewterAncientVisualWrapped then
      BattleState.__pewterAncientVisualWrapped=true
      local downstreamDraw=BattleState.drawPic
      local downstreamScale=BattleState.picScale

      local function withAncientPalette(mon,fn)
        local a=mon and mon.pewterAncient
        if not (a and a.palette) then return fn() end
        local original=Palettes.monColors
        Palettes.monColors=function(data,species,shiny)
          if species==mon.species then
            -- Preserve the species' native outer palette colors. Summary
            -- frontpics fill their 7x7 block with palette color 0, so replacing
            -- that color creates a visible square around Ancient sprites.
            local base=original(data,species,shiny)
            local pal=deep(a.palette)
            if type(base)=="table" then
              if base[1] then pal[1]=deep(base[1]) end
              if base[4] then pal[4]=deep(base[4]) end
            end
            return pal
          end
          return original(data,species,shiny)
        end
        local ok,x,y,z=pcall(fn)
        Palettes.monColors=original
        if not ok then error(x) end
        return x,y,z
      end

      BattleState.drawPic=function(self,mon,back)
        return withAncientPalette(mon,function()
          return downstreamDraw(self,mon,back)
        end)
      end
      BattleState.picScale=function(self,path,mon,back)
        local base=downstreamScale(self,path,mon,back)
        local s=tonumber(mon and mon.pewterAncient and mon.pewterAncient.scale)
        return s and base*s or base
      end

      local Summary=require("src.ui.gen2.SummaryMenu")
      local summaryDraw=Summary.drawPic
      Summary.drawPic=function(self)
        local mon=self.mon
        return withAncientPalette(mon,function() return summaryDraw(self) end)
      end


      -- Ancient Pokemon use Crystal's shiny-icon slot for their own 8x8 mark.
      local ancientIconLoaded=false
      local ancientIcon=nil
      local function getAncientIcon()
        if ancientIconLoaded then return ancientIcon end
        ancientIconLoaded=true
        local ok,v=pcall(function() return mod.assets:image("assets/ancientsymbol.png") end)
        if ok and v then
          if v.setFilter then pcall(function() v:setFilter("nearest","nearest") end) end
          ancientIcon=v
        end
        return ancientIcon
      end
      local summaryUpper=Summary.drawUpperHalf
      Summary.drawUpperHalf=function(self)
        summaryUpper(self)
        local mon=self.mon
        if mon and mon.pewterAncient then
          local icon=getAncientIcon()
          if icon then
            local G=love.graphics
            G.setColor(1,1,1,1)
            G.rectangle("fill",19*8,0,8,8)
            G.draw(icon,19*8,0)
          end
        end
      end
    end
  end

  mod.events:on("pokemon.evolved",function(ev)
    local mon=ev and ev.mon
    if mon and mon.pewterAncient then
      applyAncientStats(mod.game,mon)
      mon.pewterAncientStatsApplied=true
      local root,p=ancientProfileForSpecies(mon.species)
      if root and p then
        mon.pewterAncient.root=root
        mon.pewterAncient.palette=deep(p.palette)
        mon.pewterAncient.scale=p.scale
      end
    end
  end)

  -- Ancient stat profiles persist after Summary refreshes and future level-ups.
  -- If Mutant Monster Lab later gives the same individual explicit mutant stat
  -- overrides, those take precedence instead of stacking two overhaul systems.
  do
    local downstreamRefresh=Mon.refreshStats
    local downstreamGain=Mon.gainExperience

    local function ancientStats(mon,data)
      if not (mon and mon.pewterAncient) then return nil end
      local f=mon.cinnabarFusion
      if f and f.statOverrides then return nil end
      local root,p=ancientProfileForSpecies(mon.species)
      p=p or ANCIENT[mon.pewterAncient.root]
      local def=data and data.pokemon and data.pokemon[mon.species]
      if not (p and def and def.baseStats) then return nil end
      local bs=deep(def.baseStats)
      for k,v in pairs(p.adds or {}) do bs[k]=(tonumber(bs[k]) or 1)+v end
      return Mon.stats(bs,mon.dvs or {},mon.level or 1,mon.statExp or {}),p,root
    end

    Mon.refreshStats=function(mon,data)
      local oldMax=mon and (mon.maxHp or (mon.stats and mon.stats.hp))
      local oldHp=mon and mon.hp
      local wasAncient=mon and mon.pewterAncientStatsApplied
      local out=downstreamRefresh(mon,data)
      local stats,p,root=ancientStats(mon,data)
      if not stats then return out end
      mon.stats=stats; mon.maxHp=stats.hp
      if oldMax and oldHp~=nil and wasAncient then
        mon.hp=math.max(0,math.min(stats.hp,oldHp+(stats.hp-oldMax)))
      else
        mon.hp=math.max(0,math.min(stats.hp,mon.hp or stats.hp))
      end
      mon.pewterAncientStatsApplied=true
      if p then
        mon.pewterAncient.palette=deep(p.palette)
        mon.pewterAncient.scale=p.scale
        if root then mon.pewterAncient.root=root end
      end
      return mon
    end

    Mon.gainExperience=function(mon,amount,data)
      local oldMax=mon and (mon.maxHp or (mon.stats and mon.stats.hp))
      local oldHp=mon and mon.hp
      local oldLevel=mon and mon.level
      local out=downstreamGain(mon,amount,data)
      if mon and mon.pewterAncient and mon.level~=oldLevel then
        local stats,p,root=ancientStats(mon,data)
        if stats then
          mon.stats=stats; mon.maxHp=stats.hp
          if oldMax and oldHp~=nil then
            mon.hp=math.max(0,math.min(stats.hp,oldHp+(stats.hp-oldMax)))
          end
          mon.pewterAncientStatsApplied=true
          if p then
            mon.pewterAncient.palette=deep(p.palette)
            mon.pewterAncient.scale=p.scale
            if root then mon.pewterAncient.root=root end
          end
        end
      end
      return out
    end
  end

  -- Rapid roguelike leveling without touching normal Crystal battles.
  -- DEV72 trims the delve multiplier by 15% (2.50x -> 2.125x) so the player's
  -- party does not outpace the guardian curve quite as aggressively.
  mod.hooks:wrap("exp.gain",function(next,ctx)
    local amount=next(ctx)
    local game=mod.game
    if isActive(game) then return math.max(1,math.floor((tonumber(amount) or 0)*2.125)) end
    return amount
  end,180)

  -- Pewter exterior + museum lobby ------------------------------------------------
  local maps=mod.game and mod.game.data and mod.game.data.gen2Maps
  local tilesets=mod.game and mod.game.data and mod.game.data.gen2Tilesets
  local pewter=maps and maps[PEWTER]
  local lobbyTemplate=maps and (maps.SILPH_CO_1F or maps.RUINS_OF_ALPH_RESEARCH_CENTER)
  local floorTemplate=nil
  if maps then
    for _,row in ipairs(CAVE_SOURCES) do
      if maps[row.id] then floorTemplate=maps[row.id] break end
    end
    floorTemplate=floorTemplate or maps.UNION_CAVE_1F or maps.DARK_CAVE_VIOLET_ENTRANCE
  end

  local exteriorWarpIndex=nil
  local lobbyReception={x=4,y=3}
  local lobbyResearch={x=7,y=3}

  if pewter and lobbyTemplate and floorTemplate then
    -- Restore the museum at its original Gen-I doorway coordinate (14,7),
    -- but do NOT paste an entire Gym metatile over Pewter's museum facade.
    -- Build one extra Kanto metatile instead: keep the museum wall block and
    -- transplant only the 16x16 door quadrant from Pewter Gym's native door.
    -- This leaves the museum architecture intact while giving the doorway the
    -- same graphics/collision semantics as a real Crystal entrance.
    local editedBlocks=deep(pewter.blocks or {})
    local function blockIndex(def,cx,cy)
      return math.floor(cy/2)*def.width+math.floor(cx/2)+1
    end
    local dst=blockIndex(pewter,MUSEUM_DOOR_X,MUSEUM_DOOR_Y)
    local gym=blockIndex(pewter,16,17)
    local museumBlockId=editedBlocks[dst]
    local gymDoorBlockId=editedBlocks[gym]
    local kanto=tilesets and tilesets[pewter.tileset]
    local customDoorBlockId=128 -- vanilla Gen-II tilesets expose blocks 0..127
    if kanto and kanto.blocks and kanto.collision
        and museumBlockId and gymDoorBlockId
        and kanto.blocks[museumBlockId+1] and kanto.blocks[gymDoorBlockId+1] then
      local hybrid=deep(kanto.blocks[museumBlockId+1])
      local source=deep(kanto.blocks[gymDoorBlockId+1])
      -- Both doorway cells occupy the lower-left 16x16 quadrant of their
      -- respective 32x32 metatiles: tile rows 3-4, columns 1-2.
      for _,i in ipairs({9,10,13,14}) do hybrid[i]=source[i] end
      kanto.blocks[customDoorBlockId+1]=hybrid

      local coll=deep(kanto.collision[museumBlockId+1] or {})
      local sourceColl=kanto.collision[gymDoorBlockId+1] or {}
      coll[3]=sourceColl[3] or 0x71 -- lower-left cell / COLL_DOOR
      kanto.collision[customDoorBlockId+1]=coll
      editedBlocks[dst]=customDoorBlockId
    end

    local warps=deep(pewter.warps or {})
    exteriorWarpIndex=#warps+1
    warps[#warps+1]={x=MUSEUM_DOOR_X,y=MUSEUM_DOOR_Y,destMap=LOBBY,destWarp=1}
    local bgEvents={}
    for _,ev in ipairs(pewter.bgEvents or {}) do
      if not (ev.x==MUSEUM_SIGN_X and ev.y==MUSEUM_SIGN_Y) then
        bgEvents[#bgEvents+1]=deep(ev)
      end
    end
    mod.content.maps:patch(PEWTER,{blocks=editedBlocks,warps=warps,bgEvents=bgEvents})

    local lobby=deep(lobbyTemplate)
    lobby.id=LOBBY; lobby.label="Pewter Dungeon Museum"; lobby.name="PEWTER MUSEUM"
    lobby.index=1190; lobby.landmark=PEWTER_LANDMARK
    lobby.connections={}; lobby.bgEvents={}; lobby.coordEvents={}; lobby.sceneScripts={}; lobby.callbacks={}

    -- Reuse the lobby template's native door coordinates and redirect them to
    -- our newly restored Pewter exterior warp.
    local nativeWarps=deep(lobbyTemplate.warps or {})
    lobby.warps={}
    if #nativeWarps>0 then
      for i,w in ipairs(nativeWarps) do
        if i<=2 then
          local c=deep(w); c.destMap=PEWTER; c.destWarp=exteriorWarpIndex
          lobby.warps[#lobby.warps+1]=c
        end
      end
    end
    if #lobby.warps==0 then
      lobby.warps={{x=4,y=7,destMap=PEWTER,destWarp=exteriorWarpIndex}}
    end

    -- Borrow the template NPC coordinates so we know they are valid floor cells.
    local srcObjects=lobbyTemplate.objects or {}
    if srcObjects[1] then lobbyReception={x=srcObjects[1].x,y=srcObjects[1].y} end
    if srcObjects[2] then lobbyResearch={x=srcObjects[2].x,y=srcObjects[2].y}
    else lobbyResearch={x=lobbyReception.x+3,y=lobbyReception.y} end
    lobby.objects={
      {index=1,sprite="SPRITE_PRYCE",x=lobbyReception.x,y=lobbyReception.y,
       movement=6,radius={x=0,y=0},hours={-1,-1},palette=0,type=0,sight=0,
       text="TEXT_PEWTER_DUNGEON_RECEPTION",pewterRole="reception"},
    }

    -- Museum staircase: keep the same horizontal placement but move it one
    -- metatile row (two player tiles) upward from DEV48, per the room layout.
    local lobbyBlocks=deep(lobby.blocks or {})
    local lobbyW=tonumber(lobby.width) or 8
    local stairBX,stairBY=6,0
    local stairIndex=stairBY*lobbyW+stairBX+1
    if lobbyBlocks[stairIndex] then lobbyBlocks[stairIndex]=4 end
    lobby.blocks=lobbyBlocks
    lobby.warps[#lobby.warps+1]={x=stairBX*2+1,y=stairBY*2,destMap=UPSTAIRS,destWarp=1}
    local lobbyUpWarp=#lobby.warps

    -- Build the upstairs from the unused museum fossil-table artwork supplied
    -- with the project. The custom atlas is still an ordinary Gen-II 8x8
    -- tileset: 4 displays across the top, 3 in the middle, 1 at the bottom,
    -- with the staircase in the lower-left exactly like the approved mockup.
    tilesets[MUSEUM_2F_TILESET]={
      id=MUSEUM_2F_TILESET,
      image=mod.assets:path("assets/museum2f_tiles.png"),
      imageWidth=Museum2F.imageWidth,
      imageHeight=Museum2F.imageHeight,
      tilesPerRow=Museum2F.tilesPerRow or 16,
      blocks=deep(Museum2F.blocks),
      collision=deep(Museum2F.collision),
      trueColor=true,
    }

    local upstairs=deep(lobbyTemplate)
    upstairs.id=UPSTAIRS; upstairs.label="Pewter Museum 2F"; upstairs.name="PEWTER MUSEUM 2F"
    upstairs.index=1192; upstairs.landmark=PEWTER_LANDMARK
    upstairs.width=8; upstairs.height=4
    upstairs.tileset=MUSEUM_2F_TILESET; upstairs.tilesetId=11
    upstairs.borderBlock=Museum2F.borderBlock or 1
    upstairs.connections={}; upstairs.bgEvents={}; upstairs.coordEvents={}
    upstairs.sceneScripts={}; upstairs.callbacks={}
    upstairs.blocks=deep(Museum2F.mapBlocks)
    upstairs.objects={
      {index=1,sprite="SPRITE_SCIENTIST",x=14,y=6,
       movement=6,radius={x=0,y=0},hours={-1,-1},palette=0,type=0,sight=0,
       text="TEXT_PEWTER_DUNGEON_RESEARCH",pewterRole="research"},
    }
    -- Lower-left staircase in the approved room layout.
    upstairs.warps={{x=1,y=7,destMap=LOBBY,destWarp=lobbyUpWarp}}
    mod.content.maps:register(UPSTAIRS,upstairs)
    mod.content.maps:register(LOBBY,lobby)

    local initFloor=deep(floorTemplate)
    initFloor.id=FLOOR; initFloor.label="Pewter Dungeon"; initFloor.name="PEWTER DUNGEON"
    initFloor.index=1191; initFloor.landmark=PEWTER_LANDMARK
    initFloor.connections={}; initFloor.objects={}; initFloor.bgEvents={}; initFloor.coordEvents={}
    initFloor.sceneScripts={}; initFloor.callbacks={}; initFloor.warps={}
    mod.content.maps:register(FLOOR,initFloor)
  else
    mod.log:warn("Pewter Dungeon: required Crystal maps were unavailable")
  end

  -- Custom map IDs are not present in the ROM's map-song table. Give the
  -- generated delve map an explicit native cave track so entering B1 switches
  -- away from Pewter/lobby music and battle returns restore cave music.
  do
    local audio=mod.game and mod.game.data and mod.game.data.audio
    if audio and audio.mapSongs and audio.songs and audio.songs[DELVE_MAP_MUSIC] then
      audio.mapSongs[FLOOR]=DELVE_MAP_MUSIC
      -- The lobby is a repurposed interior but should hand control back to
      -- Pewter City's native theme the instant a delve ends.
      audio.mapSongs[LOBBY]=audio.mapSongs[PEWTER] or "Music_Pewter"
      audio.mapSongs[UPSTAIRS]=audio.mapSongs[PEWTER] or "Music_Pewter"
    end
  end

  -- The museum attendant uses Pryce's overworld art, but a dedicated dark
  -- slate palette rather than any of Crystal's stock NPC browns/rocks.  Do it
  -- at sprite-palette application time so no other NPC/rock palette is changed.
  if not World.__pewterDungeonReceptionPaletteWrapped then
    World.__pewterDungeonReceptionPaletteWrapped=true
    local baseApplySpritePalette=World.applySpritePalette
    function World:applySpritePalette(entity)
      if entity and entity.def and entity.def.pewterRole=="reception"
          and entity.sprite and entity.sprite.setObjPalette then
        entity.sprite:setObjPalette({
          {248,248,248}, -- highlight / white
          {255,156,82},  -- requested warm skin tone (#ff9c52)
          {58,72,86},    -- clothing: dark slate gray
          {0,0,0},
        },"pewter_dungeon:slate_attendant")
        return
      end
      return baseApplySpritePalette(self,entity)
    end
  end

  -- Ensure the restored museum door acts like a native Gen-II door even though
  -- Crystal originally shipped it as inert scenery.
  if not Map.__pewterDungeonDoorWrapped then
    Map.__pewterDungeonDoorWrapped=true
    local baseCellCollision=Map.cellCollision
    function Map:cellCollision(cx,cy)
      if self.id==PEWTER and cx==MUSEUM_DOOR_X and cy==MUSEUM_DOOR_Y then return 0x71 end
      return baseCellCollision(self,cx,cy)
    end
  end

  -- Run state lives in save for escrow safety; floorState is rebuilt each depth.
  local floorState=nil
  local transitioning=false

  -- Once a trap fires, leave the native Battle Tower battle-room pressure
  -- plate on that cell. The exact matching 16x16 plate begins at x=16,y=0 in
  -- BATTLE_TOWER_BATTLE_ROOM; we sample Crystal's baked map at runtime instead
  -- of shipping/recreating the user's reference image.
  local trapPlateCache={}
  local function getTrapPlate(world)
    if not (world and world.imageFor) then return nil,nil end
    local img=world:imageFor("BATTLE_TOWER_BATTLE_ROOM")
    if not img then return nil,nil end
    local iw,ih=img:getDimensions()
    if trapPlateCache.image~=img or trapPlateCache.w~=iw or trapPlateCache.h~=ih or not trapPlateCache.quad then
      trapPlateCache.image=img; trapPlateCache.w=iw; trapPlateCache.h=ih
      -- Exact 16x16 Battle Tower wall plate. The old 0,0 crop straddled two
      -- wall cells, which is why only its lower half resembled the reference.
      trapPlateCache.quad=love.graphics.newQuad(16,0,16,16,iw,ih)
    end
    return trapPlateCache.image,trapPlateCache.quad
  end

  if not World.__pewterDungeonTrapMarks then
    World.__pewterDungeonTrapMarks=true
    local baseDrawGround=World.drawGround
    function World:drawGround(scale)
      baseDrawGround(self,scale)
      if self.map and self.map.id==FLOOR and floorState and floorState.traps then
        local img,quad=getTrapPlate(self)
        if img and quad then
          local G=love.graphics; local cam=self.camera; scale=scale or 1
          G.push("all"); G.scale(scale,scale); G.setColor(1,1,1,1)
          for _,tr in pairs(floorState.traps) do
            if tr.used or tr.revealed then
              G.setColor(1,1,1,1)
              G.draw(img,quad,tr.x*16-cam.x,tr.y*16-cam.y)
            end
          end
          local sf=floorState.specialFeature
          if sf and sf.panels then
            G.setColor(.65,.8,1,1)
            for _,pt in ipairs(sf.panels) do G.draw(img,quad,pt.x*16-cam.x,pt.y*16-cam.y) end
          end
          if sf and sf.hazards then
            for _,hz in pairs(sf.hazards) do
              -- Hazard-floor plates are hidden like normal traps until sprung
              -- or exposed by a TRAP SCANR.
              if hz.used or hz.revealed then
                if hz.kind=="TOXIC" then G.setColor(.72,.38,.86,1) else G.setColor(1,.55,.24,1) end
                G.draw(img,quad,hz.x*16-cam.x,hz.y*16-cam.y)
              end
            end
          end
          G.setColor(1,1,1,1)
          G.pop()
        end
      end
    end
  end

  -- Trap/battle carry-over ------------------------------------------------------
  -- CHAOS scrambles the overworld d-pad while leaving menus untouched.
  if not World.__pewterDungeonChaosInputWrapped then
    World.__pewterDungeonChaosInputWrapped=true
    local basePollInput=World.pollInput
    function World:pollInput(input)
      basePollInput(self,input)
      local s=self.game and self.game.save and self.game.save.pewterDungeon
      if self.map and self.map.id==FLOOR and s and s.active
          and (tonumber(s.chaosSteps) or 0)>0 and s.chaosMap and self.heldDir then
        self.heldDir=s.chaosMap[self.heldDir] or self.heldDir
      end
    end
  end

  -- The Chaos trap also confuses the lead at the start of the NEXT battle.
  if not Battle.__pewterDungeonNewWrapped then
    Battle.__pewterDungeonNewWrapped=true
    local baseBattleNew=Battle.new
    Battle.new=function(opts)
      local battle=baseBattleNew(opts)
      local save=battle and battle.save
      local s=save and save.pewterDungeon
      if s and s.active and s.nextBattleConfused and battle.player then
        local v=battle:volatile(battle.player)
        v.confuseCount=4
        s.nextBattleConfused=nil
      end
      return battle
    end
  end

  -- Wild Delve encounters can be escaped, but the cave gives the pursuer an
  -- advantage. Trainer battles remain governed by Crystal's normal no-run rule.
  mod.hooks:wrap("battle.run",function(next,ctx)
    local game=mod.game
    if game and isActive(game) and ctx and ctx.battle and ctx.battle.wild then
      local old=ctx.eSpd
      ctx.eSpd=math.max(1,math.floor((tonumber(ctx.eSpd) or 1)*1.35))
      local result=next(ctx)
      ctx.eSpd=old
      return result
    end
    return next(ctx)
  end,930)

  -- ECHO CHARM is a one-shot held PP safety net. It only consumes itself when
  -- the user's selected move actually reaches zero PP.
  if not Battle.__pewterDungeonPpWrapped then
    Battle.__pewterDungeonPpWrapped=true
    local baseUseMove=Battle.useMove
    function Battle:useMove(attacker,defender,moveId)
      local move=self:findMove(attacker,moveId)
      local before=move and tonumber(move.pp) or nil
      local out={baseUseMove(self,attacker,defender,moveId)}
      local s=self.save and self.save.pewterDungeon
      if s and s.active and attacker and self:sideOf(attacker)=="player"
          and attacker.item==GEAR_PP_CHARM and before and before>0
          and move and (tonumber(move.pp) or 0)<=0 then
        attacker.item=nil
        move.pp=move.maxPp or before
        self:emit({kind="message",text="The ECHO CHARM\nrestored the move's PP!"})
      end
      return out[1]
    end
  end

  -- SURVEY CHART is a field-use consumable. Reuse PackMenu's normal
  -- "PLAYER used ITEM" result path after setting the per-floor reveal flag.
  if not World.__pewterDungeonFieldItemWrapped then
    World.__pewterDungeonFieldItemWrapped=true
    local baseUseFieldItem=World.useFieldItem
    function World:useFieldItem(itemId)
      local s=self.game and self.game.save and self.game.save.pewterDungeon
      if itemId==ITEM_SURVEY_CHART or itemId==SPECIAL.ESCAPE_LENS then
        if not (self.map and self.map.id==FLOOR and s and s.active and floorState) then
          return "nowhere"
        end
        if itemId==ITEM_SURVEY_CHART then
          floorState.mapRevealed=true -- legacy charts from older saves still work.
          s.mapRevealFloor=floorState.depth
        else
          floorState.exitRevealed=true
          s.exitRevealFloor=floorState.depth
        end
        Bag.remove(self.game.save,itemId,1)
        if self.playSfxNamed then self:playSfxNamed("Sfx_Item") end
        return "repel_used"
      elseif itemId==SPECIAL.FOSSIL_SCANR then
        if not (self.map and self.map.id==FLOOR and s and s.active and floorState) then
          return "nowhere"
        end
        floorState.fossilsRevealed=true
        s.fossilRevealFloor=floorState.depth
        Bag.remove(self.game.save,itemId,1)
        Sound.dropPressSfx()
        if self.playSfxNamed then self:playSfxNamed("Sfx_Item") end
        return "repel_used"
      elseif itemId==SPECIAL.TRAP_SCANR then
        if not (self.map and self.map.id==FLOOR and s and s.active and floorState) then
          return "nowhere"
        end
        floorState.trapsRevealed=true
        for _,tr in pairs(floorState.traps or {}) do tr.revealed=true end
        local sf=floorState.specialFeature
        if sf and sf.hazards then
          for _,hz in pairs(sf.hazards) do hz.revealed=true end
        end
        if SPECIAL.COOP then SPECIAL.COOP.revealAllTraps(self.game) end
        Bag.remove(self.game.save,itemId,1)
        Sound.dropPressSfx()
        if self.playSfxNamed then self:playSfxNamed("Sfx_Item") end
        return "repel_used"
      elseif itemId==SPECIAL.ESCAPE_HATCH then
        if not (self.map and self.map.id==FLOOR and s and s.active and floorState
            and not floorState.checkpoint and not floorState.bossAlive) then return "nowhere" end
        Bag.remove(self.game.save,itemId,1)
        s.pendingEscapeHatch=true
        if self.playSfxNamed then self:playSfxNamed("Sfx_Kinesis") end
        return "repel_used"
      elseif itemId==SPECIAL.FIELD_CASE then
        if not (s and s.active) then return "nowhere" end
        Fossils.showFieldCase(self.game)
        return "repel_used"
      end
      return baseUseFieldItem(self,itemId)
    end
  end

  local evolutionCache=nil
  local function speciesBST(def)
    local n=0
    for _,v in pairs((def and def.baseStats) or {}) do n=n+(tonumber(v) or 0) end
    return n
  end

  local function evolutionInfo(game)
    if evolutionCache then return evolutionCache end
    local hasPrevo={}; local stage={}
    for id,def in pairs(game.data.pokemon or {}) do
      -- Neo Nursery compatibility: nursery-exclusive/custom developmental
      -- species must never influence Dungeon Delvers' generic evolution pool.
      if def.excludeFromGenericRandomSpecies~=true
        and def.neoNurseryExclusive~=true then
        for _,e in ipairs(def.evolutions or {}) do
          local target=e.species and game.data.pokemon[e.species]
          if target and target.excludeFromGenericRandomSpecies~=true
            and target.neoNurseryExclusive~=true then hasPrevo[e.species]=true end
        end
      end
    end
    local function calc(id,seen)
      if stage[id]~=nil then return stage[id] end
      seen=seen or {}; if seen[id] then return 0 end; seen[id]=true
      if not hasPrevo[id] then stage[id]=0; return 0 end
      local best=0
      for pid,pdef in pairs(game.data.pokemon or {}) do
        if pdef.excludeFromGenericRandomSpecies~=true
          and pdef.neoNurseryExclusive~=true then
          for _,e in ipairs(pdef.evolutions or {}) do
            if e.species==id then best=math.max(best,calc(pid,seen)+1) end
          end
        end
      end
      stage[id]=best; return best
    end
    for id,def in pairs(game.data.pokemon or {}) do
      if def.excludeFromGenericRandomSpecies~=true
        and def.neoNurseryExclusive~=true then calc(id,{}) end
    end
    evolutionCache={hasPrevo=hasPrevo,stage=stage}
    return evolutionCache
  end

  local function validDelveSpecies(game,id,def)
    if not (id and def and def.baseStats and def.name) then return false end
    -- Neo Nursery compatibility: keep nursery-only species out of rentals,
    -- roaming encounters, boss/depth pools, and all generic delve selection.
    if def.excludeFromGenericRandomSpecies==true
      or def.neoNurseryExclusive==true then return false end
    if LEGENDARY[id] or id=="EGG" or id=="MISSINGNO" then return false end
    -- True fossil species are museum restorations, not ordinary cave wildlife.
    if id=="OMANYTE" or id=="OMASTAR" or id=="KABUTO" or id=="KABUTOPS"
        or id=="AERODACTYL" then return false end
    return (tonumber(def.dex) or tonumber(def.index) or 1)>0
  end

  local function starterSpecies(game)
    local evo=evolutionInfo(game); local out={}
    for id,def in pairs(game.data.pokemon or {}) do
      if validDelveSpecies(game,id,def) and (evo.stage[id] or 0)==0
          and speciesBST(def)<=555 then out[#out+1]=id end
    end
    table.sort(out); return out
  end

  local function depthSpecies(game,depth)
    depth=math.max(1,tonumber(depth) or 1)
    local evo=evolutionInfo(game); local out={}
    -- Power now rises as the delve deepens instead of unlocking the entire dex
    -- at B10. Evolution stage is part of the score, so deeper strata naturally
    -- contain more evolved and higher-BST Pokemon.
    local ceiling=math.min(650,420+depth*6)
    local floorScore=math.min(490,165+depth*4)
    for id,def in pairs(game.data.pokemon or {}) do
      if validDelveSpecies(game,id,def) then
        local score=speciesBST(def)+(evo.stage[id] or 0)*35
        if score>=floorScore and score<=ceiling then out[#out+1]=id end
      end
    end
    if #out==0 then out=starterSpecies(game) end
    table.sort(out); return out
  end

  local function chooseSpeciesForDepth(game,depth,r)
    local pool=depthSpecies(game,depth)
    if #pool==0 then return "RATTATA" end
    return pool[r(#pool)]
  end

  local COVERAGE_MOVES={
    "BITE","MUD_SLAP","ROCK_THROW","ICY_WIND","SWIFT","CONFUSION",
    "EMBER","WATER_GUN","VINE_WHIP","THUNDERSHOCK","PURSUIT","PECK",
  }

  -- Generic Delve rentals/wilds/trainers must stay inside Crystal's native
  -- move roster.  Other mods are free to register moves globally, but those
  -- should only appear where the owning mod explicitly grants them.
  local DELVE_BANNED_MOVES={
    SONICBOOM=true,DRAGON_RAGE=true,SEISMIC_TOSS=true,NIGHT_SHADE=true,
    PSYWAVE=true,SUPER_FANG=true,
  }
  local function vanillaDelveMove(game,id)
    local md=game and game.data and game.data.moves and game.data.moves[id]
    if type(md)~="table" or DELVE_BANNED_MOVES[id] then return nil end
    local index=tonumber(md.index)
    if not index or index<1 or index>251 then return nil end
    if md.excludeFromGenericRandomMoves==true
        or md.excludeFromPokeSurviveRandomMoves==true
        or md.bfrCustomMachine==true then return nil end
    return md
  end

  local function curateDelveMoves(game,mon,level)
    if not mon then return end
    local def=game.data.pokemon and game.data.pokemon[mon.species]
    local moves=game.data.moves or {}; local candidates={}; local seen={}
    local function add(id)
      local md=vanillaDelveMove(game,id)
      if id and md and not seen[id] then
        seen[id]=true; candidates[#candidates+1]={id=id,power=tonumber(md.power) or 0,type=md.type}
      end
    end
    for _,m in ipairs(mon.moves or {}) do add(m.id) end
    for _,e in ipairs((def and def.levelMoves) or {}) do
      if (tonumber(e.level) or 1)<=math.max(22,(level or 10)+12) then add(e.move) end
    end
    local types={}; for _,t in ipairs((def and def.types) or {}) do types[t]=true end
    table.sort(candidates,function(a,b)
      local as=(a.power>0 and 100 or 0)+(types[a.type] and 25 or 0)+math.min(a.power,80)
      local bs=(b.power>0 and 100 or 0)+(types[b.type] and 25 or 0)+math.min(b.power,80)
      return as>bs
    end)
    local chosen={}; local chosenType={}
    local function pick(row)
      if not row or #chosen>=4 then return end
      for _,id in ipairs(chosen) do if id==row.id then return end end
      chosen[#chosen+1]=row.id; if row.type then chosenType[row.type]=true end
    end
    -- One reliable STAB attack first.
    for _,row in ipairs(candidates) do if row.power>0 and types[row.type] then pick(row); break end end
    -- Then explicitly seek damaging coverage so something like Rattata is not
    -- hard-walled by the first Ghost trainer it sees.
    for _,row in ipairs(candidates) do
      if row.power>0 and not chosenType[row.type] then pick(row); break end
    end
    local damaging=0; for _,id in ipairs(chosen) do if (moves[id] and (moves[id].power or 0)>0) then damaging=damaging+1 end end
    for _,id in ipairs(COVERAGE_MOVES) do
      if damaging>=2 then break end
      local md=vanillaDelveMove(game,id)
      if md and (tonumber(md.power) or 0)>0 and not chosenType[md.type] then
        pick({id=id,power=md.power,type=md.type}); damaging=damaging+1
      end
    end
    for _,row in ipairs(candidates) do if #chosen<4 then pick(row) end end
    if #chosen<2 then
      for _,id in ipairs(COVERAGE_MOVES) do
        local md=vanillaDelveMove(game,id)
        if md then pick({id=id,power=md.power,type=md.type}) end
        if #chosen>=2 then break end
      end
    end
    mon.moves={}
    for _,id in ipairs(chosen) do
      local md=vanillaDelveMove(game,id)
      if md then mon.moves[#mon.moves+1]={id=id,pp=md.pp or 5,maxPp=md.pp or 5} end
    end
  end

  -- The clerk's starting partner is the only true "rental". Keep banned
  -- fixed-damage/random-damage moves out of that rental even if it levels into
  -- one during the run, but never strip legitimate moves from Pokemon the
  -- player catches or recruits inside the delve. DEV23 sanitized the entire
  -- player party at every battle start, which is why a newly learned SEISMIC
  -- TOSS could appear and then mysteriously vanish.
  if not Mon.__pewterDungeonRentalGainExperience then
    Mon.__pewterDungeonRentalGainExperience=Mon.gainExperience
    Mon.gainExperience=function(mon,amount,data)
      local result=Mon.__pewterDungeonRentalGainExperience(mon,amount,data)
      if mon and mon._pewterDungeonRental and result and type(result.learned)=="table" then
        local kept={}
        for _,id in ipairs(result.learned) do
          if not DELVE_BANNED_MOVES[id] then kept[#kept+1]=id end
        end
        result.learned=kept
      end
      return result
    end
  end

  local function buildMon(game,species,level)
    level=clamp(math.floor(level or 10),2,100)
    local mon=Mon.new(game.data,species,level)
    if mon then curateDelveMoves(game,mon,level); healMon(mon); mod._ddRollTypes(game,mon) end
    return mon
  end

  local function floorSeed(s,depth)
    return ((tonumber(s.runSeed) or 12345)+(depth*104729))%2147483647
  end

  -- Floor generation needs the roaming monsters' levels before the later
  -- battle/swap UI section declares its local helpers.
  local function generatedWildLevel(depth,r)
    depth=math.max(1,math.floor(tonumber(depth) or 1))
    return clamp(8+depth+r(2)-1,8,100)
  end

  local function rrange(r,a,b)
    if b<=a then return a end
    return a+r(b-a+1)-1
  end

  -- Palette helpers -------------------------------------------------------------
  -- Build private hue-shifted cave environments at runtime.  We only duplicate
  -- palette pool rows that a source environment actually references, so the
  -- vanilla palette tables and other maps remain untouched.
  local dungeonPaletteCache={}

  local function rgbToHsv(c)
    local r,g,b=(c[1] or 0)/255,(c[2] or 0)/255,(c[3] or 0)/255
    local mx=math.max(r,g,b); local mn=math.min(r,g,b); local d=mx-mn
    local h=0
    if d~=0 then
      if mx==r then h=((g-b)/d)%6
      elseif mx==g then h=((b-r)/d)+2
      else h=((r-g)/d)+4 end
      h=h*60
    end
    local s=(mx==0) and 0 or d/mx
    return h,s,mx
  end

  local function hsvToRgb(h,s,v)
    h=(h%360)/60
    local c=v*s; local x=c*(1-math.abs((h%2)-1)); local m=v-c
    local r,g,b
    if h<1 then r,g,b=c,x,0
    elseif h<2 then r,g,b=x,c,0
    elseif h<3 then r,g,b=0,c,x
    elseif h<4 then r,g,b=0,x,c
    elseif h<5 then r,g,b=x,0,c
    else r,g,b=c,0,x end
    return {
      clamp(math.floor((r+m)*255+.5),0,255),
      clamp(math.floor((g+m)*255+.5),0,255),
      clamp(math.floor((b+m)*255+.5),0,255),
    }
  end

  local function hueShiftColor(c,degrees)
    local h,s,v=rgbToHsv(c or {0,0,0})
    -- Whites/greys stay neutral; only actual hue-bearing colors rotate.
    if s<.08 then return {c[1] or 0,c[2] or 0,c[3] or 0} end
    return hsvToRgb(h+(degrees or 0),s,v)
  end

  local function dungeonEnvironment(game,baseEnv,shift)
    shift=math.floor(tonumber(shift) or 0)
    if shift==0 then return baseEnv end
    local pals=game.data and game.data.gen2Palettes
    local envs=pals and pals.environments
    local base=envs and envs[baseEnv]
    if not (pals and pals.bg and base) then return baseEnv end
    local key=tostring(baseEnv)..":"..tostring(shift)
    if dungeonPaletteCache[key] then return dungeonPaletteCache[key] end

    local id="PD_CAVE_"..tostring(baseEnv).."_"..tostring(shift):gsub("-","N")
    if not envs[id] then
      local out={}; local remap={}
      for _,tod in ipairs({"MORN","DAY","NITE","DARK"}) do
        local src=base[tod] or base.DAY or base.MORN
        local row={}
        if src then
          for slot=1,8 do
            local old=src[slot]
            if old and not remap[old] then
              local oldPal=pals.bg[old]
              if oldPal then
                local shifted={}
                for i=1,4 do shifted[i]=hueShiftColor(oldPal[i],shift) end
                pals.bg[#pals.bg+1]=shifted
                remap[old]=#pals.bg
              end
            end
            row[slot]=remap[old] or old
          end
        end
        out[tod]=row
      end
      envs[id]=out
    end
    dungeonPaletteCache[key]=id
    return id
  end

  local function clearFloorCaches(world)
    if not world then return end
    for _,name in ipairs({"mapImages","animCells","bgSets"}) do
      local t=world[name]
      if type(t)=="table" then
        for k in pairs(t) do
          if tostring(k):find(FLOOR.."|",1,true)==1 then t[k]=nil end
        end
      end
    end
    -- PEWTER_DUNGEON_FLOOR is one reusable map id whose object list is rebuilt
    -- from scratch for every procedural floor. Gen2 World:pooledNpc keys NPCs
    -- by map id + object index, so reusing index 1 on B20 could resurrect the
    -- index-1 actor from B19 instead of constructing the threshold miner. That
    -- stale pooled actor was the real reason the B20 miner kept disappearing.
    -- Purge only this generated map's pool entries before the next setMap.
    if type(world.npcPool)=="table" then
      local prefix=FLOOR.."_obj_"
      for k in pairs(world.npcPool) do
        if tostring(k):sub(1,#prefix)==prefix then world.npcPool[k]=nil end
      end
    end
    -- DEV118: PEWTER_DUNGEON_FLOOR is also re-used as the *live* map id.
    -- A same-map B9 -> B10 transition can therefore leave old generated NPCs
    -- in World.npcs/World.entities even after the pool has been cleared. Those
    -- stale rows reuse indices 1..N and can either swallow a new attendant or
    -- stack underneath it. Purge only Dungeon Delvers-owned floor actors here;
    -- the co-op partner ghost has no OWNER marker and is intentionally kept.
    if type(world.npcs)=="table" then
      for i=#world.npcs,1,-1 do
        local npc=world.npcs[i]; local d=npc and npc.def
        if d and d.owner==OWNER and d.pewterRole then table.remove(world.npcs,i) end
      end
    end
    if type(world.entities)=="table" then
      for i=#world.entities,1,-1 do
        local npc=world.entities[i]; local d=npc and npc.def
        if d and d.owner==OWNER and d.pewterRole then table.remove(world.entities,i) end
      end
    end
  end

  -- Cave block harvesting -------------------------------------------------------
  local caveAnalysisCache={}
  local stairBlockCache={}

  -- DEV12: source-map warp lists are not a reliable way to discover a usable
  -- staircase graphic. Kanto caves can exit through COLL_CAVE even when their
  -- tileset contains a native staircase metatile. Scan the tileset itself for
  -- COLL_STAIRCASE cells so the generator can always use an obvious descent.
  -- Build a private cave tileset whose new final metatile is ordinary floor
  -- everywhere except ONE 16x16 collision cell, which uses the native stair
  -- quadrant's four 8x8 graphics tiles and collision. This avoids pasting an
  -- authored 2x2-cell stair block (and all of its surrounding platform art)
  -- into a generated room just to get one downstairs tile.
  local function singleCellStairTileset(baseTileset,openBlockId,stair)
    if not (baseTileset and baseTileset.blocks and baseTileset.collision
        and stair and stair.id~=nil) then return nil,nil end
    local open=baseTileset.blocks[(openBlockId or -1)+1]
    local stairBlock=baseTileset.blocks[(stair.id or -1)+1]
    local openColl=baseTileset.collision[(openBlockId or -1)+1]
    if not (open and stairBlock and openColl) then return nil,nil end

    local ts={}
    for k,v in pairs(baseTileset) do ts[k]=v end
    ts.blocks=deep(baseTileset.blocks)
    ts.collision=deep(baseTileset.collision)

    local block=deep(open)
    local coll=deep(openColl)
    local lx=clamp(math.floor(tonumber(stair.lx) or 0),0,1)
    local ly=clamp(math.floor(tonumber(stair.ly) or 0),0,1)
    -- A Gen-II metatile is 4x4 graphics tiles; each collision cell is a 2x2
    -- graphics-tile quadrant. Copy only that quadrant from the native stairs.
    for dy=0,1 do
      for dx=0,1 do
        local tx=lx*2+dx
        local ty=ly*2+dy
        local i=ty*4+tx+1
        block[i]=stairBlock[i]
      end
    end
    -- Use the source cell only for its graphic. The generated exit always
    -- behaves as a normal staircase cell; source cave-mouth/warp collision
    -- semantics are intentionally not imported.
    coll[ly*2+lx+1]=0x7a

    local newId=#ts.blocks
    if newId>255 then return nil,nil end
    ts.blocks[newId+1]=block
    ts.collision[newId+1]=coll
    return ts,newId
  end

  local function tilesetStairBlocks(tileset,tilesetId)
    local key=tilesetId or tostring(tileset)
    if stairBlockCache[key] then return stairBlockCache[key] end
    local strong,weak={},{}
    local collisions=(tileset and tileset.collision) or {}
    for id=0,math.max(0,#collisions-1) do
      local q=collisions[id+1]
      if q then
        local walkable=0; local bad=false
        for j=1,4 do
          local c=q[j]
          if Permissions.isWalkable(c) then walkable=walkable+1 end
          if (Permissions.ledgeFacings and Permissions.ledgeFacings(c))
              or (Permissions.currentDirection and Permissions.currentDirection(c)) then
            bad=true
          end
        end
        if not bad then
          for j=1,4 do
            local c=q[j]
            if c==0x7a or c==0x73 then
              local rec={
                id=id,lx=(j-1)%2,ly=math.floor((j-1)/2),
                coll=c,stair=true,walkable=walkable,
              }
              if c==0x7a then strong[#strong+1]=rec else weak[#weak+1]=rec end
            end
          end
        end
      end
    end
    local out=(#strong>0) and strong or weak
    table.sort(out,function(a,b) return (a.walkable or 0)>(b.walkable or 0) end)
    stairBlockCache[key]=out
    return out
  end

  local function blockWalkCount(tileset,id)
    local q=tileset and tileset.collision and tileset.collision[(id or -1)+1]
    if not q then return 0 end
    local n=0
    for i=1,4 do if Permissions.isWalkable(q[i]) then n=n+1 end end
    return n
  end

  local function plainOpenBlock(tileset,id)
    local q=tileset and tileset.collision and tileset.collision[(id or -1)+1]
    if not q then return false end
    for i=1,4 do
      local c=q[i]
      if not Permissions.isWalkable(c) then return false end
      if Permissions.ledgeFacings and Permissions.ledgeFacings(c) then return false end
      if Permissions.currentDirection and Permissions.currentDirection(c) then return false end
      if Permissions.doorForcedDirection and Permissions.doorForcedDirection(c) then return false end
      if Permissions.isWarpCollision and Permissions.isWarpCollision(c) then return false end
    end
    return true
  end

  local function plainSolidBlock(tileset,id)
    local q=tileset and tileset.collision and tileset.collision[(id or -1)+1]
    if not q then return false end
    for i=1,4 do
      local c=q[i]
      if Permissions.isWalkable(c) then return false end
      if Permissions.ledgeFacings and Permissions.ledgeFacings(c) then return false end
      if Permissions.currentDirection and Permissions.currentDirection(c) then return false end
      if Permissions.doorForcedDirection and Permissions.doorForcedDirection(c) then return false end
      if Permissions.isWarpCollision and Permissions.isWarpCollision(c) then return false end
    end
    return true
  end

  local CAVE_SOURCE_IDS={}
  for _,row in ipairs(CAVE_SOURCES) do CAVE_SOURCE_IDS[row.id]=true end
  for _,id in ipairs({
    "WILLS_ROOM","KOGAS_ROOM","BRUNOS_ROOM","KARENS_ROOM","LANCES_ROOM",
    "TEAM_ROCKET_BASE_B1F","TEAM_ROCKET_BASE_B2F","TEAM_ROCKET_BASE_B3F",
    "TIN_TOWER_1F","TIN_TOWER_2F","TIN_TOWER_3F","TIN_TOWER_4F","TIN_TOWER_5F",
    "TIN_TOWER_6F","TIN_TOWER_7F","TIN_TOWER_8F","TIN_TOWER_9F",
  }) do CAVE_SOURCE_IDS[id]=true end

  local function caveFloorRank(id)
    id=tostring(id or "")
    local b=id:match("_B(%d+)F$")
    if b then return -tonumber(b) end
    local f=id:match("_(%d+)F$")
    if f then return tonumber(f) end
    return nil
  end

  local function analyzeCaveSource(game,row)
    local key=row and row.id
    if not key then return nil end
    if caveAnalysisCache[key]~=nil then return caveAnalysisCache[key] or nil end
    local def=game.data.gen2Maps and game.data.gen2Maps[key]
    local tileset=def and game.data.gen2Tilesets and game.data.gen2Tilesets[def.tileset]
    if not (def and tileset and def.blocks and def.width and def.height) then
      caveAnalysisCache[key]=false; return nil
    end

    local counts,boundary={},{}
    for by=0,def.height-1 do
      for bx=0,def.width-1 do
        local id=def.blocks[by*def.width+bx+1]
        if id and id>0 then
          counts[id]=(counts[id] or 0)+1
          if bx==0 or by==0 or bx==def.width-1 or by==def.height-1 then
            boundary[id]=(boundary[id] or 0)+1
          end
        end
      end
    end

    local open,solid,solidFallback={},{},{}
    for id,n in pairs(counts) do
      local wc=blockWalkCount(tileset,id)
      if wc==4 and plainOpenBlock(tileset,id) then
        open[#open+1]={id=id,n=n}
      elseif wc==0 then
        local rec={id=id,n=n,b=boundary[id] or 0}
        solidFallback[#solidFallback+1]=rec
        if plainSolidBlock(tileset,id) then solid[#solid+1]=rec end
      end
    end
    if #solid==0 then solid=solidFallback end
    table.sort(open,function(a,b) return a.n>b.n end)
    table.sort(solid,function(a,b)
      if a.b~=b.b then return a.b>b.b end
      return a.n>b.n
    end)
    if #open==0 or #solid==0 then caveAnalysisCache[key]=false; return nil end

    local sourceMap=Map.new(def,tileset)
    local stairs={}
    for _,w in ipairs(def.warps or {}) do
      local x,y=tonumber(w.x),tonumber(w.y)
      if x and y and sourceMap:inBounds(x,y) then
        local bx,by=math.floor(x/2),math.floor(y/2)
        local id=def.blocks[by*def.width+bx+1]
        local coll=sourceMap:cellCollision(x,y)
        if id and id>0 and Permissions.isWarpCollision(coll)
            and Permissions.isWalkable(coll) then
          local srcRank,dstRank=caveFloorRank(key),caveFloorRank(w.destMap)
          local internal=CAVE_SOURCE_IDS[w.destMap]==true
          stairs[#stairs+1]={
            id=id,lx=x%2,ly=y%2,coll=coll,stair=(coll==0x7a),
            destMap=w.destMap,internal=internal,
            downstairs=internal and srcRank and dstRank and dstRank<srcRank or false,
            upstairs=internal and srcRank and dstRank and dstRank>srcRank or false,
          }
        end
      end
    end

    local out={
      id=key,label=row.label or key,def=def,tileset=tileset,tilesetId=def.tileset,
      open=open,solid=solid,stairs=stairs,
    }
    caveAnalysisCache[key]=out
    return out
  end

  local function allCaveSources(game)
    local out={}
    for _,row in ipairs(CAVE_SOURCES) do
      local a=analyzeCaveSource(game,row)
      if a then out[#out+1]=a end
    end
    return out
  end


  -- Crystal already contains a surprisingly broad set of overworld Pokemon
  -- sprites.  Use the specific one when available and fall back to a generic
  -- monster/bird/dragon silhouette for species that never had an overworld
  -- actor in vanilla.
  local OVERWORLD_MON_SPRITES={
    BULBASAUR="SPRITE_BULBASAUR",IVYSAUR="SPRITE_BULBASAUR",VENUSAUR="SPRITE_BULBASAUR",
    CHARMANDER="SPRITE_CHARMANDER",CHARMELEON="SPRITE_CHARMANDER",CHARIZARD="SPRITE_DRAGON",
    SQUIRTLE="SPRITE_SQUIRTLE",WARTORTLE="SPRITE_SQUIRTLE",BLASTOISE="SPRITE_MONSTER",
    CATERPIE="SPRITE_WEEDLE",METAPOD="SPRITE_WEEDLE",BUTTERFREE="SPRITE_BUTTERFREE",
    WEEDLE="SPRITE_WEEDLE",KAKUNA="SPRITE_WEEDLE",BEEDRILL="SPRITE_BUTTERFREE",
    PIDGEY="SPRITE_BIRD",PIDGEOTTO="SPRITE_BIRD",PIDGEOT="SPRITE_BIRD",
    SPEAROW="SPRITE_BIRD",FEAROW="SPRITE_BIRD",
    EKANS="SPRITE_EKANS",ARBOK="SPRITE_EKANS",
    PIKACHU="SPRITE_PIKACHU",RAICHU="SPRITE_PIKACHU",
    CLEFAIRY="SPRITE_CLEFAIRY",CLEFABLE="SPRITE_CLEFAIRY",
    JIGGLYPUFF="SPRITE_JIGGLYPUFF",WIGGLYTUFF="SPRITE_JIGGLYPUFF",
    ZUBAT="SPRITE_ZUBAT",GOLBAT="SPRITE_ZUBAT",CROBAT="SPRITE_ZUBAT",
    ODDISH="SPRITE_ODDISH",GLOOM="SPRITE_ODDISH",VILEPLUME="SPRITE_ODDISH",BELLOSSOM="SPRITE_ODDISH",
    PARAS="SPRITE_PARAS",PARASECT="SPRITE_PARAS",
    DIGLETT="SPRITE_DIGLETT",DUGTRIO="SPRITE_DIGLETT",
    MACHOP="SPRITE_MACHOP",MACHOKE="SPRITE_MACHOP",MACHAMP="SPRITE_MACHOP",
    GEODUDE="SPRITE_GEODUDE",GRAVELER="SPRITE_GEODUDE",GOLEM="SPRITE_GEODUDE",
    GRIMER="SPRITE_GRIMER",MUK="SPRITE_GRIMER",
    GASTLY="SPRITE_GENGAR",HAUNTER="SPRITE_GENGAR",GENGAR="SPRITE_GENGAR",
    VOLTORB="SPRITE_VOLTORB",ELECTRODE="SPRITE_VOLTORB",
    RHYHORN="SPRITE_RHYDON",RHYDON="SPRITE_RHYDON",
    MAGIKARP="SPRITE_MAGIKARP",GYARADOS="SPRITE_GYARADOS",
    LAPRAS="SPRITE_LAPRAS",SNORLAX="SPRITE_SNORLAX",
    SLOWPOKE="SPRITE_SLOWPOKE",SLOWBRO="SPRITE_SLOWPOKE",SLOWKING="SPRITE_SLOWPOKE",
    TAUROS="SPRITE_TAUROS",SUDOWOODO="SPRITE_SUDOWOODO",
    TOGEPI="SPRITE_TOGEPI",TOGETIC="SPRITE_TOGEPI",
    UNOWN="SPRITE_UNOWN",
    POLIWAG="SPRITE_POLIWAG",POLIWHIRL="SPRITE_POLIWAG",POLIWRATH="SPRITE_POLIWAG",POLITOED="SPRITE_POLIWAG",
    SHELLDER="SPRITE_SHELLDER",CLOYSTER="SPRITE_SHELLDER",
    TENTACOOL="SPRITE_TENTACOOL",TENTACRUEL="SPRITE_TENTACOOL",
  }
  local BIRDISH={
    HOOTHOOT=true,NOCTOWL=true,MURKROW=true,DELIBIRD=true,SKARMORY=true,
    DODUO=true,DODRIO=true,FARFETCH_D=true,
  }
  local DRAGONISH={
    DRATINI=true,DRAGONAIR=true,DRAGONITE=true,AERODACTYL=true,ONIX=true,STEELIX=true,
  }
  local function overworldSpriteForSpecies(species)
    return OVERWORLD_MON_SPRITES[species]
      or (BIRDISH[species] and "SPRITE_BIRD")
      or (DRAGONISH[species] and "SPRITE_DRAGON")
      or "SPRITE_MONSTER"
  end

  -- A $16 POKEMON object alternates frame 0 and frame 1. Crystal's true
  -- Pokemon/icon sheets are already authored as a two-frame idle, but the
  -- generic MONSTER/BIRD/DRAGON fallbacks are six-frame WALKING_SPRITE sheets:
  -- frame 0 is stand-down and frame 1 is stand-up. Using those raw with bounce
  -- makes the monster look like it is nodding vertically.
  --
  -- DEV24 builds a private two-frame idle from each walker's DOWN poses while
  -- pinning the bottom four pixel rows to the exact same stand-down artwork in
  -- both frames. The upper 12 pixels genuinely animate from stand-down to the
  -- walk-down pose, while the feet/ground contact can never move. This restores
  -- visible bird/monster idle motion without the old up/down bob or DEV23's
  -- nearly-invisible mirror trick. Native POKEMON_SPRITE rows stay untouched.
  -- Unique Menu Icons ships final 16x32 RGBA art. The party menu knows how
  -- to display that art, but SpriteRenderer treats overworld sheets as indexed
  -- Crystal OBJ graphics and keys their light shade to transparency. That is
  -- what produced the missing chunks in DEV64. Angler's Cove/Viridian solve
  -- this by drawing ICON_UNIQUE_* directly; Dungeon Delvers now does the same.
  local directIconCache={}
  local function directUniqueIcon(game,def)
    if not (def and def.pewterDirectIcon and def.pewterIconPath) then return nil end
    local species=def.pewterSpecies
    local key=tostring(def.pewterIconPath).."|"..tostring(species)
    local cached=directIconCache[key]
    if cached~=nil then return cached or nil end
    local okData,data=pcall(love.image.newImageData,def.pewterIconPath)
    if not (okData and data) then directIconCache[key]=false; return nil end
    local iw0,ih0=data:getDimensions()
    local grayscale=true
    for yy=0,ih0-1 do
      for xx=0,iw0-1 do
        local rr,gg,bb,aa=data:getPixel(xx,yy)
        if aa>0.01 and (math.abs(rr-gg)>0.01 or math.abs(rr-bb)>0.01) then
          grayscale=false; break
        end
      end
      if not grayscale then break end
    end
    -- UMI ORIGINAL mode is grayscale and normally receives its species OBJ
    -- palette from PartyMenu. Because roamers bypass PartyMenu, apply those
    -- two species colors here while preserving the PNG's real alpha.
    if grayscale then
      local colors=Palettes.monColors(game.data and game.data.gen2Palettes,species,false)
      if colors then
        local light=colors[2] or colors[1]
        local dark=colors[3] or colors[2] or colors[1]
        if light and dark then
          for yy=0,ih0-1 do
            for xx=0,iw0-1 do
              local rr,gg,bb,aa=data:getPixel(xx,yy)
              if aa>0.01 then
                local lum=(rr+gg+bb)/3
                if lum>0.80 then
                  data:setPixel(xx,yy,light[1]/255,light[2]/255,light[3]/255,aa)
                elseif lum>0.35 then
                  data:setPixel(xx,yy,dark[1]/255,dark[2]/255,dark[3]/255,aa)
                else
                  data:setPixel(xx,yy,0,0,0,aa)
                end
              end
            end
          end
        end
      end
    end
    local okImage,image=pcall(love.graphics.newImage,data)
    if not (okImage and image) then directIconCache[key]=false; return nil end
    image:setFilter("nearest","nearest")
    local iw,ih=image:getDimensions()
    local frames=math.max(1,math.min(2,math.floor(ih/16)))
    local out={image=image,frames=frames,full={},top={},bottom={}}
    for f=0,frames-1 do
      out.full[f]=love.graphics.newQuad(0,f*16,16,16,iw,ih)
      out.top[f]=love.graphics.newQuad(0,f*16,16,8,iw,ih)
      out.bottom[f]=love.graphics.newQuad(0,f*16+8,16,8,iw,ih)
    end
    directIconCache[key]=out
    return out
  end

  if not World.__pewterDungeonDirectIconState then
    local state={base=World.drawEntityComposite,draw=nil}
    World.__pewterDungeonDirectIconState=state
    function World:drawEntityComposite(entity,ox,oy,scale,drawSpriteFn,withExtras)
      if state.draw and state.draw(self,entity,ox,oy,scale,withExtras) then return end
      return state.base(self,entity,ox,oy,scale,drawSpriteFn,withExtras)
    end
  end
  World.__pewterDungeonDirectIconState.draw=function(world,entity,ox,oy,scale,withExtras)
    local def=entity and entity.spriteDef
    if not (world.map and world.map.id==FLOOR and def and def.pewterDirectIcon) then return false end
    local icon=directUniqueIcon(world.game,def)
    if not icon then return false end
    local function drawDirect(row,localOx,localOy,localScale)
      local G=love.graphics
      local lx=localOx or ox; local ly=localOy or oy; local ls=localScale or scale
      local frame=(entity.bounceFrame and entity:bounceFrame()) or 0
      frame=math.max(0,math.min(icon.frames-1,tonumber(frame) or 0))
      local quad=icon.full[frame]; local dy=0
      if row=="top" then quad=icon.top[frame]
      elseif row=="bottom" then quad=icon.bottom[frame]; dy=8 end
      G.push("all")
      G.translate(lx,ly); G.scale(ls,ls); G.setColor(1,1,1,1)
      -- Match SpriteRenderer's true-color bookkeeping so literal UMI colors
      -- are not recolored by a later palette pass.
      require("src.render.PaletteFX").markTrueColor(
        entity.px,entity.py+(entity.spriteYOffset or 0)-4+dy,16,row and 8 or 16)
      G.draw(icon.image,quad,entity.px,entity.py+(entity.spriteYOffset or 0)-4+dy)
      G.pop()
    end
    World.__pewterDungeonDirectIconState.base(world,entity,ox,oy,scale,drawDirect,withExtras)
    return true
  end

  local function delveRoamerSprite(game,species)
    local data=game and game.data
    local sprites=data and data.gen2Sprites
    -- Unique Menu Icons 1.5.0 registers species -> ICON_UNIQUE_* sheets in the
    -- native Gen-II icon registry. Reuse that exact sheet for dungeon roamers
    -- when present; otherwise retain Dungeon Delvers' vanilla sprite fallback.
    local icons=data and data.gen2Icons
    local iconId=icons and icons.species and icons.species[species]
    local iconEntry=iconId and tostring(iconId):match("^ICON_UNIQUE_")
      and icons.icons and icons.icons[iconId]
    if sprites and iconEntry and iconEntry.image then
      local uniqueId="SPRITE_PEWTER_UNIQUE_"..tostring(species)
      if not sprites[uniqueId] then
        sprites[uniqueId]={
          id=uniqueId,image=iconEntry.image,frames=2,walker=false,
          spriteType="POKEMON_SPRITE",palette="PAL_OW_RED",paletteId=0,
          species=species,icon=iconId,trueColor=true,
          pewterDirectIcon=true,pewterIconPath=iconEntry.image,pewterSpecies=species,
          source="MOD:pewter_dungeon_unique_menu_icons_direct:"..tostring(iconId),
        }
      else
        -- Hot reload / an older DEV save may already have the private sprite.
        -- Refresh the direct-draw metadata instead of keeping the DEV64 path.
        sprites[uniqueId].pewterDirectIcon=true
        sprites[uniqueId].pewterIconPath=iconEntry.image
        sprites[uniqueId].pewterSpecies=species
        sprites[uniqueId].trueColor=true
      end
      return uniqueId
    end
    local baseId=overworldSpriteForSpecies(species)
    local base=sprites and sprites[baseId]
    if not (sprites and base) then return baseId end

    if base.spriteType=="POKEMON_SPRITE" and (tonumber(base.frames) or 1)>=2 then
      return baseId
    end

    if base.image and (base.walker or base.spriteType=="WALKING_SPRITE") and (tonumber(base.frames) or 1)>=6 then
      local id="SPRITE_PEWTER_IDLE_"..tostring(baseId)
      if not sprites[id] then
        local function frameCells(topSourceRow)
          local out={}
          -- 8x4 chunks: two columns, four rows per 16x16 frame.
          -- stand-down begins at source chunk row 0; walk-down (frame 3) begins
          -- at source chunk row 12. Keep the final 4px row from stand-down.
          for row=0,2 do
            local src=(topSourceRow+row)*2
            out[#out+1]={tile=src,dx=0,dy=row*4}
            out[#out+1]={tile=src+1,dx=8,dy=row*4}
          end
          out[#out+1]={tile=6,dx=0,dy=12}
          out[#out+1]={tile=7,dx=8,dy=12}
          return out
        end
        sprites[id]={
          id=id,image=base.image,frames=2,walker=false,
          frameWidth=16,frameHeight=16,
          cells={frameCells(0),frameCells(12)},cellWidth=8,cellHeight=4,cellColumns=2,
          spriteType="POKEMON_SPRITE",
          palette=base.palette,paletteId=base.paletteId,trueColor=base.trueColor,
          source="MOD:pewter_dungeon_grounded_idle:"..tostring(baseId),
        }
      end
      return id
    end

    return baseId
  end

  local function reachableCells(map,start)
    if not (map and start and map:isWalkableCell(start.x,start.y)) then return {} end
    local seen={}; local q={{start.x,start.y}}; local head=1; local out={}
    seen[start.y*1024+start.x]=true
    while head<=#q do
      local c=q[head]; head=head+1
      out[#out+1]=c
      for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
        local nx,ny=c[1]+d[1],c[2]+d[2]; local k=ny*1024+nx
        if not seen[k] and map:inBounds(nx,ny)
            and map:isWalkableCell(nx,ny) and not map:isWaterCell(nx,ny) then
          seen[k]=true; q[#q+1]={nx,ny}
        end
      end
    end
    return out,seen
  end

  local function generateFloor(game,depth)
    local s=pdSave(game)
    -- Same-map dungeon depths replace the whole generated object table. Remove
    -- the runtime co-op ghost first so its index can never be recycled into a
    -- B10 attendant (the Scientist was the most visible victim).
    if SPECIAL.COOP and SPECIAL.COOP.beforeFloorRebuild then
      pcall(SPECIAL.COOP.beforeFloorRebuild,game)
    end
    depth=math.max(1,math.floor(depth or 1))
    local r=rng(floorSeed(s,depth))
    local constructed=(depth>=21)
    local thresholdVisual=(depth==20 or depth==40 or depth==60)
    local sources={}
    if thresholdVisual then
      -- Threshold chambers need an unmistakable authored ladder-up tile. Use
      -- the cave family here even at B40/B60 so we can source a genuine upward
      -- inter-floor warp graphic instead of guessing from another tileset.
      sources=allCaveSources(game)
    elseif depth>=41 then
      -- B41-B60 use Tin/Bell Tower's ancient interior family.
      for _,row in ipairs({
        {id="TIN_TOWER_2F",label="BURIED SANCTUM"},
        {id="TIN_TOWER_3F",label="BURIED SANCTUM"},
        {id="TIN_TOWER_4F",label="BURIED SANCTUM"},
        {id="TIN_TOWER_5F",label="BURIED SANCTUM"},
        {id="TIN_TOWER_6F",label="BURIED SANCTUM"},
        {id="TIN_TOWER_7F",label="BURIED SANCTUM"},
        {id="TIN_TOWER_8F",label="BURIED SANCTUM"},
        {id="TIN_TOWER_9F",label="BURIED SANCTUM"},
      }) do
        local a=analyzeCaveSource(game,row)
        if a then sources[#sources+1]=a end
      end
    elseif constructed then
      -- B21-B40 deliberately pin to Karen's Elite Four room instead of
      -- randomly selecting among all five chambers.  The rooms share a
      -- tileset but use different palettes/block mixes; random selection let
      -- a green open block + busy wall block leak into Buried Works. Karen's
      -- room is the dark masonry look that matched the approved DEV79 test.
      local a=analyzeCaveSource(game,{id="KARENS_ROOM",label="BURIED WORKS"})
      if a then sources[#sources+1]=a end
      if #sources==0 then
        for _,row in ipairs({
          {id="WILLS_ROOM",label="BURIED WORKS"},
          {id="BRUNOS_ROOM",label="BURIED WORKS"},
          {id="KOGAS_ROOM",label="BURIED WORKS"},
          {id="LANCES_ROOM",label="BURIED WORKS"},
        }) do
          local fallback=analyzeCaveSource(game,row)
          if fallback then sources[#sources+1]=fallback; break end
        end
      end
    else
      sources=allCaveSources(game)
    end
    -- If the tower family is absent, fall back to the proven Elite Four
    -- constructed family before ever dropping all the way back to caves.
    if #sources==0 and depth>=41 and not thresholdVisual then
      for _,row in ipairs({
        {id="BRUNOS_ROOM",label="BURIED WORKS"},
        {id="KARENS_ROOM",label="BURIED WORKS"},
        {id="WILLS_ROOM",label="BURIED WORKS"},
        {id="KOGAS_ROOM",label="BURIED WORKS"},
        {id="LANCES_ROOM",label="BURIED WORKS"},
      }) do
        local a=analyzeCaveSource(game,row)
        if a then sources[#sources+1]=a end
      end
    end
    -- Never strand an existing save if an unusual cache exposes neither
    -- constructed family. Fall back to the proven cave source pool.
    if #sources==0 and constructed then sources=allCaveSources(game); constructed=false end
    if #sources==0 then return nil,"no compatible dungeon sources" end

    -- DEV13 prefers staircase BLOCKS that are actually used by native cave
    -- warp events.  Scanning for any block containing COLL_STAIRCASE proved
    -- too permissive: some otherwise-valid blocks have a staircase collision
    -- in one quadrant but visually look like ledges/platform trim.  An authored
    -- warp block gives us the real cave ladder/stair graphic.  The raw tileset
    -- scan remains only as a last-resort compatibility fallback.
    local groupsByTileset={}
    for _,a in ipairs(sources) do
      local g=groupsByTileset[a.tilesetId]
      if not g then
        g={
          tilesetId=a.tilesetId,sources={},stairs={},internalStairs={},downStairs={},upStairs={},stairSeen={},
          fallbackStairs=tilesetStairBlocks(a.tileset,a.tilesetId),
        }
        groupsByTileset[a.tilesetId]=g
      end
      g.sources[#g.sources+1]=a
      for _,st in ipairs(a.stairs or {}) do
        local key=tostring(st.id)..":"..tostring(st.lx)..":"..tostring(st.ly)
          ..":"..tostring(st.destMap or "")
        if not g.stairSeen[key] then
          g.stairSeen[key]=true
          if st.downstairs then
            g.downStairs[#g.downStairs+1]=deep(st)
          elseif st.upstairs then
            g.upStairs[#g.upStairs+1]=deep(st)
            g.internalStairs[#g.internalStairs+1]=deep(st)
          elseif st.internal then
            g.internalStairs[#g.internalStairs+1]=deep(st)
          elseif st.stair then
            g.stairs[#g.stairs+1]=deep(st)
          end
        end
      end
    end
    local eligibleGroups,preferredGroups={},{}
    local groupKeys={}
    for key in pairs(groupsByTileset) do groupKeys[#groupKeys+1]=key end
    table.sort(groupKeys,function(a,b) return tostring(a)<tostring(b) end)
    for _,key in ipairs(groupKeys) do
      local g=groupsByTileset[key]
      table.sort(g.sources,function(a,b) return tostring(a.id or a.label)<tostring(b.id or b.label) end)
      -- Prefer an actual authored warp that DESCENDS to another floor in the
      -- same cave. Those cells are the compact one-tile ladder/downstairs art
      -- the user expects. Internal cave warps come next; a raw collision scan
      -- is only a last resort.
      if #(g.downStairs or {})>0 then
        g.stairs=g.downStairs
      elseif #(g.internalStairs or {})>0 then
        g.stairs=g.internalStairs
      elseif #(g.stairs or {})==0 then
        g.stairs=g.fallbackStairs or {}
      end
      if #(g.stairs or {})>0 then
        eligibleGroups[#eligibleGroups+1]=g
        for _,a in ipairs(g.sources) do
          if a.label=="ROCK TUNNEL" or a.label=="VICTORY ROAD" then
            preferredGroups[#preferredGroups+1]=g; break
          end
        end
      end
    end
    if #eligibleGroups==0 then return nil,"no cave tileset exposes a staircase block" end
    local group
    if thresholdVisual then
      local upGroups={}
      for _,g in ipairs(eligibleGroups) do
        if #(g.upStairs or {})>0 then upGroups[#upGroups+1]=g end
      end
      if #upGroups>0 then group=upGroups[r(#upGroups)] end
    end
    group=group or ((#preferredGroups>0 and preferredGroups[r(#preferredGroups)]) or eligibleGroups[r(#eligibleGroups)])
    local compatible=group.sources
    local preferred={}
    for _,a in ipairs(compatible) do
      if a.label=="ROCK TUNNEL" or a.label=="VICTORY ROAD" then preferred[#preferred+1]=a end
    end
    local source=(#preferred>0 and preferred[r(#preferred)]) or compatible[r(#compatible)]

    -- Twenty-floor thresholds now behave like actual gates. The first time a
    -- player reaches B20/B40 without the matching permanent unlock, there is
    -- no ladder: a miner closes the expedition and sends the haul upstairs.
    -- Bringing the RP-bought key on a later run consumes it and permanently
    -- turns that threshold into an ordinary rest stop with a deeper ladder.
    local checkpoint=(depth%20==10)
    local thresholdDepth=(depth==20 or depth==40)
    local thresholdUnlocked=(depth==20 and s.worksUnlocked==true)
      or (depth==40 and s.megalithUnlocked==true) or false
    local lockedThreshold=thresholdDepth and not thresholdUnlocked
    local terminalFloor=(depth==60)
    local campFloor=checkpoint or thresholdUnlocked or lockedThreshold or terminalFloor
    local bossFloor=(depth%10==9)
    local majorBoss=bossFloor and (depth%20==19)
    local specialRoom=campFloor or bossFloor
    -- Rest stops and guardian floors are compact, authored-feeling chambers.
    -- Ordinary floors keep the larger procedural graph.
    local width=specialRoom and 7 or rrange(r,20,26)
    local height=specialRoom and 6 or rrange(r,16,21)
    local wallId=source.solid[1].id
    local corridorId=source.open[1].id
    -- Curate the constructed strata instead of trusting the generic block
    -- frequency heuristic.  B21-B40 use the same Elite Four blocks seen in the
    -- good DEV79 Buried Works: black/empty surround + masonry floor.  Runtime
    -- collision validation keeps this safe if a cache ever differs.
    local sourceTilesetName=source.def and source.def.tileset
    if depth>=21 and depth<=40 and not thresholdVisual then
      if plainOpenBlock(source.tileset,45) then corridorId=45 end
      if plainSolidBlock(source.tileset,23) then wallId=23 end
    elseif depth>=41 and not thresholdVisual and sourceTilesetName=="TILESET_TOWER" then
      if plainOpenBlock(source.tileset,9) then corridorId=9 end
      if plainSolidBlock(source.tileset,42) then wallId=42 end
    end
    local blocks={}
    for i=1,width*height do blocks[i]=wallId end

    local function blockAt(bx,by) return by*width+bx+1 end
    local function carve(bx,by,id)
      if bx>=1 and by>=1 and bx<width-1 and by<height-1 then
        blocks[blockAt(bx,by)]=id or corridorId
      end
    end

    local rooms={}
    local want=rrange(r,11,16)
    local function overlaps(x,y,w,h)
      for _,room in ipairs(rooms) do
        if x<=room.x+room.w and x+w>=room.x-1
            and y<=room.y+room.h and y+h>=room.y-1 then return true end
      end
      return false
    end
    if specialRoom then
      local room={x=1,y=1,w=width-2,h=height-2,floorId=corridorId}
      rooms[1]=room
      for by=room.y,room.y+room.h-1 do
        for bx=room.x,room.x+room.w-1 do carve(bx,by,corridorId) end
      end
    else
      for _=1,520 do
        if #rooms>=want then break end
        local rw=rrange(r,2,5); local rh=rrange(r,2,4)
        local maxX=width-rw-2; local maxY=height-rh-2
        if maxX>=1 and maxY>=1 then
          local x=rrange(r,1,maxX); local y=rrange(r,1,maxY)
          if not overlaps(x,y,rw,rh) then
            -- Use the same clean all-walkable cave-floor block throughout rooms.
            -- Alternate "open" blocks can contain decorative cliff/ledge art even
            -- when their collisions are permissive, which looked like purposeless
            -- ledges in earlier DEV floors.
            local floorId=corridorId
            local room={x=x,y=y,w=rw,h=rh,floorId=floorId}
            rooms[#rooms+1]=room
            for by=y,y+rh-1 do for bx=x,x+rw-1 do carve(bx,by,floorId) end end
          end
        end
      end
    end

    -- Guaranteed fallback shape if random packing was unusually unlucky.
    if not specialRoom and #rooms<7 then
      rooms={
        {x=1,y=1,w=4,h=3,floorId=corridorId},
        {x=math.floor(width/2)-2,y=1,w=4,h=3,floorId=corridorId},
        {x=width-5,y=1,w=4,h=3,floorId=corridorId},
        {x=1,y=math.floor(height/2)-1,w=4,h=3,floorId=corridorId},
        {x=width-5,y=math.floor(height/2)-1,w=4,h=3,floorId=corridorId},
        {x=1,y=height-4,w=4,h=3,floorId=corridorId},
        {x=math.floor(width/2)-2,y=height-4,w=4,h=3,floorId=corridorId},
        {x=width-5,y=height-4,w=4,h=3,floorId=corridorId},
      }
      for i=1,width*height do blocks[i]=wallId end
      for _,room in ipairs(rooms) do
        for by=room.y,room.y+room.h-1 do
          for bx=room.x,room.x+room.w-1 do carve(bx,by,room.floorId) end
        end
      end
    end

    local function center(room)
      return math.floor(room.x+(room.w-1)/2),math.floor(room.y+(room.h-1)/2)
    end
    local function carveLine(x1,y1,x2,y2)
      local x,y=x1,y1; carve(x,y,corridorId)
      if r(2)==1 then
        while x~=x2 do x=x+(x2>x and 1 or -1); carve(x,y,corridorId) end
        while y~=y2 do y=y+(y2>y and 1 or -1); carve(x,y,corridorId) end
      else
        while y~=y2 do y=y+(y2>y and 1 or -1); carve(x,y,corridorId) end
        while x~=x2 do x=x+(x2>x and 1 or -1); carve(x,y,corridorId) end
      end
    end
    local function link(a,b)
      local ax,ay=center(a); local bx,by=center(b)
      carveLine(ax,ay,bx,by)
    end

    local layoutKinds={"CHAIN","HUB","RING","BRANCH","SNAKE","DOUBLE_HUB"}
    local layout=campFloor and "REST STOP" or (bossFloor and "GUARDIAN" or layoutKinds[r(#layoutKinds)])
    local modifier
    if checkpoint or thresholdUnlocked then
      modifier={id="REST",label="REST STOP",desc="A safe camp between dangerous floors."}
      -- One open room: no procedural corridors, enemies, traps or hidden encounters.
    elseif lockedThreshold then
      modifier={id="THRESHOLD",label="DELVE COMPLETE",desc="A sealed route marks the end of this expedition."}
    elseif terminalFloor then
      modifier={id="TERMINUS",label="DEEP TERMINUS",desc="The current expedition ends here."}
    elseif bossFloor then
      modifier={id="BOSS",label="GUARDIAN FLOOR",desc="Defeat the guardian to uncover the ladder."}
    elseif layout=="CHAIN" then
      table.sort(rooms,function(a,b)
        local ac=a.x+a.w/2; local bc=b.x+b.w/2
        if ac~=bc then return ac<bc end
        return a.y<b.y
      end)
      for i=1,#rooms-1 do link(rooms[i],rooms[i+1]) end
    elseif layout=="HUB" then
      local best,bestDist=1,math.huge
      for i,room in ipairs(rooms) do
        local x,y=center(room)
        local d=math.abs(x-width/2)+math.abs(y-height/2)
        if d<bestDist then best,bestDist=i,d end
      end
      for i=1,#rooms do if i~=best then link(rooms[best],rooms[i]) end end
    elseif layout=="RING" then
      table.sort(rooms,function(a,b)
        local ax,ay=center(a); local bx,by=center(b)
        return math.atan2(ay-height/2,ax-width/2)<math.atan2(by-height/2,bx-width/2)
      end)
      for i=1,#rooms do link(rooms[i],rooms[(i%#rooms)+1]) end
    elseif layout=="BRANCH" then
      for i=2,#rooms do link(rooms[i],rooms[r(i-1)]) end
      if #rooms>=5 then link(rooms[1],rooms[#rooms]) end
    elseif layout=="SNAKE" then
      table.sort(rooms,function(a,b)
        if a.y~=b.y then return a.y<b.y end
        local leftToRight=(math.floor(a.y/3)%2==0)
        if leftToRight then return a.x<b.x end
        return a.x>b.x
      end)
      for i=1,#rooms-1 do link(rooms[i],rooms[i+1]) end
    else -- DOUBLE_HUB
      local a=rooms[1]; local b=rooms[#rooms]; link(a,b)
      for i=2,#rooms-1 do if i%2==0 then link(a,rooms[i]) else link(b,rooms[i]) end end
    end
    local specialFeature=nil
    if not specialRoom then
      local featureChance=.20+(constructed and .08 or 0)
      local forcedFeature=s.forceSpecialFeature
      s.forceSpecialFeature=nil
      if forcedFeature=="FOSSIL_CHAMBER" then
        specialFeature={id="FOSSIL_CHAMBER",label="FOSSIL CHAMBER",desc="Several fossil-bearing rocks are exposed on this floor.",extraMonsters=-2,extraTrainers=-1,extraTraps=-2}
        modifier=deep(specialFeature)
      elseif constructed and depth==21 then
        modifier={id="NEW_STRATUM",label="NEW STRATUM",desc="Natural cave gives way to fitted stone and forgotten machinery."}
      elseif depth>=3 and r(10000)<=math.floor(featureChance*10000) then
        local featurePool={
          {id="WARP_MATRIX",label="WARP MATRIX",desc="Linked floor panels can throw you across the floor."},
          {id="SEALED_GATE",label="SEALED GATE",desc="A key mechanism on this floor controls the route to the ladder."},
          {id="HAZARD_GRID",label="HAZARD FLOOR",desc="Hidden floor traps can burn or poison a partner when stepped on."},
          {id="FOSSIL_CHAMBER",label="FOSSIL CHAMBER",desc="Several fossil-bearing rocks are exposed on this floor.",extraMonsters=-2,extraTrainers=-1,extraTraps=-2},
        }
        specialFeature=deep(featurePool[r(#featurePool)])
        modifier=deep(specialFeature)
      elseif r(10000)<=math.floor(FLOOR_EFFECT_CHANCE*10000) then
        modifier=deep(MODIFIERS[r(#MODIFIERS)])
      else
        modifier={id="NORMAL",label="STABLE"}
      end
    end

    -- Pick start/exit rooms by maximum separation rather than array order.
    local first,last=rooms[1],rooms[#rooms]
    local far=-1
    for i=1,#rooms do
      local ax,ay=center(rooms[i])
      for j=i+1,#rooms do
        local bx,by=center(rooms[j])
        local d=math.abs(ax-bx)+math.abs(ay-by)
        if d>far then far=d; first=rooms[i]; last=rooms[j] end
      end
    end

    local tone
    if constructed then
      local bands={
        {label="BURIED WORKS",shift=10},
        {label="ANCIENT HALLS",shift=34},
        {label="BURIED SANCTUM",shift=0},
        {label="LOWER SANCTUM",shift=0},
      }
      tone=bands[math.min(math.floor((depth-21)/10)+1,#bands)]
    else
      tone=HUE_BANDS[math.min(math.floor((depth-1)/5)+1,#HUE_BANDS)]
    end
    local def=deep(source.def)
    def.id=FLOOR; def.label=tone.label.." B"..tostring(depth); def.name=tone.label
    def.index=1191; def.landmark=PEWTER_LANDMARK; def.connections={}
    def.width=width; def.height=height; def.blocks=blocks; def.borderBlock=wallId
    def.objects={}; def.bgEvents={}; def.coordEvents={}; def.sceneScripts={}; def.callbacks={}
    def.warps={}
    def.environment=dungeonEnvironment(game,source.def.environment,tone.shift)
    def.palette="PALETTE_DAY"

    local sbx,sby=center(first); local dbx,dby=center(last)
    if specialRoom then
      -- Enter at the bottom-center of the compact room and put the downstairs
      -- target in the room's center. DEV23 placed both on opposite horizontal
      -- edges, which made the checkpoint feel like another full-size floor.
      sbx=math.floor(first.x+(first.w-1)/2)
      sby=first.y+first.h-1
      dbx=math.floor(first.x+(first.w-1)/2)
      dby=math.floor(first.y+(first.h-1)/2)
    end
    local start={x=sbx*2+1,y=sby*2+1}
    local descent=nil

    -- Build exits only from staircase/ladder cells that Crystal actually uses
    -- for authored floor-to-floor warps. DEV86 tried to infer a staircase from
    -- generic COLL_STAIRCASE blocks; that produced a platform-looking metatile
    -- instead of visible stairs on B20. Thresholds now use the exact authored
    -- downward-warp graphic from the source map, same as a real cave descent.
    local stairChoices={}
    local stairSource=(lockedThreshold or terminalFloor) and (group.upStairs or {}) or group.stairs
    for _,st in ipairs(stairSource or {}) do stairChoices[#stairChoices+1]=st end
    if #stairChoices==0 then
      for _,st in ipairs(group.stairs or {}) do stairChoices[#stairChoices+1]=st end
    end
    for i=#stairChoices,2,-1 do local j=r(i); stairChoices[i],stairChoices[j]=stairChoices[j],stairChoices[i] end
    local exitBlocks={}
    for by=last.y,last.y+last.h-1 do
      for bx=last.x,last.x+last.w-1 do
        exitBlocks[#exitBlocks+1]={x=bx,y=by,d=math.abs(bx-dbx)+math.abs(by-dby)}
      end
    end
    table.sort(exitBlocks,function(a,b) return a.d<b.d end)
    local map,cells,seen,chosenTileset,chosenTilesetId
    local wantFullStairs=(lockedThreshold or terminalFloor)
    for _,pos in ipairs(exitBlocks) do
      for _,st in ipairs(stairChoices) do
        local bi=blockAt(pos.x,pos.y); local original=def.blocks[bi]
        local stairTileset,stairBlockId
        if wantFullStairs then
          -- Keep the authored warp cell itself, but transplant only its 16x16
          -- staircase quadrant into otherwise ordinary floor. This is the
          -- actual graphic used by a real inter-floor warp, without importing
          -- an unrelated 32x32 platform or wall around it.
          stairTileset,stairBlockId=singleCellStairTileset(source.tileset,corridorId,st)
        else
          stairTileset,stairBlockId=singleCellStairTileset(source.tileset,corridorId,st)
        end
        if stairTileset and stairBlockId~=nil then
          def.blocks[bi]=stairBlockId
          local candidate=Map.new(def,stairTileset)
          local cc,ss=reachableCells(candidate,start)
          local dx,dy=pos.x*2+st.lx,pos.y*2+st.ly
          if #cc>=24 and ss[dy*1024+dx] then
            dbx,dby=pos.x,pos.y
            map,cells,seen=candidate,cc,ss
            descent={x=dx,y=dy,marker=false,block=stairBlockId}
            chosenTileset=stairTileset
            -- PEWTER_DUNGEON_FLOOR reuses one map id across every depth. Using
            -- one shared custom tileset id let the renderer keep B20's cave
            -- graphics cached when B21 rebuilt the map with Elite Four blocks.
            -- Give every generated depth its own tileset id so same-map floor
            -- transitions cannot inherit the previous stratum's tile graphics.
            chosenTilesetId="PD_DUNGEON_TILESET_B"..tostring(depth)
            def.tileset=chosenTilesetId
            break
          end
          def.blocks[bi]=original
        end
      end
      if descent then break end
    end
    if not descent then return nil,"could not place the downstairs tile in the exit room" end
    -- B20/B40/B60 use the generated native stair cell as the threshold exit.
    -- Earlier DEV builds tried to put a one-off miner in these same-map rooms,
    -- but the procedural map reuses one map id and the engine repeatedly lost
    -- that actor. A stepped stair is deterministic and uses the same event path
    -- that already works for every ordinary descent.
    if lockedThreshold or terminalFloor then
      descent.thresholdExit=true
      descent.locked=true
      descent.hidden=false
    end
    if chosenTilesetId then
      game.data.gen2Tilesets[chosenTilesetId]=chosenTileset
      -- World keeps its own tileset lookup in some engine builds. Keep it in
      -- sync explicitly so a FLOOR->FLOOR transition sees the new stratum art
      -- immediately instead of an older cached tileset table.
      if game.world and type(game.world.tilesets)=="table" then
        game.world.tilesets[chosenTilesetId]=chosenTileset
      end
    end

    -- Checkpoints do not decay; regular floors retain their exploration budget.
    local baseStability=clamp(math.floor(width*height*3.1+100),1000,1550)
    local stability=specialRoom and 9999 or math.floor(baseStability*(modifier.stability or 1))

    local used={}
    local function reserve(x,y) used[y*1024+x]=true end
    reserve(start.x,start.y); reserve(descent.x,descent.y)
    local function openDegree(x,y)
      local n=0
      for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
        if seen[(y+d[2])*1024+(x+d[1])] then n=n+1 end
      end
      return n
    end
    local function takeCell(minDist,preferOpen)
      minDist=minDist or 2
      for _=1,500 do
        local c=cells[r(#cells)]; local x,y=c[1],c[2]; local k=y*1024+x
        if not used[k] and (not preferOpen or openDegree(x,y)>=3)
            and math.abs(x-start.x)+math.abs(y-start.y)>=minDist
            and math.abs(x-descent.x)+math.abs(y-descent.y)>=2 then
          reserve(x,y); return x,y
        end
      end
      for _,c in ipairs(cells) do
        local k=c[2]*1024+c[1]
        if not used[k] and (not preferOpen or openDegree(c[1],c[2])>=2) then
          reserve(c[1],c[2]); return c[1],c[2]
        end
      end
    end

    local entities={}; local index=0
    local function addRole(role,sprite,x,y,extra)
      if not x then return nil end
      index=index+1
      local obj={
        index=index,sprite=sprite,x=x,y=y,
        movement=(role=="monster" and 0x16
          or ((role=="shelf" or role=="loot" or role=="fossil" or role=="floor_key" or role=="gate") and "STAY" or 3)),
        radius={x=0,y=0},hours={-1,-1},
        palette=0,type=0,sight=(role=="trainer" and 4 or 0),
        text="TEXT_PEWTER_DUNGEON_DYNAMIC",
        runtime=true,owner=OWNER,pewterRole=role,
      }
      -- Legacy threshold miners were virtual actors. PEWTER_DUNGEON_FLOOR
      -- reuses one map id for every generated depth, and repeated B19->B20 same-
      -- map reloads proved unreliable for one freshly-authored object row. Keep
      -- every normal actor in def.objects, but render/block/interact with the
      -- threshold miner directly from floorState so it cannot disappear.
      if role~="threshold_miner" then def.objects[#def.objects+1]=obj end
      local e={role=role,x=x,y=y,index=index,active=true,obj=obj,
        virtual=(role=="threshold_miner") or nil}
      if extra then for k,v in pairs(extra) do e[k]=v end end
      entities[#entities+1]=e
      return e
    end

    local function tmPool()
      local out={}
      for id,d in pairs(game.data.items or {}) do
        if type(d)=="table" and type(d.machine)=="table" and d.machine.kind=="TM" then
          local moveId=d.machine.move or d.machine.moveId or d.move
          -- Vanilla item data does not always expose the taught move through
          -- the same field.  When it does, reject mod-exclusive moves here too.
          if not moveId or vanillaDelveMove(game,moveId) then out[#out+1]=id end
        end
      end
      table.sort(out); return out
    end
    local availableTms=tmPool()
    local function rollLootId()
      local n=r(1000)
      if n<=135 then return "POTION"
      elseif n<=195 then return "SUPER_POTION"
      elseif n<=250 then return ITEM_DELVE_BALL
      -- Poison is the most dangerous field status in a step-based dungeon, so
      -- ANTIDOTE gets a modest weight edge over the other single-status cures.
      elseif n<=315 then return "ANTIDOTE"
      elseif n<=350 then return "PARLYZ_HEAL"
      elseif n<=385 then return "AWAKENING"
      elseif n<=430 then return "FULL_HEAL"
      elseif n<=515 then return "BERRY"
      elseif n<=537 then return "GOLD_BERRY"
      elseif n<=592 then return "FRESH_WATER"
      elseif n<=617 then return "SODA_POP"
      elseif n<=639 then return "LEMONADE"
      elseif n<=699 then return "ETHER"
      elseif n<=731 then return "MAX_ETHER"
      elseif n<=758 then return "ELIXER"
      elseif n<=785 then return "RARE_CANDY"
      elseif n<=820 and #availableTms>0 then return availableTms[r(#availableTms)]
      elseif n<=845 then return "X_ATTACK"
      elseif n<=870 then return "X_DEFEND"
      elseif n<=895 then return "X_SPEED"
      elseif n<=915 then return "X_SPECIAL"
      elseif n<=929 then return SPECIAL.ESCAPE_LENS
      elseif n<=940 then return SPECIAL.FOSSIL_SCANR
      elseif n<=951 then return SPECIAL.TRAP_SCANR
      elseif n<=961 then return GEAR_BOOTS
      elseif n<=971 then return GEAR_TRAP_WARD
      elseif n<=980 then return GEAR_PP_CHARM
      elseif n<=988 then return GEAR_ROPE
      elseif n<=995 then return GEAR_CHARM
      else return SPECIAL.ESCAPE_HATCH end
    end

    -- Custom floor loot uses the familiar ball sprite but controls its own
    -- vanilla-style two-page pickup copy, avoiding the old "Igame.world:showText("FLOOR EFFECT:\n"..tostring(floorState.modifier.label or "UNKNOWN"))OTION" text.
    local function addLoot(x,y)
      addRole("loot","SPRITE_POKE_BALL",x,y,{item=rollLootId()})
    end

    -- Occasional expedition props now use ONLY real Crystal object sprites.
    -- SPRITE_POKEDEX reads as old field equipment/terminal and SPRITE_PAPER as
    -- loose notes.  No custom furniture art is registered or drawn.
    local shelfNotes={
      "Dusty field notes.\nThe ink is faded.",
      "Old depth marks.\nB23 is circled.",
      "A cracked ledger.\nMost names stop here.",
      "A fossil sketch.\nIt is not a known one.",
      "A warning reads:\nDON'T RUSH STAIRS.",
    }
    local trainerSpriteCandidates={
      "SPRITE_YOUNGSTER","SPRITE_LASS","SPRITE_BUG_CATCHER","SPRITE_FISHER",
      "SPRITE_SUPER_NERD","SPRITE_HIKER","SPRITE_COOLTRAINER_M","SPRITE_COOLTRAINER_F",
      "SPRITE_POKEFAN_M","SPRITE_POKEFAN_F","SPRITE_SAILOR","SPRITE_GENTLEMAN",
      "SPRITE_TEACHER","SPRITE_BEAUTY","SPRITE_BIKER","SPRITE_BLACK_BELT",
      "SPRITE_GRAMPS",
    }
    local trainerSprites={}
    for _,id in ipairs(trainerSpriteCandidates) do
      if game.data.gen2Sprites and game.data.gen2Sprites[id] then trainerSprites[#trainerSprites+1]=id end
    end
    if #trainerSprites==0 then trainerSprites[1]="SPRITE_COOLTRAINER_M" end
    local function randomDelverSprite() return trainerSprites[r(#trainerSprites)] end

    local traps={}
    if lockedThreshold or terminalFloor then
      -- First-clear B20/B40 and the B60 terminus are intentionally empty save
      -- for the visible threshold stair. Stepping on it handles completion or
      -- consumes the proper progression key. No special NPC is required.
    elseif checkpoint or thresholdUnlocked then
      local cy=3
      local cx=math.max(4,math.floor((width*2)/2))
      local spots={{x=cx-2,y=cy},{x=cx,y=cy},{x=cx+2,y=cy}}
      for _,spot in ipairs(spots) do reserve(spot.x,spot.y) end
      addRole("healer","SPRITE_RECEPTIONIST",spots[1].x,spots[1].y)
      addRole("trader","SPRITE_SUPER_NERD",spots[2].x,spots[2].y,{tradeGiveIndex=r(10),tradeGetIndex=r(15)})
      addRole("extract","SPRITE_SCIENTIST",spots[3].x,spots[3].y)
    elseif bossFloor then
      -- Every floor ending in 9 is a guardian check.  B19/B39/B59 remain the
      -- major stratum sentinels; B9/B29/B49 are slightly lighter mid-stratum
      -- fights so the ten-floor cadence does not flatten every boss together.
      local function rollGuardian()
        local bossSpecies=nil; local bossScore=-1
        for _=1,10 do
          local candidate=chooseSpeciesForDepth(game,depth+8,r)
          local defn=game.data.pokemon and game.data.pokemon[candidate]
          local score=speciesBST(defn)
          if score>bossScore then bossSpecies,bossScore=candidate,score end
        end
        return bossSpecies or "RHYDON"
      end
      local bossSpecies=rollGuardian()
      local bossLevel=clamp(generatedWildLevel(depth,r)+(majorBoss and 17 or 16),2,100)
      addRole("monster",delveRoamerSprite(game,bossSpecies),descent.x,descent.y,{
        species=bossSpecies,level=bossLevel,moveDir="up",cooldown=0,boss=true,
        bossTier=majorBoss and "major" or "standard",
      })

      -- A co-op guardian floor gives EACH Delver a live guardian to challenge.
      -- Keep the second one close to the descent but on its own walkable cell;
      -- the ladder remains locked until both authoritative boss entities are
      -- defeated. Single-player floors retain the original one-guardian rule.
      if SPECIAL.COOP and SPECIAL.COOP.isRunActive and SPECIAL.COOP.isRunActive() then
        local candidates={}
        for _,cell in ipairs(cells) do
          local x,y=cell[1],cell[2]; local k=y*1024+x
          local dist=math.abs(x-descent.x)+math.abs(y-descent.y)
          if not used[k] and dist>=2 and dist<=6 and openDegree(x,y)>=2 then
            candidates[#candidates+1]={x=x,y=y,d=dist}
          end
        end
        table.sort(candidates,function(a,b)
          if a.d~=b.d then return a.d<b.d end
          if a.y~=b.y then return a.y<b.y end
          return a.x<b.x
        end)
        local spot=candidates[1]
        if not spot then
          local x,y=takeCell(4,false); if x then spot={x=x,y=y} end
        else reserve(spot.x,spot.y) end
        if spot then
          local secondSpecies=rollGuardian()
          addRole("monster",delveRoamerSprite(game,secondSpecies),spot.x,spot.y,{
            species=secondSpecies,level=bossLevel,moveDir="up",cooldown=0,boss=true,
            bossTier=majorBoss and "major" or "standard",
          })
        end
      end
    else
      local shelfCount=rrange(r,1,3)
      for _=1,shelfCount do
        local sx,sy=takeCell(3,true)
        if sx then
          local hasItem=(r(100)<=55)
          local propSprite=(r(100)<=55) and "SPRITE_POKEDEX" or "SPRITE_PAPER"
          addRole("shelf",propSprite,sx,sy,{
            shelfItem=hasItem and rollLootId() or nil,
            shelfNote=shelfNotes[r(#shelfNotes)],
            propKind=(propSprite=="SPRITE_POKEDEX") and "equipment" or "papers",
          })
        end
      end

      -- Azure-Dreams-style wandering monsters replace random encounter rolls.
      -- Their species/levels are fixed from the deterministic floor seed.
      local monsterCount=math.max(0,rrange(r,5,8)+(modifier.extraMonsters or 0))
      local dirs={"up","down","left","right"}
      for _=1,monsterCount do
        local mx,my=takeCell(5,true)
        if mx then
          local species=chooseSpeciesForDepth(game,depth,r)
          addRole("monster",delveRoamerSprite(game,species),mx,my,{
            species=species,level=generatedWildLevel(depth,r),
            moveDir=dirs[r(#dirs)],cooldown=0,
          })
        end
      end

      -- Every ordinary-floor delver draws from the same trainer-sprite pool.
      -- Appearance therefore gives no clue whether the stranger battles,
      -- trades, or springs a trap. Dedicated healer sprites exist only at the
      -- ten-floor post-guardian rest stops.
      local trainerCount=math.max(0,2+(modifier.extraTrainers or 0))
      for _=1,trainerCount do
        local x,y=takeCell(4,true); addRole("trainer",randomDelverSprite(),x,y)
      end
      for _,role in ipairs({"trader","trickster"}) do
        local nx,ny=takeCell(3,true)
        addRole(role,randomDelverSprite(),nx,ny,role=="trader" and {tradeGiveIndex=r(10),tradeGetIndex=r(15)} or nil)
      end

      local lootCount=math.max(0,4+(modifier.extraLoot or 0))
      for _=1,lootCount do local lx,ly=takeCell(2); addLoot(lx,ly) end

      local trapTypes={"BOULDER","POISON","BLINDER","CHAOS","SLEEP","SLOW","WARP","RUST"}
      local trapCount=math.max(0,4+(modifier.extraTraps or 0)+(depth>=8 and 1 or 0))
      for _=1,trapCount do
        local tx,ty=takeCell(3)
        if tx then
          traps[ty*1024+tx]={
            x=tx,y=ty,used=false,type=trapTypes[r(#trapTypes)],
            id="T"..tostring(depth).."_"..tostring(tx).."_"..tostring(ty),
          }
        end
      end

      local hasRelic=false
      if SPECIAL.COOP and SPECIAL.COOP.isRunActive() then
        hasRelic=pdSave(game).coopRelicActive==true
      else
        for _,mon in ipairs(game.save.party or {}) do if mon.item==GEAR_CHARM then hasRelic=true break end end
      end
      local function addFossilDeposit(minDistance)
        local fx,fy=takeCell(minDistance or 4,true)
        if not fx then return false end
        local root,part=Fossils.rollDeposit(r,depth)
        if modifier.ancientBias and r(10000)<=math.floor(modifier.ancientBias*10000) then
          for _=1,6 do
            local rr,pp=Fossils.rollDeposit(r,depth)
            if ANCIENT[rr] then root,part=rr,pp break end
          end
        end
        addRole("fossil","SPRITE_ROCK",fx,fy,{fossilRoot=root,fossilPart=part})
        return true
      end
      if specialFeature and specialFeature.id=="FOSSIL_CHAMBER" then
        -- Rare dedicated dig floor: 3-5 guaranteed deposits from this stratum's
        -- fossil pool.  The encounter/trap counts are reduced above so the room
        -- feels like a geological find rather than a normal floor with extra rocks.
        local fossilCount=rrange(r,3,5)
        for _=1,fossilCount do if not addFossilDeposit(3) then break end end
      else
        local fossilChance=clamp(.08+depth*.012+(hasRelic and .12 or 0)+(modifier.fossilBonus or 0),.08,.65)
        if r(10000)<=math.floor(fossilChance*10000) then addFossilDeposit(4) end
      end

      -- Special-floor foundation.  These systems deliberately reuse native
      -- Crystal objects/tiles so we can iterate on behavior before committing
      -- to bespoke room art.
      if specialFeature and specialFeature.id=="WARP_MATRIX" then
        specialFeature.links={}
        specialFeature.panels={}
        for pair=1,2 do
          local ax,ay=takeCell(5,true)
          local bx,by=takeCell(5,true)
          if ax and bx then
            specialFeature.links[ay*1024+ax]={x=bx,y=by}
            specialFeature.links[by*1024+bx]={x=ax,y=ay}
            specialFeature.panels[#specialFeature.panels+1]={x=ax,y=ay}
            specialFeature.panels[#specialFeature.panels+1]={x=bx,y=by}
          end
        end
      elseif specialFeature and specialFeature.id=="SEALED_GATE" then
        local kx,ky=takeCell(7,true)
        if kx then
          addRole("floor_key","SPRITE_POKE_BALL",kx,ky,{specialKey=true})
          addRole("gate",(game.data.gen2Sprites and game.data.gen2Sprites.SPRITE_BOULDER) and "SPRITE_BOULDER" or "SPRITE_ROCK",descent.x,descent.y,{specialGate=true})
          specialFeature.keyFound=false
          specialFeature.gateOpen=false
        end
      elseif specialFeature and specialFeature.id=="HAZARD_GRID" then
        specialFeature.hazards={}
        local hazardCount=rrange(r,7,12)
        for i=1,hazardCount do
          local hx,hy=takeCell(3)
          if hx then
            specialFeature.hazards[hy*1024+hx]={
              x=hx,y=hy,kind=(i%3==0) and "TOXIC" or "HEAT",
              used=false,revealed=false,
            }
          end
        end
      end
    end

    -- Turn expedition notes into actual navigation help and a continuing
    -- explorer-log story instead of generic flavor text.
    if not checkpoint and not bossFloor then
      local firstLoot=nil
      for _,row in ipairs(entities) do
        if row.active and (row.role=="loot" or row.role=="fossil") then firstLoot=row break end
      end
      local nearExitTrap=nil; local nearest=999
      for _,tr in pairs(traps) do
        local dist=math.abs(tr.x-descent.x)+math.abs(tr.y-descent.y)
        if dist<nearest then nearest=dist; nearExitTrap=tr end
      end
      local logPages={
        {"FIELD NOTE", "The caverns change character every few layers. No two descents stay alike."},
        {"FIELD NOTE", "Some walls look natural. Others are too straight. Someone may have shaped them."},
        {"FIELD NOTE", "Fossil beds grow richer below, but the stone around them is less stable."},
        {"FIELD NOTE", "Old tool marks cross a passage that should predate modern Pewter."},
        {"FIELD NOTE", "Powerful wild POKéMON sometimes guard routes into the deeper strata."},
        {"FIELD NOTE", "Those guardians gather near descents. Prepare before forcing your way past."},
        {"FIELD NOTE", "Warm limestone gave way to black rock, then pale mineral seams below."},
        {"FIELD NOTE", "Someone left supply caches in places that make little sense. Earlier Delvers?"},
        {"FIELD NOTE", "Below B20, fitted stone replaces cave wall. The joins are far too regular."},
        {"FIELD NOTE", "Old metal fittings appear in the deep halls. No Pewter record mentions builders."},
        {"EXPEDITION LOG I", "Past the warm rock, we found a layer of blue ice."},
        {"EXPEDITION LOG II", "Something was frozen inside it. A POKéMON, I think."},
        {"EXPEDITION LOG III", "Its shape matches nothing in the modern field guides."},
        {"EXPEDITION LOG IV", "We could not free it. The deeper ice may hold another."},
      }
      local shelfNo=0
      for _,row in ipairs(entities) do
        if row.role=="shelf" then
          shelfNo=shelfNo+1
          if shelfNo==1 and nearExitTrap and nearest<=7 then
            row.shelfPages={"A Delver marked the ladder route.","TRAP NEAR EXIT. Watch the last few steps."}
          elseif shelfNo==2 and firstLoot then
            local east=firstLoot.x>(width*2)/2
            local south=firstLoot.y>(height*2)/2
            local quadrant=(south and "SOUTH" or "NORTH")..(east and "EAST" or "WEST")
            row.shelfPages={"An old cache note is still readable.","SUPPLIES: "..quadrant.." quarter of this floor."}
          else
            row.shelfPages=logPages[((depth+shelfNo-2)%#logPages)+1]
          end
        end
      end
    end

    game.data.gen2Maps[FLOOR]=def
    if game.world and game.world.maps then game.world.maps[FLOOR]=def end
    clearFloorCaches(game.world)

    local floorStateNew={
      depth=depth,template=source.id,style=source.label,tone=tone.label,layer=tone.label,
      checkpoint=checkpoint,thresholdDepth=thresholdDepth,thresholdUnlocked=thresholdUnlocked,
      lockedThreshold=lockedThreshold,terminalFloor=terminalFloor,campFloor=campFloor,
      bossFloor=bossFloor,majorBoss=majorBoss,bossAlive=bossFloor,modifier=modifier,
      constructed=constructed,specialFeature=specialFeature,
      layout=layout,start=start,descent=descent,stability=stability,maxStability=stability,
      entities=entities,entityAt={},traps=traps,walkable=seen,explored={},
      cellWidth=width*2,cellHeight=height*2,mapRevealed=campFloor,exitRevealed=campFloor,
      fossilsRevealed=false,monsterTurn=0,collapsing=false,warned=false,
    }
    for _,e in ipairs(entities) do floorStateNew.entityAt[e.y*1024+e.x]=e end
    for yy=start.y-1,start.y+1 do
      for xx=start.x-1,start.x+1 do
        local k=yy*1024+xx
        if seen[k] then floorStateNew.explored[k]=true end
      end
    end
    s.floor=depth; s.stability=stability; s.maxStability=stability
    s.style=tone.label.." / "..layout; s.modifier=modifier.label; s.layer=tone.label
    s.mapRevealFloor=nil; s.exitRevealFloor=nil; s.fossilRevealFloor=nil
    floorState=floorStateNew
    if SPECIAL.COOP and SPECIAL.COOP.floorGenerated then SPECIAL.COOP.floorGenerated(game,floorStateNew) end
    return floorStateNew
  end

  local function floorObjectId(e)
    return FLOOR.."_obj_"..tostring(e.index)
  end

  -- DEV118: rebuild the generated floor's live NPC list from floorState. This
  -- is deliberately authoritative and index-deduping because every procedural
  -- depth shares PEWTER_DUNGEON_FLOOR. On same-map transitions the engine can
  -- retain old live actors even though the map definition has been replaced.
  -- Rest stops exposed this most clearly: one client could lose the Scientist
  -- while another kept multiple attendants stacked on the same cell.
  SPECIAL.reconcileFloorNpcs=function(game)
    local world=game and game.world
    if not (floorState and world and world.map and world.map.id==FLOOR) then return false end

    local liveByIndex={}
    local keptNpcs={}
    local keptEntities={}
    local npcSeen={}
    local entitySeen={}
    local function ownedFloorActor(npc)
      local d=npc and npc.def
      return d and d.owner==OWNER and d.pewterRole and d.pewterRole~="threshold_miner"
    end
    local function addUnique(list,seen,npc)
      if npc and not seen[npc] then seen[npc]=true; list[#list+1]=npc end
    end

    -- Harvest exactly one reusable live actor per generated index. Everything
    -- else owned by this generated floor is stale/duplicate and is discarded.
    for _,npc in ipairs(world.npcs or {}) do
      if ownedFloorActor(npc) then
        local idx=tonumber(npc.def and npc.def.index)
        if idx and not liveByIndex[idx] then liveByIndex[idx]=npc end
      else
        addUnique(keptNpcs,npcSeen,npc)
      end
    end
    for _,npc in ipairs(world.entities or {}) do
      if not ownedFloorActor(npc) then addUnique(keptEntities,entitySeen,npc) end
    end

    -- Rebuild peopleFromMap too. Snapshot-created actors used to be absent from
    -- this table, so the next same-map setMap treated them as mod GUESTS and
    -- preserved them on top of the next floor's new object rows.
    local made={}
    for npc,v in pairs(world.peopleFromMap or {}) do
      if not ownedFloorActor(npc) then made[npc]=v end
    end

    for _,entity in ipairs(floorState.entities or {}) do
      if entity.active and entity.role~="threshold_miner" then
        local idx=tonumber(entity.index)
        local npc=idx and liveByIndex[idx] or nil
        if not npc and world.pooledNpc then npc=world:pooledNpc(FLOOR,entity.obj) end
        if npc then
          npc.def=entity.obj
          local spriteDef=(world.sprites and world.sprites[entity.obj.sprite])
            or (game.data.gen2Sprites and game.data.gen2Sprites[entity.obj.sprite])
          if spriteDef and npc.setSpriteDef and npc:setSpriteDef(spriteDef) and world.applySpritePalette then
            world:applySpritePalette(npc)
          end
          npc.hiddenByMovement=false
          if npc.placeAt then npc:placeAt(entity.x,entity.y,npc.facing or "down")
          else npc.cellX,npc.cellY=entity.x,entity.y; npc.px,npc.py=entity.x*16,entity.y*16 end
          addUnique(keptNpcs,npcSeen,npc)
          addUnique(keptEntities,entitySeen,npc)
          made[npc]=true
        end
      end
    end
    world.npcs=keptNpcs
    world.entities=keptEntities
    world.peopleFromMap=made
    return true
  end

  local function removeEntity(game,e)
    if not (e and e.active) then return end
    if SPECIAL.COOP then SPECIAL.COOP.entityRemoved(game,e) end
    e.active=false
    if floorState then
      floorState.entityAt[e.y*1024+e.x]=nil
      if e.boss then
        local anyBoss=false
        for _,row in ipairs(floorState.entities or {}) do
          if row.active and row.boss then anyBoss=true; break end
        end
        floorState.bossAlive=anyBoss
      end
    end
    local world=game and game.world
    if world and world.removeRuntimeObject then
      pcall(world.removeRuntimeObject,world,floorObjectId(e),OWNER)
    end
    -- A synchronized pickup can arrive while the guest still has a pooled/live
    -- copy of the runtime object.  removeRuntimeObject normally rebuilds it away,
    -- but force-purge our owned object by generated entity index as a fallback so
    -- a collected Poke Ball can never remain drawn as an untouchable ghost.
    local def=game and game.data and game.data.gen2Maps and game.data.gen2Maps[FLOOR]
    if def and type(def.objects)=="table" then
      for i=#def.objects,1,-1 do
        local obj=def.objects[i]
        if obj and obj.owner==OWNER and tonumber(obj.index)==tonumber(e.index) then
          table.remove(def.objects,i)
        end
      end
    end
    if world and world.maps and world.maps[FLOOR] and world.maps[FLOOR]~=def
        and type(world.maps[FLOOR].objects)=="table" then
      local objects=world.maps[FLOOR].objects
      for i=#objects,1,-1 do
        local obj=objects[i]
        if obj and obj.owner==OWNER and tonumber(obj.index)==tonumber(e.index) then table.remove(objects,i) end
      end
    end
    if world then
      if world.npcPool then world.npcPool[floorObjectId(e)]=nil end
      if type(world.npcs)=="table" then
        for i=#world.npcs,1,-1 do
          local npc=world.npcs[i]; local d=npc and npc.def
          if d and d.owner==OWNER and tonumber(d.index)==tonumber(e.index) then
            table.remove(world.npcs,i)
          end
        end
      end
      if type(world.entities)=="table" then
        for i=#world.entities,1,-1 do
          local npc=world.entities[i]; local d=npc and npc.def
          if d and d.owner==OWNER and tonumber(d.index)==tonumber(e.index) then
            table.remove(world.entities,i)
          end
        end
      end
    end
  end

  local function randomPartyMon(game,allowFainted)
    local pool={}
    for _,mon in ipairs((game.save and game.save.party) or {}) do
      if mon and not mon.isEgg and (allowFainted or (tonumber(mon.hp) or 0)>0) then
        pool[#pool+1]=mon
      end
    end
    if #pool==0 then return nil end
    local s=pdSave(game)
    local seed=floorSeed(s,(floorState and floorState.depth) or s.floor or 1)
      +(floorState and floorState.stability or 0)*193+#pool*17
    return pool[rng(seed)(#pool)]
  end

  local function refreshBlindPipeline(game)
    local s=game and pdSave(game)
    local on=s and s.active and game.world and game.world.map
      and game.world.map.id==FLOOR and not (floorState and floorState.campFloor)
    if Pipelines and Pipelines.setLevel then
      pcall(Pipelines.setLevel,BLIND_PIPELINE,on and 1 or 0)
    end
  end

  local function exploredAround(fs,x,y,radius)
    if not fs then return end
    fs.explored=fs.explored or {}
    radius=radius or 1
    for yy=y-radius,y+radius do
      for xx=x-radius,x+radius do
        local k=yy*1024+xx
        if fs.walkable and fs.walkable[k] then fs.explored[k]=true end
      end
    end
  end

  -- A compact in-run dungeon map. Only traversed/nearby cells appear until a
  -- SURVEY CHART reveals the whole floor.
  mod.content.screens:register(MAP_SCREEN,{
    new=function(game)
      local state={game=game,isOpaque=true}
      function state:update(dt)
        local input=game.input
        if input and (input:wasPressed("b") or input:wasPressed("start")
            or input:wasPressed("a")) then
          game.stack:pop()
        end
      end
      function state:draw()
        Chrome.clear()
        Chrome.box(0,0,20,18)
        love.graphics.setColor(0,0,0,1)
        Font.draw("DELVE MAP  B"..tostring((floorState and floorState.depth) or "?"),8,8)
        if not floorState then
          Font.draw("NO ACTIVE FLOOR",24,64)
          return
        end
        local fs=floorState
        local x0,y0=8,27
        local availW,availH=144,101
        local cw,ch=math.max(1,fs.cellWidth or 1),math.max(1,fs.cellHeight or 1)
        local scale=math.max(2,math.floor(math.min(availW/cw,availH/ch)))
        local ox=x0+math.floor((availW-cw*scale)/2)
        local oy=y0+math.floor((availH-ch*scale)/2)
        local reveal=fs.mapRevealed or pdSave(game).mapRevealFloor==fs.depth
        love.graphics.setColor(.86,.86,.86,1)
        for k in pairs(fs.walkable or {}) do
          if reveal or (fs.explored and fs.explored[k]) then
            local y=math.floor(k/1024); local x=k-y*1024
            love.graphics.rectangle("fill",ox+x*scale,oy+y*scale,scale,scale)
          end
        end
        local p=game.world and game.world.player
        if p then
          love.graphics.setColor(0,0,0,1)
          love.graphics.rectangle("fill",ox+p.cellX*scale,oy+p.cellY*scale,scale,scale)
        end
        local d=fs.descent
        if d then
          -- The staircase is always marked even before its room is explored.
          love.graphics.setColor(.12,.12,.12,1)
          love.graphics.rectangle("line",ox+d.x*scale,oy+d.y*scale,scale,scale)
          love.graphics.line(ox+d.x*scale,oy+d.y*scale+scale-1,ox+d.x*scale+scale-1,oy+d.y*scale)
        end
        -- Trainers and pickups appear once their cell has been explored (or the
        -- floor has been fully surveyed).  Filled square = trainer, center dot =
        -- item/fossil.  Removed pickups vanish immediately.
        for _,e in ipairs(fs.entities or {}) do
          local known=reveal or (fs.explored and fs.explored[e.y*1024+e.x])
            or (e.role=="fossil" and (fs.fossilsRevealed or pdSave(game).fossilRevealFloor==fs.depth))
          if e.active and known and e.role=="trainer" then
            love.graphics.setColor(.12,.12,.12,1)
            love.graphics.rectangle("fill",ox+e.x*scale,oy+e.y*scale,scale,scale)
          elseif e.active and known and (e.role=="loot" or e.role=="fossil" or e.role=="floor_key") then
            love.graphics.setColor(.12,.12,.12,1)
            local dot=math.max(1,math.floor(scale/2))
            love.graphics.rectangle("fill",ox+e.x*scale+math.floor((scale-dot)/2),oy+e.y*scale+math.floor((scale-dot)/2),dot,dot)
          end
        end
        for _,tr in pairs(fs.traps or {}) do
          if tr.used or tr.revealed then
            love.graphics.setColor(.7,.08,.08,1)
            love.graphics.rectangle("fill",ox+tr.x*scale,oy+tr.y*scale,math.max(1,scale),math.max(1,scale))
          end
        end
        local sf=fs.specialFeature
        if sf and sf.hazards then
          for _,hz in pairs(sf.hazards) do
            if hz.used or hz.revealed then
              if hz.kind=="TOXIC" then love.graphics.setColor(.55,.12,.65,1)
              else love.graphics.setColor(.85,.35,.05,1) end
              love.graphics.rectangle("fill",ox+hz.x*scale,oy+hz.y*scale,math.max(1,scale),math.max(1,scale))
            end
          end
        end
        love.graphics.setColor(0,0,0,1)
        Font.draw(reveal and "FULL SURVEY" or "EXPLORE TO MAP",8,132)
      end
      return state
    end,
  })

  -- Public-facing delve navigation uses only the always-on corner minimap.
  -- The old full-screen DELVE MAP screen remains registered for save/debug
  -- compatibility, but it is no longer exposed through START.

  -- Fossil excavation / catalogue UI lives in fossils.lua so this already-large
  -- dungeon controller stays below LuaJIT's 200-local function limit.

  local function queuePostWarpMessage(game,text,arrivalSfx)
    local s=pdSave(game)
    local pages=(type(text)=="table") and text or {tostring(text or "")}
    s.pendingPostWarpMessage={pages=pages,frames=2,arrivalSfx=arrivalSfx}
  end

  local function ensureThresholdMinerLive(game)
    local fs=floorState
    local world=game and game.world
    if not (fs and fs.lockedThreshold and world and world.map and world.map.id==FLOOR) then return end
    local target=nil
    for _,e in ipairs(fs.entities or {}) do
      if e.active and e.role=="threshold_miner" then target=e; break end
    end
    if not target then return end

    -- Build a private drawable NPC that is NOT part of the generated map's
    -- object lifecycle. This is intentionally separate from world.npcs: the
    -- same procedural map id is reloaded for every depth, and the normal object
    -- pool repeatedly swallowed the one B20/B40 actor despite successful map
    -- reconstruction. A unique high index gives SpriteRenderer a stable seed
    -- while floorState owns visibility and interaction.
    local obj=deep(target.obj or {})
    obj.index=900+(tonumber(fs.depth) or 0)
    obj.x,target.x=target.x,target.x
    obj.y,target.y=target.y,target.y
    obj.pewterRole="threshold_miner"
    local npc=world:pooledNpc(FLOOR,obj)
    if npc then
      npc.def=obj
      npc.hiddenByMovement=false
      if npc.placeAt then npc:placeAt(target.x,target.y,"down")
      else
        npc.cellX,npc.cellY=target.x,target.y
        npc.px,npc.py=target.x*16,target.y*16
        npc.facing="down"
      end
      target.virtualNpc=npc

      -- DEV83 only owned this actor through floorState and tried to paint it
      -- later in render.hud. That explains the user's clue perfectly: the
      -- collision cell existed, but World:facingObject could not see anyone
      -- there and the normal overworld draw pass never received the miner.
      -- Put the private high-index actor into World.npcs after every same-map
      -- floor rebuild. It now participates in the engine's ordinary sorting,
      -- drawing, facingObject lookup and interaction exactly like any NPC,
      -- while still avoiding the reused procedural map-object index bug.
      world.npcs=world.npcs or {}
      local present=false
      for _,live in ipairs(world.npcs) do
        if live==npc or (live and live.id==npc.id) then present=true; break end
      end
      if not present then world.npcs[#world.npcs+1]=npc end
    end
  end

  SPECIAL.delveFloorMusic=function(depth)
    depth=math.floor(tonumber(depth) or 1)
    -- Natural caverns retain the cave theme. The constructed middle stratum
    -- uses Team Rocket HQ's mechanical hideout track, while the deep sanctum
    -- uses Bell/Tin Tower's native Crystal track.
    if depth>=41 then return "Music_TinTower" end
    if depth>=21 then return "Music_RocketHideout" end
    if floorState and floorState.checkpoint then return "Music_PokemonCenter" end
    return DELVE_MAP_MUSIC
  end

  local function safeWarp(game,map,x,y,facing)
    if map==FLOOR and game and game.data and game.data.audio and game.data.audio.mapSongs then
      local depth=(floorState and floorState.depth) or (pdSave(game).floor) or 1
      local song=SPECIAL.delveFloorMusic(depth)
      if not game.data.audio.songs or game.data.audio.songs[song] then game.data.audio.mapSongs[FLOOR]=song end
    end
    local ok,err=mod.world:warpTo(map,x,y,facing or "down")
    if not ok then
      mod.log:warn("Pewter Dungeon warp failed: %s",tostring(err))
      return ok
    end
    if map==FLOOR then
      if SPECIAL.reconcileFloorNpcs then pcall(SPECIAL.reconcileFloorNpcs,game) end
      ensureThresholdMinerLive(game)
    end
    -- Rare floor conditions are announced only after the destination has had
    -- time to render, avoiding a textbox over the transient white warp frame.
    if map==FLOOR and floorState and not floorState.checkpoint
        and floorState.modifier and floorState.modifier.id~="NORMAL"
        and not floorState.effectAnnounced then
      floorState.effectAnnounced=true
      queuePostWarpMessage(game,{
        "FLOOR EFFECT:\n"..tostring(floorState.modifier.label or "UNKNOWN"),
        tostring(floorState.modifier.desc or "The cavern behaves differently here."),
      })
    end
    return ok
  end

  local function updateDeepest(game,depth)
    local s=pdSave(game)
    s.deepest=math.max(tonumber(s.deepest) or 0,tonumber(depth) or 0)
    mod.save:set("deepest",s.deepest)
  end

  local function backupAdventureState(game,s)
    s=s or pdSave(game)
    s.partyBackup=deep(game.save.party or {})
    s.inventoryBackup=deep(game.save.inventory or {})
    s.bagOrderBackup=deep(game.save.bagOrder or {})
    s.pokedexBackup=deep(game.save.pokedex or {})
    s.firstUnownBackup=game.save.firstUnownSeen
    s.unownDexBackup=deep(game.save.unownDex or {})
    s.psRentalBackup=game.save.pokesurvive_factory_rentals
  end

  local function restoreEscrow(game)
    local s=pdSave(game)
    if type(s.partyBackup)=="table" then game.save.party=s.partyBackup end
    if type(s.inventoryBackup)=="table" then game.save.inventory=s.inventoryBackup end
    if type(s.bagOrderBackup)=="table" then game.save.bagOrder=s.bagOrderBackup end
    if type(s.pokedexBackup)=="table" then game.save.pokedex=s.pokedexBackup end
    if s.firstUnownBackup~=nil then game.save.firstUnownSeen=s.firstUnownBackup end
    if type(s.unownDexBackup)=="table" then game.save.unownDex=s.unownDexBackup end
    game.save.pokesurvive_factory_rentals=s.psRentalBackup
    s.partyBackup=nil; s.inventoryBackup=nil; s.bagOrderBackup=nil; s.pokedexBackup=nil
    s.firstUnownBackup=nil; s.unownDexBackup=nil; s.psRentalBackup=nil; s.active=false; s.floor=nil
    s.stability=nil; s.maxStability=nil; s.style=nil; s.modifier=nil; s.layer=nil
    s.blindSteps=nil; s.chaosSteps=nil; s.chaosMap=nil; s.nextBattleConfused=nil
    s.slowSteps=nil; s.mapRevealFloor=nil; s.exitRevealFloor=nil; s.fossilRevealFloor=nil
    s.pendingPostWarpMessage=nil; s.pendingEscapeHatch=nil; s.pendingCaughtMon=nil; s.pendingBossAftermath=nil
    floorState=nil; transitioning=false
    if Pipelines and Pipelines.setLevel then pcall(Pipelines.setLevel,BLIND_PIPELINE,0) end
  end

  local function finishRun(game,reason,extracted,opts)
    local world=game and game.world
    local s=pdSave(game)
    if not s.active then return end
    opts=opts or {}
    local recap=nil
    if opts.recapAtDesk then
      local fossilCount=#(s.carriedFossils or {})
      local itemCount=0
      for _,qty in pairs(s.carriedTreasures or {}) do itemCount=itemCount+(tonumber(qty) or 0) end
      recap={
        floor=tonumber(s.floor) or 1,
        startFloor=tonumber(s.runStartFloor) or 1,
        rp=tonumber(s.runRpEarned) or 0,
        fossils=fossilCount,items=itemCount,keyNotice=opts.keyNotice,
      }
    end
    updateDeepest(game,s.floor or 1)
    Fossils.extractRunLoot(s,extracted)
    if opts.freshRoster then
      -- Normal offers stay locked for a full 24 RTC hours, but a failed delve
      -- immediately retires the current roster. The next desk visit generates
      -- a fresh six-Pokemon roster and begins a new 24-hour lock from then.
      s.rentalOfferStartMinutes=nil
      s.rentalOfferSeed=nil
      s.freshRosterReady=true
    end
    Fossils.clearRunLoot(s)
    restoreEscrow(game)
    if extracted then Fossils.settleSecuredLoot(game) end
    if s.coopRun then
      s.coopRun=nil; s.coopRelicActive=nil; s.coopExpeditionId=nil
      SPECIAL.COOP.runEnded()
    end
    if recap then
      recap.frames=6
      s.pendingDelveRecap=recap
      safeWarp(game,LOBBY,lobbyReception.x,lobbyReception.y+2,"up")
      return
    end
    local msg=reason or (extracted and "DELVE COMPLETE!" or "THE DELVE ENDED.")
    local pages=opts.pages or {msg}
    local function backToDesk()
      safeWarp(game,LOBBY,lobbyReception.x,lobbyReception.y+2,"up")
    end
    if world then showPages(world,pages,backToDesk) else backToDesk() end
  end

  local function loseRun(game,reason)
    return finishRun(game,reason or "YOUR DELVE ENDED.",false,{freshRoster=true})
  end

  -- DEV114: keep the active-delve LEAVE menu injection in its own lexical
  -- scope. main.lua already sits at LuaJIT's 200-local ceiling; DEV113 kept
  -- this helper alive for the rest of the entry function and made the entire
  -- mod fail to compile. Scoping it here lets LuaJIT release that local before
  -- parsing the remainder of Dungeon Delvers.
  do
    local function openAbandonDelvePrompt(game)
      if not isActive(game) then return end
      -- Hook-injected START-menu rows do not automatically close the menu.
      -- Pop it before opening the confirmation so the normal delve teardown
      -- can return cleanly to the museum desk.
      if game and game.stack and game.stack.pop then game.stack:pop() end
      game.stack:push(TextBox.new(game,"Abandon this delve?\nLoot will be lost.",nil,{
        defaultNo=true,
        choice=function(yes)
          if not yes or not isActive(game) then return end
          finishRun(game,"DELVE ABANDONED.",false,{
            pages={
              "DELVE ABANDONED.",
              "Your original party\nand PACK were restored.",
            },
          })
        end,
      }))
    end

    mod.hooks:wrap("ui.start_menu.items",function(next,game,items)
      local out=next(game,items)
      if type(out)~="table" or not isActive(game) then return out end
      for _,item in ipairs(out) do
        if item and item.label=="LEAVE" then return out end
      end
      return mod.ui.insertBefore(out,"SAVE",{
        label="LEAVE",
        desc={"Abandon delve"},
        onSelect=function(g) openAbandonDelvePrompt(g or game) end,
      })
    end,160)
  end

  local function advanceFloor(game,collapsed)
    if transitioning or not isActive(game) then return end
    transitioning=true
    local world=game.world; local s=pdSave(game)
    local completedDepth=tonumber(s.floor) or 1
    local nextDepth=completedDepth+1
    local rpGain=1+math.floor(math.max(0,completedDepth-1)/20)
    if completedDepth%10==9 then
      rpGain=rpGain+((completedDepth%20==19) and 2 or 1)
    end
    s.researchPoints=(tonumber(s.researchPoints) or 0)+rpGain
    s.runRpEarned=(tonumber(s.runRpEarned) or 0)+rpGain
    if collapsed then
      local lead=game.save.party and game.save.party[1]
      if lead and lead.item==GEAR_ROPE then
        lead.item=nil
        if world and world.showText then
          showPages(world,{"The SAFETY ROPE caught the fall!"},function()
            local fs,err=generateFloor(game,nextDepth); transitioning=false
            if fs then safeWarp(game,FLOOR,fs.start.x,fs.start.y,"down")
            else finishRun(game,"FLOOR ERROR:\n"..tostring(err),false) end
          end)
          return
        end
      else
        for _,mon in ipairs(game.save.party or {}) do
          local dmg=math.max(1,math.floor((mon.maxHp or 1)*.20))
          mon.hp=math.max(1,(mon.hp or 1)-dmg)
        end
      end
    end

    local function finishDescent()
      local fs,err=generateFloor(game,nextDepth); transitioning=false
      if not fs then return finishRun(game,"FLOOR ERROR:\n"..tostring(err),false) end
      safeWarp(game,FLOOR,fs.start.x,fs.start.y,"down")
    end
    if not collapsed then
      Sound.dropPressSfx()
      mod.ui.push(game,"PewterDungeonFloorDrop",{onDone=finishDescent})
    else
      finishDescent()
    end
  end

  -- Persistent reward settlement -------------------------------------------------
  local function settleRestoredMon(game,mon)
    local save=game.save
    save.party=save.party or {}
    save.pokedex=save.pokedex or {seen={},caught={}}
    save.pokedex.seen=save.pokedex.seen or {}
    save.pokedex.caught=save.pokedex.caught or {}
    if Mon.stampOT then Mon.stampOT(save,mon) end

    local destination="party"; local boxIndex
    if #save.party<Boxes.PARTY_SIZE then
      save.party[#save.party+1]=mon
    else
      local startBox=tonumber(save.currentBox) or 1
      for step=0,Boxes.NUM_BOXES-1 do
        local idx=((startBox-1+step)%Boxes.NUM_BOXES)+1
        if not Boxes.isFull(save,idx) then boxIndex=idx; break end
      end
      if not boxIndex then return false,"YOUR PC BOXES\nARE FULL!" end
      local box=Boxes.box(save,boxIndex)
      table.insert(box,1,mon)
      Boxes.enterBox(mon)
      destination="box"
    end
    save.pokedex.seen[mon.species]=true
    save.pokedex.caught[mon.species]=true
    return true,destination,boxIndex
  end

  Fossils.init({
    mod=mod,pdSave=pdSave,getFloorState=function() return floorState end,
    floorSeed=floorSeed,rng=rng,clamp=clamp,showPages=showPages,removeEntity=removeEntity,
    deep=deep,buildMon=buildMon,settleRestoredMon=settleRestoredMon,markAncient=markAncient,
    speciesName=speciesName,Chrome=Chrome,Font=Font,Sound=Sound,Menu=Menu,Bag=Bag,TextBox=TextBox,
    special=SPECIAL,
    shareExcavationFind=function(game,e,find)
      if SPECIAL.COOP then SPECIAL.COOP.shareFind(game,find) end
    end,
    shareExcavationDone=function(game,e,summary)
      if SPECIAL.COOP and SPECIAL.COOP.miningComplete then SPECIAL.COOP.miningComplete(game,summary) end
    end,
  })

  -- Delve startup / escrow -------------------------------------------------------
  local function delveDayKey(game)
    local save=game and game.save or {}
    -- PokeSurvive can own an accelerated in-game weekday.  Respect it when
    -- present; otherwise Crystal's RTC/calendar day is the daily boundary.
    if save._pokesurviveClockDay~=nil then
      return "ps:"..tostring(save._pokesurviveClockDay)
    end
    local offset=tonumber(save.rtc and save.rtc.startMinute) or 0
    return os.date("%Y-%j",os.time()+offset*60)
  end

  local function hashOfferText(text,seed)
    local h=math.floor(tonumber(seed) or 104729)%2147483647
    for i=1,#text do h=(h*131+text:byte(i))%2147483647 end
    if h<=0 then h=1 end
    return h
  end

  local function chooseStarterOffers(game)
    local pool=starterSpecies(game); local picks={}
    local save=game and game.save or {}
    local playerId=tonumber(save.player and save.player.id) or 0
    local s=pdSave(game)
    local rtc=save.rtc or {}
    local rtcDay=tonumber(rtc.day)
    local rtcHour=tonumber(rtc.hour)
    local rtcMinute=tonumber(rtc.minute)
    local nowMinutes
    if rtcDay~=nil and rtcHour~=nil and rtcMinute~=nil then
      nowMinutes=rtcDay*1440 + rtcHour*60 + rtcMinute
    else
      nowMinutes=math.floor(os.time()/60)
    end
    local rosterStart=tonumber(s.rentalOfferStartMinutes)
    local seed=tonumber(s.rentalOfferSeed)
    if not rosterStart or not seed or nowMinutes<rosterStart or (nowMinutes-rosterStart)>=1440 then
      rosterStart=nowMinutes
      seed=hashOfferText("rtc24:"..tostring(rosterStart),104729+playerId*7919)
      s.rentalOfferStartMinutes=rosterStart
      s.rentalOfferSeed=seed
    end
    local r=rng(seed)
    while #picks<6 and #pool>0 do
      local i=r(#pool); picks[#picks+1]=table.remove(pool,i)
    end
    return picks,seed,#starterSpecies(game),"rtc24:"..tostring(rosterStart)
  end

  local function freshRunSeed(game)
    local seed=os.time()%2147483647
    if love and love.timer and love.timer.getTime then
      seed=(seed+math.floor(love.timer.getTime()*100000))%2147483647
    end
    local pid=tonumber(game and game.save and game.save.player and game.save.player.id) or 0
    seed=(seed+pid*104729)%2147483647
    if seed<=0 then seed=1 end
    return seed
  end

  local function beginDelve(game,species,seed,startDepth)
    local s=pdSave(game); local world=game.world
    if s.active then return showPages(world,{"A delve is already in progress."}) end
    startDepth=math.max(1,math.floor(tonumber(startDepth) or 1))
    local startLevel=(startDepth>=41 and 50) or (startDepth>=21 and 30) or 10

    local starter=buildMon(game,species,startLevel)
    if not starter then return showPages(world,{"That partner could not be prepared."}) end
    if s.pendingRentalSpecies==species and type(s.pendingRentalTypes)=="table" then
      starter._ddIndividualTypes=deep(s.pendingRentalTypes)
      starter.types=deep(s.pendingRentalTypes)
    end
    s.pendingRentalSpecies=nil; s.pendingRentalTypes=nil
    starter._pewterDungeonRental=true
    -- Fresh delves start lean: the chosen rental carries one BERRY, but the
    -- desk no longer hands out free POTIONs.  This keeps the opening resource
    -- decision on the Pokemon itself instead of front-loading bag healing.
    starter.item="BERRY"

    backupAdventureState(game,s)
    -- Do NOT borrow Battle Factory Remix's pokesurvive_factory_rentals flag.
    -- BFR intentionally suppresses EXP for any battle while that flag is true,
    -- which would make Delve partners stop leveling whenever BFR is installed.
    -- PokeSurvive's Pewter compatibility reads pewterDungeon.active directly.
    s.checkpoint=nil
    if not s.coopRun then s.coopExpeditionId=nil end
    if SPECIAL.COOP and SPECIAL.COOP.checkpointChanged then SPECIAL.COOP.checkpointChanged(game) end
    s.active=true
    -- Honor an explicit seed so later host-authoritative co-op can start both
    -- clients from the exact same deterministic delve.
    s.runSeed=tonumber(seed) or freshRunSeed(game)
    Fossils.clearRunLoot(s)
    s.blindSteps=nil; s.chaosSteps=nil; s.chaosMap=nil; s.slowSteps=nil
    s.nextBattleConfused=nil; s.mapRevealFloor=nil; s.exitRevealFloor=nil; s.fossilRevealFloor=nil
    s.pendingPostWarpMessage=nil; s.pendingEscapeHatch=nil; s.pendingCaughtMon=nil; s.pendingBossAftermath=nil
    s.floor=startDepth
    s.runStartFloor=startDepth
    s.runRpEarned=0

    game.save.party={starter}
    game.save.inventory={}
    for id,qty in pairs(s.inventoryBackup or {}) do
      if Bag.isBadge and Bag.isBadge(id) then game.save.inventory[id]=qty end
    end
    game.save.bagOrder={}
    -- Progression keys are real Key Items. Mirror them into the temporary
    -- delve bag so the threshold stair can consume one from the player.
    for _,keyId in ipairs({SPECIAL.WORKS_KEY,SPECIAL.MEGALITH_KEY}) do
      if (s.inventoryBackup and (s.inventoryBackup[keyId] or 0)>0) then
        Bag.add(game.save,keyId,1,game.data)
      end
    end
    Bag.add(game.save,"ANTIDOTE",1,game.data)
    Bag.add(game.save,ITEM_DELVE_BALL,5,game.data)
    Bag.add(game.save,SPECIAL.FIELD_CASE,1,game.data)

    local fs,err=generateFloor(game,startDepth)
    if not fs then
      restoreEscrow(game)
      return showPages(world,{"The delve floor\ncould not be made.",tostring(err):sub(1,34)})
    end
    showPages(world,{
      "DELVE PARTNER:\n"..speciesName(game,species).." Lv.10",
      "It is holding\na BERRY.",
      "5 DELVE BALLS\nand 1 ANTIDOTE packed.",
    },function()
      Sound.dropPressSfx()
      if world.playSfxNamed then world:playSfxNamed("Sfx_WarpTo") end
      safeWarp(game,FLOOR,fs.start.x,fs.start.y,"down")
    end)
  end

  local function checkpointExit(game)
    local s=pdSave(game); local world=game.world
    -- Midpoint camps (B10/B30/B50) and permanently-unlocked threshold camps
    -- (B20/B40) both use the Scientist as a checkpoint extraction point.
    -- The old guard accepted only floorState.checkpoint, so choosing YES at an
    -- unlocked B20/B40 rest stop silently returned without doing anything.
    local canCheckpoint=floorState and (floorState.checkpoint or floorState.thresholdUnlocked)
    if not (s.active and canCheckpoint) then return end
    local nextFloor=(tonumber(s.floor) or floorState.depth or 1)+1
    updateDeepest(game,s.floor or floorState.depth or 1)
    local cp={
      nextFloor=nextFloor,runSeed=s.runSeed,
      party=deep(game.save.party or {}),inventory=deep(game.save.inventory or {}),
      bagOrder=deep(game.save.bagOrder or {}),pokedex=deep(game.save.pokedex or {}),
      firstUnownSeen=game.save.firstUnownSeen,unownDex=deep(game.save.unownDex or {}),
      runStartFloor=s.runStartFloor,runRpEarned=s.runRpEarned,
      coopExpeditionId=s.coopRun and s.coopExpeditionId or nil,
    }
    -- Legacy DEV66 fossil-piece bag tokens must never survive into a checkpoint;
    -- DEV67 keeps fossil parts exclusively as DELVE CASE records.
    cp.inventory[SPECIAL.HEAD_FOSSIL]=nil
    cp.inventory[SPECIAL.UBODY_FOSSIL]=nil
    cp.inventory[SPECIAL.LBODY_FOSSIL]=nil
    Fossils.extractRunLoot(s,true)
    Fossils.clearRunLoot(s)
    restoreEscrow(game)
    Fossils.settleSecuredLoot(game)
    local wasCoop=s.coopRun and true or false
    s.checkpoint=cp
    if SPECIAL.COOP and SPECIAL.COOP.checkpointChanged then SPECIAL.COOP.checkpointChanged(game) end
    if wasCoop then
      s.coopRun=nil; s.coopRelicActive=nil; s.coopExpeditionId=nil
      SPECIAL.COOP.runEnded()
    end
    local function back()
      safeWarp(game,LOBBY,lobbyReception.x,lobbyReception.y+2,"up")
    end
    if world and world.showText then
      showPages(world,{"CHECKPOINT SECURED!","Resume at B"..tostring(nextFloor).."."},back)
    else back() end
  end

  local function resumeCheckpoint(game,coopOpts)
    local s=pdSave(game); local world=game.world; local cp=s.checkpoint
    if s.active then return showPages(world,{"A delve is already in progress."}) end
    if type(cp)~="table" or not cp.nextFloor then
      return showPages(world,{"No delve checkpoint is available."})
    end
    if coopOpts and coopOpts.coop then
      if not cp.coopExpeditionId
          or tostring(cp.coopExpeditionId)~=tostring(coopOpts.id or "")
          or tonumber(cp.nextFloor)~=tonumber(coopOpts.floor)
          or tonumber(cp.runSeed)~=tonumber(coopOpts.seed) then
        showPages(world,{"That shared checkpoint no longer matches your partner's."})
        return false
      end
    end
    cp=deep(cp)
    backupAdventureState(game,s)
    s.active=true; s.runSeed=cp.runSeed or freshRunSeed(game)
    s.floor=cp.nextFloor; s.checkpoint=nil
    s.runStartFloor=cp.runStartFloor or 1
    s.runRpEarned=cp.runRpEarned or 0
    if coopOpts and coopOpts.coop then
      s.coopRun=true; s.coopRelicActive=false; s.coopExpeditionId=cp.coopExpeditionId
    else
      s.coopRun=nil; s.coopRelicActive=nil; s.coopExpeditionId=nil
    end
    if SPECIAL.COOP and SPECIAL.COOP.checkpointChanged then SPECIAL.COOP.checkpointChanged(game) end
    s.blindSteps=nil; s.chaosSteps=nil; s.chaosMap=nil; s.slowSteps=nil
    s.nextBattleConfused=nil; s.mapRevealFloor=nil; s.exitRevealFloor=nil; s.fossilRevealFloor=nil
    s.pendingPostWarpMessage=nil; s.pendingEscapeHatch=nil; s.pendingCaughtMon=nil; s.pendingBossAftermath=nil
    Fossils.clearRunLoot(s)
    game.save.party=deep(cp.party or {})
    game.save.inventory=deep(cp.inventory or {})
    -- DEV67 fossils live only in the DELVE CASE. Strip legacy DEV66 token
    -- entries so old checkpoints cannot leak them back into the PACK.
    game.save.inventory[SPECIAL.HEAD_FOSSIL]=nil
    game.save.inventory[SPECIAL.UBODY_FOSSIL]=nil
    game.save.inventory[SPECIAL.LBODY_FOSSIL]=nil
    game.save.bagOrder=deep(cp.bagOrder or {})
    if type(cp.pokedex)=="table" then game.save.pokedex=deep(cp.pokedex) end
    game.save.firstUnownSeen=cp.firstUnownSeen
    if type(cp.unownDex)=="table" then game.save.unownDex=deep(cp.unownDex) end

    local fs,err=generateFloor(game,cp.nextFloor)
    if not fs then
      restoreEscrow(game); s.checkpoint=cp
      s.coopRun=nil; s.coopRelicActive=nil; s.coopExpeditionId=nil
      if SPECIAL.COOP and SPECIAL.COOP.checkpointChanged then SPECIAL.COOP.checkpointChanged(game) end
      showPages(world,{"The saved delve\ncould not resume.",tostring(err):sub(1,34)})
      return false
    end
    showPages(world,{
      (coopOpts and coopOpts.coop) and ("Shared checkpoint!\nReturning to B"..tostring(cp.nextFloor)..".")
        or ("Checkpoint restored!\nReturning to B"..tostring(cp.nextFloor).."."),
      "Your delve party\nand gear are intact.",
    },function() safeWarp(game,FLOOR,fs.start.x,fs.start.y,"down") end)
    return true
  end

  -- Battle Factory-style Delve Partner picker -----------------------------------
  local PARTNER_SCREEN="PewterDungeonPartnerDraft"
  local partnerPreviewImages={}

  local function previewImage(game,mon)
    if not (game and game.data and mon and mon.species) then return nil end
    local def=game.data.pokemon and game.data.pokemon[mon.species]
    local vanilla=def and def.spriteFront
    if not vanilla then return nil end
    local path,trueColor=Sprites.pic(vanilla,{
      species=mon.species,side="front",kind="summary",mon=mon,
      data=game.data,shiny=mon.shiny and true or false,
    })
    if not path then return nil end
    local image=partnerPreviewImages[path]
    if image==nil then
      local ok,loaded=pcall(Assets.image,path)
      image=(ok and loaded) or false
      partnerPreviewImages[path]=image
    end
    return image or nil,trueColor
  end

  local function typeLabel(typeId)
    return tostring(typeId or ""):gsub("_TYPE$",""):gsub(" TYPE$",""):gsub("_"," ")
  end

  local function previewTypes(game,mon)
    local raw=(mon and type(mon.types)=="table" and #mon.types>0) and mon.types or nil
    if not raw then
      local def=mon and game.data.pokemon and game.data.pokemon[mon.species]
      raw=(def and def.types) or {}
    end
    local out,seen={},{}
    for _,id in ipairs(raw or {}) do
      if id and not seen[id] then seen[id]=true; out[#out+1]=id end
    end
    return out
  end

  local function fitText(text,x,y,maxWidth)
    text=tostring(text or "")
    local width=(Font.width and Font.width(text)) or (#text*8)
    if width<=0 then return end
    local scale=math.min(1,maxWidth/width)
    if scale>=.999 then Font.draw(text,x,y); return end
    love.graphics.push(); love.graphics.translate(x,y); love.graphics.scale(scale,1)
    Font.draw(text,0,0); love.graphics.pop()
  end

  local function centeredText(text,left,width,y)
    text=tostring(text or "")
    local natural=(Font.width and Font.width(text)) or (#text*8)
    if natural<=0 then return end
    local scale=math.min(1,(width-4)/natural)
    local drawn=natural*scale
    fitText(text,left+math.floor((width-drawn)/2),y,width-4)
  end

  local function drawPartnerPreview(game,mon)
    if not mon then return end
    local image,trueColor=previewImage(game,mon)
    if image then
      local G=love.graphics; local iw,ih=image:getDimensions()
      local scale=math.min(1,56/math.max(1,iw),40/math.max(1,ih))
      local dx=96+math.floor((56-iw*scale)/2)
      local dy=8+math.floor((40-ih*scale)/2)
      local colors=game.data.gen2Palettes
        and Palettes.monColors(game.data.gen2Palettes,mon.species,mon.shiny) or nil
      local function body() G.setColor(1,1,1,1); G.draw(image,dx,dy,0,scale,scale) end
      if colors and not (trueColor and GbcPalette.mode=="gbc") and GbcPalette.available() then
        GbcPalette.with(colors,body)
      else body() end
    end
    local types=previewTypes(game,mon)
    love.graphics.setColor(0,0,0,1)
    if #types==1 then centeredText(typeLabel(types[1]),96,56,68)
    elseif #types>=2 then
      centeredText(typeLabel(types[1]),96,56,64)
      centeredText(typeLabel(types[2]),96,56,72)
    end
  end

  local function drawPartnerShell(game,mon,actionOpen,title)
    Chrome.box(0,0,11,3); Chrome.box(0,3,11,15)
    Chrome.box(11,0,9,7); Chrome.box(11,7,9,4)
    if not actionOpen then Chrome.box(11,11,9,7) end
    love.graphics.setColor(0,0,0,1)
    centeredText(title or "DELVE <PK><MN>",0,88,8)
    drawPartnerPreview(game,mon)
  end

  mod.content.screens:register(PARTNER_SCREEN,{
    new=function(game,opts)
      opts=opts or {}
      local Theme=require("src.ui.Theme")
      local SummaryMenu=require("src.ui.gen2.SummaryMenu")
      local state={game=game,isOpaque=false,cursor=1,actionMenu=nil}
      local picks,offerSeed,totalPool,dayKey=chooseStarterOffers(game)
      local pool={}
      for _,species in ipairs(picks) do
        local mon=buildMon(game,species,10)
        if mon then pool[#pool+1]=mon end
      end

      local function closeAction() state.actionMenu=nil end
      local function openStats(i)
        local mon=pool[i]; if not mon then return end
        game.stack:push(SummaryMenu.new(game,{mon=mon,save=game.save,onClose=function()
          if game.stack and game.stack:top() then game.stack:pop() end
        end}))
      end
      local function choose(i)
        local mon=pool[i]; if not mon then return end
        local saved=pdSave(game)
        saved.pendingRentalSpecies=mon.species
        saved.pendingRentalTypes=mon._ddIndividualTypes and deep(mon._ddIndividualTypes) or nil
        game.stack:pop()
        if opts.onDone then opts.onDone(mon.species) end
      end
      local function openAction(i)
        state.actionMenu=Menu.new(game,{
          {label="STATS",keepOpen=true,onSelect=function() openStats(i) end},
          {label="CHOOSE",keepOpen=true,onSelect=function() choose(i) end},
          {label="BACK",keepOpen=true,onSelect=closeAction},
        },{tx=11,ty=11,tw=9,th=7,cancelable=false,rowStep=2})
      end

      function state:update(dt)
        local input=game.input; if not input then return end
        if self.actionMenu then
          if input:wasPressed("b") then closeAction(); return end
          self.actionMenu:update(dt); return
        end
        if input:wasPressed("b") then
          game.stack:pop(); if opts.onDone then opts.onDone(nil) end; return
        end
        local count=#pool+1
        if input:wasPressed("up") then self.cursor=self.cursor-1; if self.cursor<1 then self.cursor=count end
        elseif input:wasPressed("down") then self.cursor=self.cursor+1; if self.cursor>count then self.cursor=1 end
        elseif input:wasPressed("a") then
          if self.cursor<=#pool then openAction(self.cursor)
          else game.stack:pop(); if opts.onDone then opts.onDone(nil) end end
        end
      end

      function state:draw()
        local focus=(self.cursor<=#pool) and pool[self.cursor] or nil
        drawPartnerShell(game,focus,self.actionMenu~=nil)
        local y=37; local step=11
        for i,mon in ipairs(pool) do
          if self.cursor==i and not self.actionMenu then Font.drawCode(Theme.cursor,8,y) end
          fitText(speciesName(game,mon.species),16,y,64); y=y+step
        end
        if self.cursor==#pool+1 and not self.actionMenu then Font.drawCode(Theme.cursor,8,y) end
        Font.draw("BACK",16,y)
        if not self.actionMenu then
          love.graphics.setColor(0,0,0,1)
          -- daily / total pool intentionally hidden
        end
        if self.actionMenu then self.actionMenu:draw() end
      end
      return state
    end,
  })

  -- Crystal stores the player's wallet under save.player.money and exposes
  -- it through World:money()/setMoney().  Using save.money here made the
  -- money box display ¥0 even when the player had cash in Crystal saves.
  SPECIAL.delveMoney=function(game)
    local world=game and game.world
    if world and type(world.money)=="function" then
      local ok,value=pcall(world.money,world,0)
      if ok then return tonumber(value) or 0 end
    end
    local save=game and game.save
    if save and save.player and save.player.money~=nil then
      return tonumber(save.player.money) or 0
    end
    return tonumber(save and save.money) or 0
  end

  SPECIAL.setDelveMoney=function(game,value)
    value=math.max(0,math.floor(tonumber(value) or 0))
    local world=game and game.world
    if world and type(world.setMoney)=="function" then
      local ok=pcall(world.setMoney,world,0,value)
      if ok then return end
    end
    local save=game and game.save
    if not save then return end
    save.player=save.player or {}
    save.player.money=value
    -- Keep a compatibility alias in sync only if an environment already
    -- supplies one; Crystal's persistent wallet remains save.player.money.
    if save.money~=nil then save.money=value end
  end

  local function openStarterMenu(game,startDepth)
    startDepth=math.max(1,math.floor(tonumber(startDepth) or 1))
    mod.ui.push(game,PARTNER_SCREEN,{onDone=function(species)
      if not species then return end
      local money=function() return SPECIAL.delveMoney(game) end
      game.stack:push(TextBox.new(game,
        "Entry fee: ¥"..tostring(2500)..".\nStart this delve?",nil,{
          money=money,moneyWithChoice=true,defaultNo=true,
          choice=function(yes)
            if not yes then return end
            local have=money()
            if have<2500 then
              return showPages(game.world,{"You don't have enough money.","A delve costs ¥"..tostring(2500).."."})
            end
            SPECIAL.setDelveMoney(game,have-2500)
            Sound.dropPressSfx()
            if game.world and game.world.playSfxNamed then game.world:playSfxNamed("Sfx_Transaction") end
            showPages(game.world,{"Good luck."},function()
              beginDelve(game,species,nil,startDepth)
            end)
          end,
        }))
    end})
  end

  -- Co-op keeps each player's rental and wallet local while sharing the
  -- deterministic run seed/depth. The fee is deducted only once both sides
  -- have locked in a rental and the host begins the run.
  SPECIAL.prepareCoopStarter=function(game,startDepth,onReady)
    startDepth=math.max(1,math.floor(tonumber(startDepth) or 1))
    mod.ui.push(game,PARTNER_SCREEN,{onDone=function(species)
      if not species then if onReady then onReady(nil) end return end
      local have=SPECIAL.delveMoney(game)
      if have<2500 then
        return showPages(game.world,{"You don't have enough money.","A co-op delve costs ¥2500."},function()
          if onReady then onReady(nil) end
        end)
      end
      game.stack:push(TextBox.new(game,"Entry fee: ¥2500.\nReady for co-op?",nil,{
        money=function() return SPECIAL.delveMoney(game) end,moneyWithChoice=true,defaultNo=true,
        choice=function(yes) if onReady then onReady(yes and species or nil) end end,
      }))
    end})
  end
  SPECIAL.startCoopRun=function(game,species,seed,startDepth)
    local have=SPECIAL.delveMoney(game)
    if have<2500 then
      showPages(game.world,{"Your co-op delve could not start.","You no longer have ¥2500."})
      return false
    end
    SPECIAL.setDelveMoney(game,have-2500)
    Sound.dropPressSfx()
    if game.world and game.world.playSfxNamed then game.world:playSfxNamed("Sfx_Transaction") end
    local ds=pdSave(game); ds.coopRun=true; ds.coopRelicActive=false
    ds.coopExpeditionId="DD-"..tostring(tonumber(seed) or 0).."-"..tostring(math.floor(tonumber(startDepth) or 1))
    beginDelve(game,species,seed,startDepth)
    return true
  end

  local function openRules(game)
    showPages(game.world,{
      "The old museum closed after a sinkhole opened beneath the building.",
      "Survey crews found a shifting cave network below it, packed with fossils and supplies.",
      "So instead of tearing the place down, Pewter reopened it as a base for Delvers.",
      "Each expedition costs ¥2500. You can delve again whenever you can afford another entry.",
      "You start each delve with one rental partner at Lv.10 and a small supply kit.",
      "Your delve team can hold three POKéMON. Catch wild ones or recruit a defeated Delver's partner.",
      "A full team can still catch a wild POKéMON. You will choose whether to swap it in.",
      "Wild POKéMON can be escaped from, but getting away down here is harder than usual.",
      "Loose items you find are expedition supplies. They disappear when the delve ends.",
      "Mining finds ride in your DELVE CASE. Check out safely at a REST STOP to bring them home.",
      "B10, B30, and B50 are midpoint camps where you can safely check out.",
      "The first clear of B20 and B40 unlocks a deeper-route key in the RP Exchange.",
      "Bring that key to the threshold stair. It will open the route permanently.",
      "The cave grows unstable as you explore. You will get two warnings before a collapse.",
      "Some floors have special conditions: warp panels, sealed routes, hazards, and other surprises.",
      "Past B20, natural cave gives way to buried constructed halls no survey map explains.",
      "Clearing floors earns Research Points. Deeper strata award more RP per floor.",
      "Spend RP at this desk on useful supplies for your normal adventure.",
      "Bring fossils to my scientist associate upstairs. He handles restoration and revival.",
    })
  end

  local function receptionist(game)
    local world=game.world; local s=pdSave(game)
    if s.active then return showPages(world,{"Your active delve is still underway."}) end

    local function startFresh()
      if not s.checkpoint then return openStarterMenu(game) end
      game.stack:push(TextBox.new(game,"Abandon saved delve\nand start over?",nil,{
        defaultNo=true,
        choice=function(yes)
          if yes then
            s.checkpoint=nil
            if SPECIAL.COOP and SPECIAL.COOP.checkpointChanged then SPECIAL.COOP.checkpointChanged(game) end
            openStarterMenu(game)
          end
        end,
      }))
    end

    local function openResearchExchange(back)
      -- Research Points buy a deliberately small set of useful vanilla
      -- adventure items.  Mining/trader loot stays separate so the RP counter
      -- has its own identity instead of duplicating ordinary delve finds.
      local stock={
        {id="FULL_HEAL",cost=8},
        {id="MAX_REPEL",cost=10},
        {id="MAX_POTION",cost=12},
        {id="MAX_REVIVE",cost=15},
        {id="PP_UP",cost=20},
        {id="LEFTOVERS",cost=40},
        {id="LUCKY_EGG",cost=50},
      }
      if s.worksKeyAvailable and not s.worksUnlocked
          and (game.save.inventory[SPECIAL.WORKS_KEY] or 0)<1 then
        stock[#stock+1]={id=SPECIAL.WORKS_KEY,cost=100}
      end
      if s.megalithKeyAvailable and not s.megalithUnlocked
          and (game.save.inventory[SPECIAL.MEGALITH_KEY] or 0)<1 then
        stock[#stock+1]={id=SPECIAL.MEGALITH_KEY,cost=200}
      end
      local items={}
      for _,row in ipairs(stock) do
        local def=game.data.items and game.data.items[row.id]
        if def then
          local itemId,cost,name=row.id,row.cost,def.name or row.id
          items[#items+1]={label=name.."  "..tostring(cost).."RP",onSelect=function()
            local ps=pdSave(game)
            local have=tonumber(ps.researchPoints) or 0
            if have<cost then
              return showPages(world,{"You need "..tostring(cost).." RP for that.","Current balance: "..tostring(have).." RP."})
            end
            if not Bag.add(game.save,itemId,1,game.data) then
              return showPages(world,{"Your bag cannot hold it right now."})
            end
            ps.researchPoints=have-cost
            Sound.play(game.data,"Sfx_Item")
            showPages(world,{"You traded "..tostring(cost).." RP for "..name..".","Research balance: "..tostring(ps.researchPoints).." RP."})
          end}
        end
      end
      items[#items+1]={label="BACK",onSelect=function() if back then back() end end}
      local rpNow=tonumber(pdSave(game).researchPoints) or 0
      game.stack:push(Menu.new(game,items,{tx=5,ty=1,tw=15,rowStep=2,cancelable=true,maxVisible=7,
        title="RP "..tostring(rpNow)}))
    end

    local function openMenu()
      local items={}
      if s.checkpoint and s.checkpoint.nextFloor then
        items[#items+1]={label="CONTINUE B"..tostring(s.checkpoint.nextFloor),onSelect=function()
          resumeCheckpoint(game)
        end}
      end
      items[#items+1]={label=s.checkpoint and "NEW DELVE" or "START DELVE",onSelect=startFresh}
      items[#items+1]={label="CO-OP DELVE",onSelect=function() SPECIAL.COOP.openMenu(game) end}
      items[#items+1]={label="RP EXCHANGE",onSelect=function() openResearchExchange(openMenu) end}
      items[#items+1]={label="DELVE RULES",onSelect=function() openRules(game) end}
      items[#items+1]={label="RECORDS",onSelect=function()
        local ps=pdSave(game)
        showPages(world,{
          "DEEPEST: B"..tostring(ps.deepest or 0).."\nCATALOG: "..tostring(Fossils.catalogueCount(ps)).." / "..tostring(Fossils.catalogueSize()),
          "COMPLETE SETS: "..tostring(Fossils.completeSetCount(ps)).."\nREVIVED: "..tostring(Fossils.revivedCount(ps)),
          "RESEARCH: "..tostring(Fossils.researchPoints(ps)).." RP",
        })
      end}
      game.stack:push(Menu.new(game,items,{tx=7,ty=1,tw=13,rowStep=2,cancelable=true,maxVisible=7}))
    end

    if s.freshRosterReady then
      s.freshRosterReady=nil
      showPages(world,{"That delve is over. I have a fresh rental roster ready for you."},openMenu)
    elseif s.checkpoint and s.checkpoint.nextFloor then
      showPages(world,{"Your checkpoint is safe. B"..tostring(s.checkpoint.nextFloor).." is waiting when you are."},openMenu)
    elseif not s.heardMuseumIntro then
      s.heardMuseumIntro=true
      showPages(world,{
        "Welcome in. Funny enough, this used to be the old Pewter Museum.",
        "We closed for good after a sinkhole opened under the foundation.",
        "Then the survey crews climbed down and found an entire cave network beneath us.",
        "Rare minerals, old equipment, fossils... enough that sealing it back up felt like a waste.",
        "So Pewter reopened the building as a base for people willing to explore it.",
        "We call them Delvers. You rent one partner from us before heading below.",
        "Down there you can build a team of up to three POKéMON as you go.",
        "Push deeper, scavenge what you need, and keep an eye out for anything worth bringing home.",
        "Most loose supplies belong to the expedition, but anything you recover while mining can come back with you.",
        "Each floor you clear also earns Research Points. I trade those for useful supplies here at the desk.",
        "And if you bring back fossils, talk to my scientist associate upstairs.",
        "He's been waiting a long time for a chance to make those old displays mean something again.",
      },openMenu)
    else
      showPages(world,{"Welcome back. Ready to go on a delve?"},openMenu)
    end
  end

  -- Floor encounters ------------------------------------------------------------
  local function itemName(game,id)
    return (game.data.items and game.data.items[id] and game.data.items[id].name) or id
  end
  local function pickupLoot(game,e)
    local id=e and e.item; if not id then return end
    local def=game.data.items and game.data.items[id]
    local ok=Bag.add(game.save,id,1,game.data)
    if not ok then return showPages(game.world,{"Your PACK is full. You left it there."}) end
    removeEntity(game,e)
    if game.world.playSfxNamed then game.world:playSfxNamed("Sfx_Item") else Sound.play(game.data,"Sfx_Item") end
    local player=(game.save.player and game.save.player.name) or "PLAYER"
    local pocket=(def and def.pocket) or "ITEM"
    local ptext=(pocket=="BALL" and "BALL POCKET") or (pocket=="TM_HM" and "TM POCKET") or "ITEM POCKET"
    showPages(game.world,{
      player.." found\n"..itemName(game,id).."!",
      "Put it in the\n"..ptext..".",
    },function()
      -- Picking up a ground item spends a dungeon turn just like taking a
      -- step, so roaming wild Pokemon get one movement action too.
      if game.world and game.world.pewterDungeonMonsterTurn then
        game.world:pewterDungeonMonsterTurn()
      end
    end)
  end

  local function shelfInteract(game,e)
    local world=game.world
    if e.shelfItem and not e.used then
      local id=e.shelfItem
      local ok=Bag.add(game.save,id,1,game.data)
      if not ok then return showPages(world,{"Your PACK is full. The item stays put."}) end
      e.used=true
      if SPECIAL.COOP then SPECIAL.COOP.entityState(game,e) end
      if world.playSfxNamed then world:playSfxNamed("Sfx_Item") else Sound.play(game.data,"Sfx_Item") end
      local pages={
        (e.propKind=="equipment") and "You check the old field equipment." or "You sort through the scattered papers.",
        "Found "..itemName(game,id).."!",
      }
      for _,page in ipairs(e.shelfPages or {}) do pages[#pages+1]=page end
      showPages(world,pages)
      return
    end
    if e.shelfPages and #e.shelfPages>0 then return showPages(world,e.shelfPages) end
    showPages(world,{e.shelfNote or "Nothing useful remains here."})
  end

  local function healer(game,e)
    local world=game.world
    local coopHealing=SPECIAL.COOP and SPECIAL.COOP.isRunActive and SPECIAL.COOP.isRunActive()
    if e.used and not coopHealing then
      return showPages(world,{"That's all I have.\nGood luck below."})
    end
    showPages(world,{
      "Rough trip so far?\nLet me look.",
      "I'll patch your\npartners up.",
    },function()
      healParty(game.save)
      -- In co-op the rest-stop attendant is a shared recovery service, not a
      -- one-use pickup. Either Delver can heal whenever they speak to her, and
      -- one player's visit never consumes the attendant for the other.
      if not coopHealing then
        e.used=true
        if SPECIAL.COOP then SPECIAL.COOP.entityState(game,e) end
      end
      require("src.core.Music").playOnce(game.data,"Music_HealPokemon")
      showPages(world,{"There. All better!\nWatch your step."})
    end)
  end

  local function trader(game,e)
    local world=game.world
    if e.used then return showPages(world,{"That's all I have. Safe travels."}) end

    -- What a trader wants and what they offer are rolled independently. Two
    -- Delvers can therefore ask for the same POTION and still have very
    -- different stock, which makes each encounter worth checking.
    local wants={"POTION","ANTIDOTE","PARLYZ_HEAL","AWAKENING","BERRY",
      "FRESH_WATER","SUPER_POTION","ETHER","SODA_POP","X_ATTACK"}
    -- Common utility rewards get duplicate tickets; stronger drinks stay
    -- single-entry so SUPER POTION / SODA POP / LEMONADE are a little rarer.
    local rewards={"ANTIDOTE","ANTIDOTE","SUPER_POTION",ITEM_DELVE_BALL,ITEM_DELVE_BALL,
      "BERRY","BERRY","GOLD_BERRY","FRESH_WATER","FRESH_WATER","SODA_POP","LEMONADE",
      "ETHER","ETHER",GEAR_BOOTS,GEAR_PP_CHARM,GEAR_TRAP_WARD,SPECIAL.ESCAPE_LENS,
      SPECIAL.FOSSIL_SCANR,SPECIAL.TRAP_SCANR,"RARE_CANDY",SPECIAL.ESCAPE_HATCH}
    local gi=((tonumber(e.tradeGiveIndex) or 1)-1)%#wants+1
    for step=0,#wants-1 do
      local idx=((gi-1+step)%#wants)+1
      if (game.save.inventory[wants[idx]] or 0)>0 then gi=idx break end
    end
    local give=wants[gi]
    local ri=((tonumber(e.tradeGetIndex) or 1)-1)%#rewards+1
    local get=rewards[ri]
    if get==give then get=rewards[(ri%#rewards)+1] end
    local getQty=(get==ITEM_DELVE_BALL) and 2 or 1
    local giveName=itemName(game,give); local getName=itemName(game,get)

    if (game.save.inventory[give] or 0)<1 then
      return showPages(world,{"I'm looking for a "..giveName..".","I've got "..getName.." if you find one."})
    end
    local rewardText=(getQty>1 and tostring(getQty).." " or "")..getName
    showPages(world,{"I could use your "..giveName..".","I'll trade you "..rewardText..". Deal?"},function()
      game.stack:push(Menu.new(game,{
        {label="YES",onSelect=function()
          Bag.remove(game.save,give,1)
          Bag.add(game.save,get,getQty,game.data)
          e.used=true
          if SPECIAL.COOP then SPECIAL.COOP.entityState(game,e) end
          Sound.play(game.data,"Sfx_Item")
          showPages(world,{"Deal. Hope it helps down there."})
        end},
        {label="NO",onSelect=function() end},
      },{tx=12,ty=8,tw=8,rowStep=2,cancelable=true}))
    end)
  end

  local function damageMon(mon,fraction)
    if not mon then return end
    local dmg=math.max(1,math.floor((mon.maxHp or 1)*(fraction or .10)))
    mon.hp=math.max(1,(mon.hp or 1)-dmg)
  end

  local function newChaosMap(seed)
    local dirs={"up","down","left","right"}
    local r=rng(seed or 1)
    for i=#dirs,2,-1 do
      local j=r(i); dirs[i],dirs[j]=dirs[j],dirs[i]
    end
    -- Never leave all four directions unchanged.
    if dirs[1]=="up" and dirs[2]=="down" and dirs[3]=="left" and dirs[4]=="right" then
      dirs[1],dirs[2]=dirs[2],dirs[1]
    end
    return {up=dirs[1],down=dirs[2],left=dirs[3],right=dirs[4]}
  end

  local function trapSfx(world,kind,after)
    local id=({BOULDER="Sfx_Tackle",POISON="Sfx_Poison",BLINDER="Sfx_BallPoof",
      CHAOS="Sfx_Psychic",SLEEP="Sfx_Snore",SLOW="Sfx_Kinesis2",WARP="Sfx_WarpTo",
      RUST="Sfx_Screech"})[kind]
    -- A-button/menu confirmation can otherwise win the same audio channel and
    -- make a trap sound effectively silent. Clear that UI press first.
    if id then Sound.dropPressSfx() end
    if id and world and world.playSfxNamed then world:playSfxNamed(id) end
    if after and world and world.playSfxNamed then world:playSfxNamed(after) end
  end

  local function triggerTrap(game,trap,label,onDone)
    local world=game.world
    trap=trap or {type="BOULDER"}
    trap.revealed=true
    local lead=game.save.party and game.save.party[1]

    if lead and lead.item==GEAR_TRAP_WARD then
      lead.item=nil
      return showPages(world,{label or "A hidden trap snaps shut!","The WARD CHARM shattered instead!"})
    end
    local evadeRoll=rng(floorSeed(pdSave(game),(floorState and floorState.depth) or 1)
      +(trap.x or 0)*97+(trap.y or 0)*193)(100)
    if lead and lead.item==GEAR_BOOTS and evadeRoll<=35 then
      return showPages(world,{label or "A hidden trap snaps shut!","MINER BOOTS kept you clear!"})
    end

    local ds=pdSave(game)
    local kind=trap.type or "BOULDER"
    trapSfx(world,kind)
    local function done(pages,callback)
      showPages(world,pages,function()
        if callback then callback() end
        if onDone then onDone() end
      end)
    end
    if kind=="BOULDER" then
      local mon=randomPartyMon(game,true); damageMon(mon,.18)
      done({"A boulder drops from above!",(mon and monName(game,mon) or "A partner").." took a heavy hit!"})
    elseif kind=="POISON" then
      local mon=randomPartyMon(game,true); if mon then mon.status="poison" end
      done({"Poison gas pours from the floor!",(mon and monName(game,mon) or "A partner").." was poisoned!"})
    elseif kind=="BLINDER" then
      ds.blindSteps=80; refreshBlindPipeline(game)
      done({"Black dust bursts into your face!","Your view shrinks for 80 steps!"})
    elseif kind=="CHAOS" then
      ds.chaosSteps=50; ds.nextBattleConfused=true
      ds.chaosMap=newChaosMap(floorSeed(ds,(floorState and floorState.depth) or 1)+601)
      done({"The floor twists under your feet!","Your controls are scrambled!"})
    elseif kind=="SLEEP" then
      local mon=randomPartyMon(game,true); if mon then mon.status="sleep"; mon.statusTurns=4 end
      done({"Sleep spores fill the passage!",(mon and monName(game,mon) or "A partner").." fell asleep!"})
    elseif kind=="SLOW" then
      ds.slowSteps=200
      done({"A sharp pulse echoes through the cave!","Wild POKéMON move twice as fast for 200 steps!"})
    elseif kind=="RUST" then
      local held={}
      for _,mon in ipairs(game.save.party or {}) do if mon.item then held[#held+1]=mon end end
      if #held==0 then
        done({"A rusty mist sprays across your team!","Nothing was being held. Lucky."})
      else
        local rr=rng(floorSeed(ds,(floorState and floorState.depth) or 1)+(trap.x or 0)*331+(trap.y or 0)*733)
        local mon=held[rr(#held)]; local lost=mon.item; mon.item=nil
        done({"Corrosive mist coats your team!",monName(game,mon).." lost its "..itemName(game,lost).."!"})
      end
    elseif kind=="WARP" then
      local choices={}
      for k in pairs(floorState and floorState.walkable or {}) do
        local y=math.floor(k/1024); local x=k-y*1024
        if math.abs(x-world.player.cellX)+math.abs(y-world.player.cellY)>=6 then choices[#choices+1]={x=x,y=y} end
      end
      if #choices>0 then
        local rr=rng(floorSeed(ds,(floorState and floorState.depth) or 1)+(floorState.stability or 0)*43)
        local c=choices[rr(#choices)]
        showPages(world,{"A warp tile flares beneath you!","The cavern lurches sideways!"},function()
          Sound.dropPressSfx()
          if world.playSfxNamed then world:playSfxNamed("Sfx_WarpTo") end
          safeWarp(game,FLOOR,c.x,c.y,"down")
          queuePostWarpMessage(game,{"You rematerialize deeper in the cavern."},"Sfx_WarpFrom")
          if onDone then onDone() end
        end)
      else
        done({"The warp trap fizzled out."})
      end
    end
  end

  local SHORTCUT_PAYMENT_PRIORITY={
    "RARE_CANDY","ELIXER","MAX_ETHER","FULL_HEAL","GOLD_BERRY","ETHER",
    "LEMONADE","SODA_POP","FRESH_WATER","SUPER_POTION",ITEM_DELVE_BALL,
    "ANTIDOTE","PARLYZ_HEAL","AWAKENING","POTION","BERRY",
  }

  local function shortcutPayment(game)
    local inv=game and game.save and game.save.inventory or {}
    for _,id in ipairs(SHORTCUT_PAYMENT_PRIORITY) do
      if (tonumber(inv[id]) or 0)>0 then return id end
    end
    return nil
  end

  local function trickster(game,e)
    local world=game.world
    if e.used then return showPages(world,{"Shortcut's gone. Better luck next time."}) end
    local payment=shortcutPayment(game)
    if not payment then
      return showPages(world,{"Psst. I know a shortcut.","But shortcuts aren't free. Come back with something worth trading."})
    end
    local payName=itemName(game,payment)
    showPages(world,{
      "Psst. Want a shortcut? I know these caves. Mostly.",
      "My fee is your "..payName..". I might get you closer to the ladder.",
      "Hand it over?",
    },function()
      game.stack:push(Menu.new(game,{
        {label="YES",onSelect=function()
          if (game.save.inventory[payment] or 0)<1 then
            return showPages(world,{"Hey, where'd the "..payName.." go? No payment, no shortcut."})
          end
          Bag.remove(game.save,payment,1)
          e.used=true
          if SPECIAL.COOP then SPECIAL.COOP.entityState(game,e) end
          Sound.dropPressSfx()
          if world.playSfxNamed then world:playSfxNamed("Sfx_Transaction") end
          local rr=rng(floorSeed(pdSave(game),(floorState and floorState.depth) or 1)+(e.index or 0)*7919)
          local outcome=rr(3)
          if outcome<=2 then
            local d=floorState and floorState.descent; local choices={}; local best=-1
            for k in pairs((floorState and floorState.walkable) or {}) do
              local y=math.floor(k/1024); local x=k-y*1024
              local occupied=floorState.entityAt and floorState.entityAt[k]
              if d and not occupied and not (x==d.x and y==d.y) then
                local dist=math.abs(x-d.x)+math.abs(y-d.y)
                if outcome==1 then
                  if dist>=1 and dist<=3 then choices[#choices+1]={x=x,y=y,d=dist} end
                else
                  if dist>best then best=dist; choices={{x=x,y=y,d=dist}}
                  elseif dist==best then choices[#choices+1]={x=x,y=y,d=dist} end
                end
              end
            end
            if #choices>0 then
              local c=choices[rr(#choices)]
              Sound.dropPressSfx()
              if world.playSfxNamed then world:playSfxNamed("Sfx_WarpTo") end
              if outcome==1 then
                queuePostWarpMessage(game,{"There. That should save you some walking."},"Sfx_WarpFrom")
              else
                queuePostWarpMessage(game,{"Heh. Wrong way.","You're a long way from that ladder now!"},"Sfx_WarpFrom")
              end
              safeWarp(game,FLOOR,c.x,c.y,"down")
              return
            end
          end
          local types={"BOULDER","POISON","BLINDER","CHAOS","SLEEP","SLOW","RUST"}
          triggerTrap(game,{type=types[rr(#types)],x=e.x,y=e.y},"He grins. CLICK!",function()
            showPages(world,{"Ha! You fell for it!","What a sucker. Heh heh!"})
          end)
        end},
        {label="NO",onSelect=function() showPages(world,{"Smart. Probably."}) end},
      },{tx=12,ty=8,tw=8,rowStep=2,cancelable=true}))
    end)
  end

  local function fossil(game,e)
    local world=game.world
    if e.miningCollapsed then
      return showPages(world,{"The fossil rock is already ruined."})
    end
    showPages(world,{
      "There's a fossil fragment sealed inside this rock.",
      "Think you can free it before the wall gives out?",
    },function()
      game.stack:push(Menu.new(game,{
        {label="YES",onSelect=function() Fossils.openMining(game,e) end},
        {label="NO",onSelect=function() end},
      },{tx=12,ty=8,tw=8,rowStep=2,cancelable=true}))
    end)
  end

  local function confirmExtract(game)
    local world=game.world
    local nextFloor=((floorState and floorState.depth) or pdSave(game).floor or 1)+1
    showPages(world,{
      "I can take you\nto the museum.",
      "Your return point\nwill be B"..tostring(nextFloor)..".",
      "Leave the delve\nfrom this rest stop?",
    },function()
      game.stack:push(Menu.new(game,{
        {label="YES",onSelect=function() checkpointExit(game) end},
        {label="NO",onSelect=function() end},
      },{tx=12,ty=8,tw=8,rowStep=2,cancelable=true}))
    end)
  end

  SPECIAL.handleThresholdExit=function(game)
    local world=game.world
    local s=pdSave(game)
    local depth=(floorState and floorState.depth) or s.floor or 1
    depth=math.floor(tonumber(depth) or 1)

    local function addThresholdRp()
      if floorState and not floorState.thresholdRpAwarded then
        local rp=1+math.floor(math.max(0,depth-1)/20)
        s.researchPoints=(tonumber(s.researchPoints) or 0)+rp
        s.runRpEarned=(tonumber(s.runRpEarned) or 0)+rp
        floorState.thresholdRpAwarded=true
      end
    end

    local function completeDelve()
      addThresholdRp()
      Sound.dropPressSfx()
      Sound.play(game.data,"Sfx_Fanfare")
      local notice=nil
      if depth==20 and not s.worksKeyAvailable and not s.worksUnlocked then
        s.worksKeyAvailable=true
        notice="WORKS KEY unlocked!\n100 RP in RP EXCHANGE.\nCarry it on a delve.\nIt opens the route past B20."
      elseif depth==40 and not s.megalithKeyAvailable and not s.megalithUnlocked then
        s.megalithKeyAvailable=true
        notice="MEGALITH KEY unlocked!\n200 RP in RP EXCHANGE.\nCarry it on a delve.\nIt opens the route past B40."
      end
      showPages(world,{"DELVE COMPLETE!","DELVE CASE secured."},function()
        finishRun(game,nil,true,{recapAtDesk=true,keyNotice=notice})
      end)
    end

    if depth==60 then return completeDelve() end

    local keyId=(depth==20) and SPECIAL.WORKS_KEY or SPECIAL.MEGALITH_KEY
    local keyName=(depth==20) and "WORKS KEY" or "MEGALITH KEY"
    local unlockField=(depth==20) and "worksUnlocked" or "megalithUnlocked"
    local nextDepth=(depth==20) and 21 or 41
    local tempQty=(game.save.inventory and game.save.inventory[keyId]) or 0
    local backupQty=(s.inventoryBackup and s.inventoryBackup[keyId]) or 0

    if tempQty<1 and backupQty<1 then return completeDelve() end

    showPages(world,{"The lower route is sealed.",keyName.." fits. Use it?"},function()
      game.stack:push(Menu.new(game,{
        {label="YES",onSelect=function()
          if game.save.inventory and (game.save.inventory[keyId] or 0)>0 then
            Bag.remove(game.save,keyId,1)
          end
          if s.inventoryBackup and (s.inventoryBackup[keyId] or 0)>0 then
            s.inventoryBackup[keyId]=s.inventoryBackup[keyId]-1
            if s.inventoryBackup[keyId]<=0 then
              s.inventoryBackup[keyId]=nil
              for i,oid in ipairs(s.bagOrderBackup or {}) do
                if oid==keyId then table.remove(s.bagOrderBackup,i); break end
              end
            end
          end
          s[unlockField]=true
          Sound.dropPressSfx()
          if world and world.playSfxNamed then world:playSfxNamed("Sfx_Strength") end
          showPages(world,{keyName.." turns in the lock.","B"..tostring(nextDepth).." route unlocked!"},function()
            -- Rebuild the same threshold depth as an ordinary rest stop. The
            -- existing three-NPC rest-stop path is already proven stable.
            local fs,err=generateFloor(game,depth)
            if not fs then return finishRun(game,"FLOOR ERROR:\n"..tostring(err),false) end
            safeWarp(game,FLOOR,fs.start.x,fs.start.y,"down")
          end)
        end},
        {label="NO",onSelect=function() end},
      },{tx=12,ty=8,tw=8,rowStep=2,cancelable=true}))
    end)
  end

  mod.content.screens:register("PewterDungeonBossFlash",{
    new=function(game,opts)
      opts=opts or {}
      local state={game=game,isOpaque=false,timer=.32,onDone=opts.onDone}
      function state:update(dt)
        self.timer=self.timer-(tonumber(dt) or 0)
        if self.timer<=0 then game.stack:pop(); if self.onDone then self.onDone() end end
      end
      function state:draw()
        love.graphics.setColor(0,0,0,1)
        love.graphics.rectangle("fill",0,0,160,144)
      end
      return state
    end,
  })

  -- Let the floor-drop cue breathe for a few frames before changing maps.
  -- DEV65 fired the sound and warp in the same frame, which could cut the SFX.
  mod.content.screens:register("PewterDungeonFloorDrop",{
    new=function(game,opts)
      opts=opts or {}
      local state={game=game,isOpaque=false,timer=.34,onDone=opts.onDone}
      Sound.waitSfxDone()
      Sound.play(game.data,"Sfx_Kinesis")
      function state:update(dt)
        self.timer=self.timer-(tonumber(dt) or 0)
        if self.timer<=0 then
          game.stack:pop()
          if self.onDone then self.onDone() end
        end
      end
      function state:draw() end
      return state
    end,
  })

  -- Post-win swap screen: use the same clean two-pane language as BFR.
  -- Left pane is the roster, upper-right is the focused Pokemon/type preview,
  -- lower-right is the action menu. No explanatory prose is drawn into the
  -- roster panes, which keeps long names/sprites from colliding with controls.
  mod.content.screens:register(SWAP_SCREEN,{
    new=function(game,opts)
      opts=opts or {}
      local candidate=opts.candidate
      local Theme=require("src.ui.Theme")
      local SummaryMenu=require("src.ui.gen2.SummaryMenu")
      local state={game=game,isOpaque=false,cursor=1,actionMenu=nil,phase="enemy"}

      local function party()
        game.save.party=game.save.party or {}
        return game.save.party
      end

      local function closeAction() state.actionMenu=nil end

      local function stats(mon)
        if not mon then return end
        game.stack:push(SummaryMenu.new(game,{
          mon=mon,save=game.save,onClose=function()
            if game.stack and game.stack:top() then game.stack:pop() end
          end,
        }))
      end

      local function finishMessage(mon)
        game.stack:pop()
        if game.world and mon then
          showPages(game.world,{monName(game,mon).." joined the delve!"})
        end
      end

      local function addCandidate()
        if not candidate then return end
        local replacement=deep(candidate); healMon(replacement)
        local p=party(); p[#p+1]=replacement
        finishMessage(replacement)
      end

      local function replaceSlot(slot)
        if not candidate then return end
        local p=party(); local replacement=deep(candidate); healMon(replacement)
        local old=p[slot]
        -- Delver Gear belongs to the expedition slot rather than the defeated
        -- trainer, so preserve it when the incoming Pokemon has no held item.
        if old and old.item and not replacement.item then replacement.item=old.item end
        p[slot]=replacement
        finishMessage(replacement)
      end

      local function openEnemyAction()
        state.actionMenu=Menu.new(game,{
          {label="STATS",keepOpen=true,onSelect=function() stats(candidate) end},
          {label=(#party()<3 and "TAKE" or "SWAP"),keepOpen=true,onSelect=function()
            closeAction()
            if #party()<3 then addCandidate()
            else state.phase="player"; state.cursor=1 end
          end},
          {label="BACK",keepOpen=true,onSelect=closeAction},
        },{tx=11,ty=11,tw=9,th=7,cancelable=false,rowStep=2})
      end

      local function openPlayerAction(i)
        local mon=party()[i]
        state.actionMenu=Menu.new(game,{
          {label="STATS",keepOpen=true,onSelect=function() stats(mon) end},
          {label="RETURN",keepOpen=true,onSelect=function() closeAction(); replaceSlot(i) end},
          {label="BACK",keepOpen=true,onSelect=closeAction},
        },{tx=11,ty=11,tw=9,th=7,cancelable=false,rowStep=2})
      end

      function state:update(dt)
        local input=game.input; if not input then return end
        if self.actionMenu then
          if input:wasPressed("b") then closeAction(); return end
          self.actionMenu:update(dt); return
        end

        local list=(self.phase=="enemy") and {candidate} or party()
        local count=#list+1
        if input:wasPressed("up") then
          self.cursor=self.cursor-1; if self.cursor<1 then self.cursor=count end
        elseif input:wasPressed("down") then
          self.cursor=self.cursor+1; if self.cursor>count then self.cursor=1 end
        elseif input:wasPressed("b") then
          if self.phase=="player" then self.phase="enemy"; self.cursor=1
          else game.stack:pop() end
        elseif input:wasPressed("a") then
          if self.cursor<=#list then
            if self.phase=="enemy" then openEnemyAction() else openPlayerAction(self.cursor) end
          else
            if self.phase=="player" then self.phase="enemy"; self.cursor=1
            else game.stack:pop() end
          end
        end
      end

      function state:draw()
        local list,title,footer
        if self.phase=="enemy" then
          list={candidate}; title="SWAP IN"; footer="CANCEL"
        else
          list=party(); title="SWAP OUT"; footer="BACK"
        end
        local focus=(self.cursor<=#list) and list[self.cursor] or nil
        drawPartnerShell(game,focus,self.actionMenu~=nil,title)

        love.graphics.setColor(0,0,0,1)
        local y=38; local step=20
        for i,mon in ipairs(list) do
          if mon then
            if self.cursor==i and not self.actionMenu then Font.drawCode(Theme.cursor,8,y) end
            fitText(monName(game,mon),16,y,64)
          end
          y=y+step
        end
        if self.cursor==#list+1 and not self.actionMenu then Font.drawCode(Theme.cursor,8,y+8) end
        Font.draw(footer,16,y+8)

        if self.actionMenu then self.actionMenu:draw() end
      end
      return state
    end,
  })

  local function swapPrompt(game,candidate)
    mod.ui.push(game,SWAP_SCREEN,{candidate=candidate})
  end

  -- Lv.10 starters; B1 opposition begins around the same scale and climbs
  -- roughly one level per floor. Accelerated delve EXP keeps viable partners
  -- near the depth curve without making early encounters automatic losses.
  local function wildLevelForDepth(depth,r)
    depth=math.max(1,math.floor(tonumber(depth) or 1))
    return clamp(8+depth+r(2)-1,8,100)
  end

  local function trainerLevelForDepth(depth,r)
    depth=math.max(1,math.floor(tonumber(depth) or 1))
    return clamp(9+depth+r(2)-1,10,100)
  end

  local pendingMonsterCollision=nil
  local pendingMonsterTurn=false

  local function floorNpcForEntity(world,e)
    if not (world and e) then return nil end
    for _,npc in ipairs(world.npcs or {}) do
      if npc.def and npc.def.index==e.index then return npc end
    end
    return nil
  end

  local pendingDelveBattleFocus=nil
  local activeDelveBattleFocus=nil

  local function sanitizeDelveMonMoves(game,mon)
    if not mon then return end
    local kept={}
    for _,m in ipairs(mon.moves or {}) do
      if vanillaDelveMove(game,m.id) then kept[#kept+1]=m end
    end
    mon.moves=kept
    if #kept<2 then
      curateDelveMoves(game,mon,mon.level or 10)
    end
  end

  -- trainer.party is randomized by PokeSurvive through the trainer.party hook
  -- inside Battle.new, so the table we originally passed may no longer be the
  -- Pokemon the player actually fought. Capture the constructed enemy party
  -- from battle.started and attach it to this floor entity for the swap screen.
  mod.events:on("battle.started",function(ev)
    local game=mod.game
    if not (game and isActive(game) and game.world and game.world.map
        and game.world.map.id==FLOOR and ev and ev.battle) then return end
    local battle=ev.battle
    -- Only the original clerk rental is curated on the player's side. Pokemon
    -- captured or recruited during the delve keep every legal move they learn.
    for _,mon in ipairs(battle.party or {}) do
      if mon._pewterDungeonRental then sanitizeDelveMonMoves(game,mon) end
    end
    -- PokeSurvive can replace a Delver trainer's prepared party inside
    -- Battle.new. Roll missing types on the actual opponents after that hook.
    for _,mon in ipairs(battle.enemyParty or {}) do
      if not mon._ddIndividualTypes then mod._ddRollTypes(game,mon) end
      sanitizeDelveMonMoves(game,mon)
    end
    if battle.wild and battle.enemy and not battle.enemy._ddIndividualTypes then
      mod._ddRollTypes(game,battle.enemy)
    end
    if pendingDelveBattleFocus and battle.enemyParty and battle.enemyParty[1] then
      pendingDelveBattleFocus.lastBattleMon=deep(battle.enemyParty[1])
    end
  end)

  -- The Gen-II battle transition redraws/captures the overworld several times.
  -- Darkness masks are not guaranteed to be part of every one of those passes,
  -- so hiding merely "distant" actors can still flash their silhouettes. During
  -- a Delve transition show only the opponent being engaged; every other dungeon
  -- actor is filtered out until the battle returns.
  local function beginDelveBattle(world,opts,focusEntity,onDone)
    if not world then return false end
    local previous=world.spriteFilter
    local focusIndex=focusEntity and focusEntity.index
    local function battleFocusFilter(npc)
      if previous and not previous(npc) then return false end
      return focusIndex ~= nil and npc and npc.def and npc.def.index==focusIndex
    end
    world.spriteFilter=battleFocusFilter
    pendingDelveBattleFocus=focusEntity
    activeDelveBattleFocus=focusEntity
    if SPECIAL.COOP and SPECIAL.COOP.battleState then SPECIAL.COOP.battleState(world.game,focusEntity,true) end
    local started=world:startBattle(opts,function(outcome)
      if world.spriteFilter==battleFocusFilter then world.spriteFilter=previous end
      pendingDelveBattleFocus=nil
      activeDelveBattleFocus=nil
      if SPECIAL.COOP and SPECIAL.COOP.battleState then SPECIAL.COOP.battleState(world.game,focusEntity,false) end
      if onDone then onDone(outcome) end
    end)
    pendingDelveBattleFocus=nil
    if not started then
      activeDelveBattleFocus=nil
      if SPECIAL.COOP and SPECIAL.COOP.battleState then SPECIAL.COOP.battleState(world.game,focusEntity,false) end
      if world.spriteFilter==battleFocusFilter then world.spriteFilter=previous end
    end
    return started
  end

  local function startMonsterBattle(game,e)
    if not (game and e and e.active) or e.battling then return end
    local world=game.world
    local me=tostring((game.save.player and game.save.player.name) or "DELVER")
    if e.coopEngagedBy and e.coopEngagedBy~=me then
      return showPages(world,{speciesName(game,e.species).." is battling "..tostring(e.coopEngagedBy).."."},function()
        if SPECIAL.COOP and SPECIAL.COOP.offerSpectate then SPECIAL.COOP.offerSpectate(game,e,true) end
      end)
    end
    local mon=buildMon(game,e.species,e.level)
    if not mon then return end
    e.battling=true
    e.coopEngagedBy=me; e.coopBattle=true
    if SPECIAL.COOP then SPECIAL.COOP.entityEngage(game,e,"battle") end
    local npc=floorNpcForEntity(world,e)
    if npc then npc.moving=false; npc.targetX=nil; npc.targetY=nil end
    beginDelveBattle(world,{wild=mon,battleType=1},e,function(outcome)
      e.battling=nil
      if #(game.save.party or {})==0 or outcome=="lose" then return loseRun(game,"YOUR DELVE ENDED.") end
      if e.boss then
        if outcome=="win" then
          removeEntity(game,e)
          local rr=rng(floorSeed(pdSave(game),(floorState and floorState.depth) or 1)+(e.index or 0)*1543)
          local gotFossil=(e.bossTier=="major") or (rr(100)<=40); local root,part
          if gotFossil then
            root,part=Fossils.rollDeposit(rr,(floorState and floorState.depth) or 1)
            local bossDepth=(floorState and floorState.depth) or 1
            Fossils.addRunFossil(game,root,part,bossDepth,95)
            SPECIAL.COOP.shareFind(game,{kind="fossil",root=root,part=part,depth=bossDepth,integrity=95})
          end
          -- Battle callbacks can fire while the battle state's white teardown
          -- frame is still on-screen. Defer the guardian aftermath until the
          -- overworld is actually back so the text sits over the dungeon.
          local ds=pdSave(game)
          ds.pendingBossAftermath={
            frames=2,gotFossil=gotFossil,root=root,part=part,species=e.species,
            floorClear=not (floorState and floorState.bossAlive),
          }
        end
        return
      end
      if outcome=="win" or outcome=="caught" or outcome=="fled" or outcome=="run" then removeEntity(game,e) end
      local ds=pdSave(game)
      if ds.pendingCaughtMon then local caught=ds.pendingCaughtMon; ds.pendingCaughtMon=nil; swapPrompt(game,caught) end
    end)
  end

  -- Player-on-monster contact: ordinary Crystal NPC collision prevents the
  -- player from physically occupying an NPC's cell, so convert a bump into a
  -- pending encounter.  Starting the battle on input.step (rather than from
  -- inside Player:tryMove) avoids re-entering movement code mid-collision.
  mod.hooks:wrap("movement.collision",function(next,allowed,ctx)
    local verdict=next(allowed,ctx)
    local game=mod.game; local world=game and game.world
    if ctx and world and floorState and ctx.mover==world.player then
      local e=floorState.entityAt and floorState.entityAt[(ctx.toY or -999)*1024+(ctx.toX or -999)]
      if e and e.active and e.role=="threshold_miner" then return false end
    end
    if not (verdict==false and ctx and world and world.map and world.map.id==FLOOR
        and floorState and ctx.mover==world.player and isActive(game)) then
      return verdict
    end

    if ctx.reason=="entity" then
      local hitNpc=nil
      for _,npc in ipairs(world.npcs or world.entities or {}) do
        local onCell=(npc.cellX==ctx.toX and npc.cellY==ctx.toY)
        local movingTo=(npc.moving and npc.targetX==ctx.toX and npc.targetY==ctx.toY)
        local role=npc.def and npc.def.pewterRole
        if (onCell or movingTo) and (role=="monster" or role=="trainer") then
          hitNpc=npc; break
        end
      end
      if hitNpc then
        for _,e in ipairs(floorState.entities or {}) do
          if e.active and (e.role=="monster" or e.role=="trainer") and e.index==(hitNpc.def and hitNpc.def.index) then
            local me=tostring((game.save.player and game.save.player.name) or "DELVER")
            if e.coopEngagedBy and e.coopEngagedBy~=me then
              floorState.coopBusyTouch=e
              return false
            end
            if e.role=="monster" then
              pendingMonsterCollision=e
              -- Let the player actually enter an unclaimed roaming Pokemon's
              -- cell; the battle begins after movement completes.
              return true
            end
          end
        end
      end
    elseif ctx.reason=="tile" or ctx.reason=="bounds" then
      -- DEV20 handles blocked/edge turns directly after World:movePlayer
      -- returns, which is reliable even when Gen-II permission checks replace
      -- the target map before Player:tryMove reaches this hook.
    end
    return verdict
  end,920)

  mod.hooks:wrap("input.step",function(next,game,dt)
    local out=next(game,dt)
    if SPECIAL.COOP then SPECIAL.COOP.update(game,dt) end
    local e=pendingMonsterCollision
    pendingMonsterCollision=nil
    pendingMonsterTurn=false
    local busyTouch=floorState and floorState.coopBusyTouch
    if floorState then floorState.coopBusyTouch=nil end
    if busyTouch and busyTouch.active and game and game.world and not game.world:busy() and not game.world.battleActive then
      local who=tostring(busyTouch.coopEngagedBy or (SPECIAL.COOP and SPECIAL.COOP.peerName()) or "your partner")
      if busyTouch.role=="monster" then
        showPages(game.world,{speciesName(game,busyTouch.species).." is battling "..who.."."},function()
          if SPECIAL.COOP and SPECIAL.COOP.offerSpectate then SPECIAL.COOP.offerSpectate(game,busyTouch,true) end
        end)
      else
        showPages(game.world,{"That Delver is battling "..who.."."},function()
          if SPECIAL.COOP and SPECIAL.COOP.offerSpectate then SPECIAL.COOP.offerSpectate(game,busyTouch,true) end
        end)
      end
    end
    if e and e.active and game and game.world and game.world.map
        and game.world.map.id==FLOOR and isActive(game)
        and not game.world.battleActive and not game.world:busy() then
      startMonsterBattle(game,e)
    end
    local s=game and game.save and game.save.pewterDungeon
    local pending=s and s.pendingPostWarpMessage
    if pending and game.world and game.world.map and game.world.map.id==FLOOR
        and not game.world.battleActive then
      pending.frames=(tonumber(pending.frames) or 1)-1
      if pending.frames<=0 and not game.world:busy() then
        s.pendingPostWarpMessage=nil
        if pending.arrivalSfx and game.world.playSfxNamed then
          Sound.dropPressSfx(); game.world:playSfxNamed(pending.arrivalSfx)
        end
        showPages(game.world,pending.pages or {pending.text})
      end
    end
    local bossAfter=s and s.pendingBossAftermath
    if bossAfter and game.world and game.world.map and game.world.map.id==FLOOR
        and not game.world.battleActive then
      bossAfter.frames=(tonumber(bossAfter.frames) or 1)-1
      if bossAfter.frames<=0 and not game.world:busy() then
        s.pendingBossAftermath=nil
        if Sound.playCry and bossAfter.species then pcall(Sound.playCry,game.data,bossAfter.species) end
        mod.ui.push(game,"PewterDungeonBossFlash",{onDone=function()
          if bossAfter.gotFossil then
            showPages(game.world,{"The guardian vanished..."},function()
              Sound.waitSfxDone()
              Sound.play(game.data,"Sfx_Item")
              local partLabel=({HEAD="HEAD",UPPER="U-BODY",LOWER="L-BODY"})[bossAfter.part] or "FOSSIL"
              local last=bossAfter.floorClear and "The ladder beneath it is clear." or "Another guardian remains."
              showPages(game.world,{partLabel.." FOSSIL!","Stored in DELVE CASE.",last})
            end)
          else
            showPages(game.world,{"The guardian vanished...",bossAfter.floorClear and "The ladder beneath it is clear." or "Another guardian remains."})
          end
        end})
      end
    end
    local recap=s and s.pendingDelveRecap
    if recap and game.world and game.world.map and game.world.map.id==LOBBY
        and not game.world.battleActive then
      recap.frames=(tonumber(recap.frames) or 1)-1
      if recap.frames<=0 and not game.world:busy() then
        s.pendingDelveRecap=nil
        local cleared=math.max(1,(tonumber(recap.floor) or 1)-(tonumber(recap.startFloor) or 1)+1)
        local pages={
          "Welcome back.",
          "DELVE REPORT",
          "FLOORS: "..tostring(cleared).."\nRP: +"..tostring(recap.rp or 0),
          "FOSSILS: "..tostring(recap.fossils or 0).."\nITEMS: "..tostring(recap.items or 0),
        }
        if recap.keyNotice then pages[#pages+1]=recap.keyNotice end
        showPages(game.world,pages)
      end
    end
    if s and s.pendingEscapeHatch and game.world and game.world.map
        and game.world.map.id==FLOOR and not game.world.battleActive and not game.world:busy() then
      s.pendingEscapeHatch=nil
      showPages(game.world,{"The ESCAPE HATCH opens beneath you!"},function() advanceFloor(game,false) end)
    end
    return out
  end,920)

  local MOVE_DELTA={
    up={0,-1},down={0,1},left={-1,0},right={1,0},
  }
  local function monsterCellFree(world,e,x,y)
    if not (world and world.map and world.map:inBounds(x,y)
        and world.map:isWalkableCell(x,y) and not world.map:isWaterCell(x,y)) then
      return false
    end
    if floorState and floorState.descent
        and floorState.descent.x==x and floorState.descent.y==y then return false end
    for _,other in ipairs(floorState and floorState.entities or {}) do
      if other~=e and other.active and other.x==x and other.y==y then return false end
    end
    return true
  end

  local function directionToward(world,e,px,py,rr)
    -- Bounded BFS so a pursuing Pokemon can round short cave corners instead
    -- of getting stuck on a greedy X/Y choice. The player cell is a valid goal
    -- but never a normal movement destination: reaching it means battle.
    local dirs={"up","down","left","right"}
    local q={{x=e.x,y=e.y,first=nil,dist=0}}
    local seen={[e.y*1024+e.x]=true}
    local head=1
    while head<=#q do
      local cur=q[head]; head=head+1
      if cur.dist<8 then
        local order={1,2,3,4}
        for i=#order,2,-1 do local j=rr(i); order[i],order[j]=order[j],order[i] end
        for _,oi in ipairs(order) do
          local dir=dirs[oi]; local d=MOVE_DELTA[dir]
          local nx,ny=cur.x+d[1],cur.y+d[2]
          local first=cur.first or dir
          if nx==px and ny==py then return first,(cur.dist==0) end
          local k=ny*1024+nx
          if not seen[k] and monsterCellFree(world,e,nx,ny) then
            seen[k]=true
            q[#q+1]={x=nx,y=ny,first=first,dist=cur.dist+1}
          end
        end
      end
    end
    -- No route around the local obstruction: keep moving rather than freezing.
    for i=#dirs,2,-1 do local j=rr(i); dirs[i],dirs[j]=dirs[j],dirs[i] end
    for _,dir in ipairs(dirs) do
      local d=MOVE_DELTA[dir]
      if monsterCellFree(world,e,e.x+d[1],e.y+d[2]) then return dir,false end
    end
    return nil,false
  end

  local function moveWanderingMonsters(game,targetX,targetY,remoteTurn)
    local world=game and game.world
    local player=world and world.player
    if not (world and floorState) then return end
    remoteTurn=remoteTurn and true or false
    if not remoteTurn and (not player or world.battleActive) then return end
    -- Co-op uses one authoritative roaming simulation. Guests report that a
    -- dungeon turn happened; the host advances the wild Pokemon and replicates
    -- their positions back to both views.  Guest turns include the guest's
    -- actual cell so monsters chase the player who moved, not whichever player
    -- happens to be hosting.  Remote turns are allowed while the host is in a
    -- battle, which prevents the shared world from freezing for the guest.
    if not remoteTurn and SPECIAL.COOP and SPECIAL.COOP.isRunActive() and SPECIAL.COOP.isGuest() then
      SPECIAL.COOP.requestMonsterTurn(game)
      return
    end
    local actorX=tonumber(targetX) or (player and player.cellX)
    local actorY=tonumber(targetY) or (player and player.cellY)
    if actorX==nil or actorY==nil then return end
    floorState.monsterTurn=(floorState.monsterTurn or 0)+1
    local turn=floorState.monsterTurn
    local rr=rng(floorSeed(pdSave(game),floorState.depth)+turn*15485863)

    for _,e in ipairs(floorState.entities or {}) do
      if e.active and e.role=="monster" and not e.battling and not e.coopEngagedBy then
        if (tonumber(e.cooldown) or 0)>0 then e.cooldown=e.cooldown-1 end
        local npc=floorNpcForEntity(world,e)
        -- If the host entered battle while a roamer was midway through an
        -- overworld step, Crystal pauses that NPC animation underneath the
        -- battle.  Guest turns must still advance the shared dungeon, so settle
        -- that hidden step first instead of leaving npc.moving=true forever.
        if npc and remoteTurn and world.battleActive and npc.moving then
          local sx=tonumber(npc.targetX) or tonumber(e.x) or tonumber(npc.cellX)
          local sy=tonumber(npc.targetY) or tonumber(e.y) or tonumber(npc.cellY)
          if sx~=nil and sy~=nil then
            npc.cellX,npc.cellY=sx,sy; npc.px,npc.py=sx*16,sy*16
            e.x,e.y=sx,sy
          end
          npc.targetX,npc.targetY=nil,nil; npc.progress=0; npc.moving=false
        end
        if npc and not npc.moving then
          -- Keep authority synced to the entity that Crystal just finished
          -- animating; e.x/e.y are also updated when a new step begins.
          e.x,e.y=npc.cellX or e.x,npc.cellY or e.y
          local px,py=actorX,actorY
          local dist=math.abs(px-e.x)+math.abs(py-e.y)
          -- Guardian encounters stay planted over the downstairs tile. The
          -- player can step into that occupied cell to challenge them, but the
          -- guardian never wanders away and accidentally exposes the ladder.
          if e.boss then
            if dist==0 and (tonumber(e.cooldown) or 0)<=0 then
              if remoteTurn and SPECIAL.COOP and SPECIAL.COOP.forcePeerMonsterBattle then
                SPECIAL.COOP.forcePeerMonsterBattle(game,e)
              else startMonsterBattle(game,e) end
              return
            end
          else
          -- Adjacency alone is safe. A battle only starts if the two actors
          -- actually share a cell (defensive fallback) or if one side attempts
          -- to move into the other's occupied cell below.
          if dist==0 and (tonumber(e.cooldown) or 0)<=0 then
            if remoteTurn and SPECIAL.COOP and SPECIAL.COOP.forcePeerMonsterBattle then
              SPECIAL.COOP.forcePeerMonsterBattle(game,e)
            else startMonsterBattle(game,e) end
            return
          end

          local dir,touches
          if dist<=4 and (tonumber(e.cooldown) or 0)<=0 then
            dir,touches=directionToward(world,e,px,py,rr)
          else
            dir=e.moveDir
            local d=dir and MOVE_DELTA[dir]
            if not d or not monsterCellFree(world,e,e.x+d[1],e.y+d[2]) then
              local choices={"up","down","left","right"}
              for i=#choices,2,-1 do local j=rr(i); choices[i],choices[j]=choices[j],choices[i] end
              dir=nil
              for _,candidate in ipairs(choices) do
                local cd=MOVE_DELTA[candidate]
                if monsterCellFree(world,e,e.x+cd[1],e.y+cd[2]) then
                  dir=candidate; break
                end
              end
            end
          end

          if touches then
            if floorState.entityAt then floorState.entityAt[e.y*1024+e.x]=nil end
            e.x,e.y=px,py
            if floorState.entityAt then floorState.entityAt[py*1024+px]=e end
            npc.cellX,npc.cellY=px,py; npc.targetX,npc.targetY=nil,nil; npc.moving=false
            npc.px,npc.py=px*16,py*16
            if remoteTurn and SPECIAL.COOP and SPECIAL.COOP.forcePeerMonsterBattle then
              SPECIAL.COOP.forcePeerMonsterBattle(game,e)
            else startMonsterBattle(game,e) end
            return
          elseif dir then
            local d=MOVE_DELTA[dir]
            local tx,ty=e.x+d[1],e.y+d[2]
            e.moveDir=dir
            if tx==px and ty==py then
              if floorState.entityAt then floorState.entityAt[e.y*1024+e.x]=nil end
              e.x,e.y=px,py
              if floorState.entityAt then floorState.entityAt[py*1024+px]=e end
              npc.cellX,npc.cellY=px,py; npc.targetX,npc.targetY=nil,nil; npc.moving=false
              npc.px,npc.py=px*16,py*16
              if remoteTurn and SPECIAL.COOP and SPECIAL.COOP.forcePeerMonsterBattle then
                SPECIAL.COOP.forcePeerMonsterBattle(game,e)
              else startMonsterBattle(game,e) end
              return
            end

            -- SLOW is deliberately dangerous: each player turn lets roamers
            -- cover up to TWO cells. The old implementation simply called this
            -- function twice, but the first call marked the NPC as moving so
            -- the second call was skipped. Resolve the second same-direction
            -- cell here instead so the logical move really is two tiles.
            local ds=pdSave(game)
            local slowStride=(tonumber(ds.slowSteps) or 0)>0
            if slowStride then
              local sx,sy=tx+d[1],ty+d[2]
              if sx==px and sy==py then
                tx,ty=sx,sy
              elseif monsterCellFree(world,e,sx,sy) then
                tx,ty=sx,sy
              end
            end
            if tx==px and ty==py then
              if floorState.entityAt then floorState.entityAt[e.y*1024+e.x]=nil end
              e.x,e.y=px,py
              if floorState.entityAt then floorState.entityAt[py*1024+px]=e end
              npc.cellX,npc.cellY=px,py; npc.targetX,npc.targetY=nil,nil; npc.moving=false
              npc.px,npc.py=px*16,py*16
              if remoteTurn and SPECIAL.COOP and SPECIAL.COOP.forcePeerMonsterBattle then
                SPECIAL.COOP.forcePeerMonsterBattle(game,e)
              else startMonsterBattle(game,e) end
              return
            end
            if floorState.entityAt then
              floorState.entityAt[e.y*1024+e.x]=nil
              floorState.entityAt[ty*1024+tx]=e
            end
            e.x,e.y=tx,ty
            -- Pokemon overworld actors use Crystal's two-frame bounce pose.
            -- Do not rotate their facing with path direction: on these species
            -- sprites that reads as frantic left/right flipping rather than an
            -- idle animation. Translation is still directional.
            if remoteTurn and world.battleActive then
              -- The host's overworld is paused underneath its battle state, so
              -- an animated NPC step would never finish and every later guest
              -- turn would see npc.moving=true.  Resolve hidden host-side remote
              -- turns instantly; the authoritative snapshot still moves the
              -- Pokemon on the guest's live overworld.
              npc.cellX,npc.cellY=tx,ty; npc.targetX,npc.targetY=nil,nil
              npc.px,npc.py=tx*16,ty*16; npc.progress=0; npc.moving=false
            else
              npc.targetX,npc.targetY=tx,ty
              -- A two-cell SLOW stride covers twice the distance in one monster
              -- action, so keep it visibly aggressive rather than taking two
              -- full player-turns worth of animation.
              npc.stepFrames=((math.abs((npc.cellX or e.x)-tx)+math.abs((npc.cellY or e.y)-ty))>=2) and 32 or 26
              npc.progress=0
              npc.moving=true
            end
          end
          end -- non-boss roaming branch
        end
      end
    end
  end

  -- Ground-item pickups also spend a dungeon turn. Expose the same turn
  -- routine as a world method so earlier interaction helpers can call it
  -- without adding another top-level local (LuaJIT's 200-local ceiling).
  function World:pewterDungeonMonsterTurn()
    if self.map and self.map.id==FLOOR and isActive(self.game) then
      moveWanderingMonsters(self.game)
    end
  end

  -- A failed movement press is still a dungeon turn. Gen-II can reject a
  -- wall/side-permission step before movement.collision sees a normal tile
  -- reason, so doing this from World:movePlayer's final result is the reliable
  -- seam. The first press that merely turns the player does not spend a turn.
  if not World.__pewterDungeonBlockedTurnWrapped then
    World.__pewterDungeonBlockedTurnWrapped=true
    local baseMovePlayer=World.movePlayer
    function World:movePlayer(dir)
      local result=baseMovePlayer(self,dir)
      local game=self.game
      if (result=="blocked" or result=="edge")
          and self.map and self.map.id==FLOOR and isActive(game)
          and not self.battleActive and not pendingMonsterCollision then
        moveWanderingMonsters(game)
      end
      return result
    end
  end

  local function trainerClassForEntity(game,e)
    local sprite=e and e.obj and e.obj.sprite
    local wanted=({
      SPRITE_YOUNGSTER="YOUNGSTER",SPRITE_LASS="LASS",SPRITE_BUG_CATCHER="BUG_CATCHER",
      SPRITE_FISHER="FISHER",SPRITE_SUPER_NERD="SUPER_NERD",SPRITE_HIKER="HIKER",
      -- Crystal's extracted class ids omit the underscore used by the overworld
      -- COOLTRAINER sprite ids. The old mapping therefore failed lookup and
      -- silently fell back to HIKER, producing the infamous woman->hiker swap.
      SPRITE_COOLTRAINER_M="COOLTRAINERM",SPRITE_COOLTRAINER_F="COOLTRAINERF",
      SPRITE_POKEFAN_M="POKEFANM",SPRITE_POKEFAN_F="POKEFANF",SPRITE_SAILOR="SAILOR",
      SPRITE_GENTLEMAN="GENTLEMAN",SPRITE_TEACHER="TEACHER",SPRITE_BEAUTY="BEAUTY",
      SPRITE_BIKER="BIKER",SPRITE_BLACK_BELT="BLACKBELT_T",SPRITE_GRAMPS="GENTLEMAN",
    })[sprite] or "HIKER"
    local classes=game.data and game.data.trainers and game.data.trainers.classes or {}
    if not classes[wanted] then
      -- Defensive fallback: if a cache ever renames one of the exact class ids,
      -- preserve the overworld trainer's apparent gender instead of turning
      -- every unknown sprite into a HIKER.
      local female=(sprite=="SPRITE_LASS" or sprite=="SPRITE_COOLTRAINER_F"
        or sprite=="SPRITE_POKEFAN_F" or sprite=="SPRITE_TEACHER" or sprite=="SPRITE_BEAUTY")
      if female and classes.LASS then wanted="LASS"
      elseif classes.YOUNGSTER then wanted="YOUNGSTER"
      else wanted="HIKER" end
    end
    return wanted,classes[wanted]
  end

  local function trainerBattle(game,e)
    local world=game.world
    if e.used then return showPages(world,{"Good fight. Lower\nfloors get ugly."}) end
    local me=tostring((game.save.player and game.save.player.name) or "DELVER")
    if e.coopEngagedBy and e.coopEngagedBy~=me then
      return showPages(world,{"That Delver is battling "..tostring(e.coopEngagedBy).."."},function()
        if SPECIAL.COOP and SPECIAL.COOP.offerSpectate then SPECIAL.COOP.offerSpectate(game,e,true) end
      end)
    end
    local depth=(floorState and floorState.depth) or 1
    local r=rng(floorSeed(pdSave(game),depth)+(e.index or 0)*7919)
    local species=chooseSpeciesForDepth(game,depth+2,r)
    local level=trainerLevelForDepth(depth,r)
    local candidate=buildMon(game,species,level)
    if not candidate then return showPages(world,{"I couldn't prep my\npartner. Weird."}) end
    local battleMon=deep(candidate)
    local classId,classDef=trainerClassForEntity(game,e)
    local trainer={
      class=classId,classId=classId,name="DELVER",trainerName="DELVER",
      className="DELVER",party={battleMon},baseMoney=0,items={},
      attributes=(classDef and classDef.attributes) or 0,
    }
    showPages(world,{"Another Delver?\nShow me your team!"},function()
      if not e.coopBattle then
        e.coopEngagedBy=me; e.coopBattle=true
        if SPECIAL.COOP then SPECIAL.COOP.entityEngage(game,e,"battle") end
      end
      beginDelveBattle(world,{trainer=trainer,battleType=1},e,function(outcome)
        if #(game.save.party or {})==0 or outcome=="lose" then return loseRun(game,"YOUR DELVE ENDED.") end
        e.used=true
        e.coopEngagedBy=nil; e.coopBattle=nil; e.engaging=nil
        if SPECIAL.COOP then SPECIAL.COOP.entityState(game,e) end
        -- If PokeSurvive randomized the trainer, offer the Pokemon the player
        -- actually battled, not Pewter Dungeon's pre-randomizer placeholder.
        local fought=deep(e.lastBattleMon or candidate)
        e.lastBattleMon=nil
        sanitizeDelveMonMoves(game,fought)
        healMon(fought)
        swapPrompt(game,fought)
      end)
    end)
  end

  -- Delver trainers use the same overworld idea as Crystal's normal sight
  -- trainers: they continuously turn, throw the ! bubble when the player
  -- enters the direction they are facing, then walk up before speaking.
  -- Our generated trainers do not point at a fixed ROM trainer record, so
  -- the battle itself remains Pewter Dungeon's generated battle; only the
  -- overworld engagement is custom.
  local function floorEntityForNpc(npc)
    if not (floorState and npc and npc.def) then return nil end
    for _,e in ipairs(floorState.entities or {}) do
      if e.index==npc.def.index and e.role=="trainer" then return e end
    end
    return nil
  end

  local function sightPathClear(world,npc,distance,dir)
    if not (world and world.map and npc and distance and dir) then return false end
    local delta=Map.DELTA[dir]
    if not delta then return false end
    for i=1,math.max(0,distance-1) do
      local x=npc.cellX+delta[1]*i
      local y=npc.cellY+delta[2]*i
      if world.map.isWalkableCell and not world.map:isWalkableCell(x,y) then
        return false
      end
      for _,other in ipairs(world.npcs or {}) do
        if other~=npc and other.cellX==x and other.cellY==y then return false end
      end
    end
    return true
  end

  local function engageSightTrainer(world,npc,e,distance,dir)
    if not (world and npc and e) or e.used or e.engaging or e.coopEngagedBy then return false end
    e.engaging=true
    e.coopEngagedBy=tostring((world.game.save.player and world.game.save.player.name) or "DELVER")
    if SPECIAL.COOP then SPECIAL.COOP.entityEngage(world.game,e,"approach",distance,dir) end
    world.talkNpc=npc
    world.trainerNpc=npc
    world.trainerSight={distance=distance,dir=dir}
    if world.freezeNpc then world:freezeNpc(npc) end

    -- Crystal's trainer alert bubble. The approach starts immediately after
    -- the sight check, so it remains visible as the Delver closes the gap.
    if world.showEmote then world:showEmote(0,-2,30) end
    local _,classDef=trainerClassForEntity(world.game,e)
    if classDef and classDef.index and world.playTrainerEncounterMusic then
      world:playTrainerEncounterMusic(classDef.index)
    end

    local steps=Trainers.approach(distance,dir)
    local function beginFight()
      e.engaging=nil
      if floorState and floorState.entityAt then floorState.entityAt[e.y*1024+e.x]=nil end
      e.x,e.y=npc.cellX or e.x,npc.cellY or e.y
      if floorState and floorState.entityAt then floorState.entityAt[e.y*1024+e.x]=e end
      e.coopBattle=true
      if SPECIAL.COOP then SPECIAL.COOP.entityEngage(world.game,e,"battle") end
      world.trainerNpc=nil
      world.trainerSight=nil
      trainerBattle(world.game,e)
    end
    if #steps==0 then beginFight(); return true end
    local bytes={}
    for _,stepDir in ipairs(steps) do bytes[#bytes+1]=Movement.stepByte(stepDir) end
    bytes[#bytes+1]=Movement.STEP_END
    world:beginMovement((npc.def.index or 0)+1,bytes,beginFight)
    return true
  end

  if not World.__pewterDungeonTrainerSightWrapped then
    World.__pewterDungeonTrainerSightWrapped=true
    local baseCheckTrainerBattle=World.checkTrainerBattle
    function World:checkTrainerBattle(...)
      if self.map and self.map.id==FLOOR and floorState and self.player
          and not self:busy() and not self.player.moving then
        for _,npc in ipairs(self.npcs or {}) do
          local def=npc.def
          if def and def.pewterRole=="trainer" then
            local e=floorEntityForNpc(npc)
            if e and not e.used and not e.engaging and not e.coopEngagedBy then
              local distance,dir=Trainers.sees(npc,self.player,def.sight or 4)
              if distance and sightPathClear(self,npc,distance,dir) then
                if engageSightTrainer(self,npc,e,distance,dir) then return true end
              end
            end
          end
        end
      end
      return baseCheckTrainerBattle(self,...)
    end
  end

  local function useStairs(game,e)
    if transitioning then return end
    -- Use the shared TextBox choice path so the question remains visible under
    -- the YES/NO prompt exactly like Crystal's native yesorno scripts.
    game.stack:push(TextBox.new(game,"Travel to the next\nfloor?",nil,{
      defaultNo=true,
      choice=function(yes)
        if yes then
          local depth=(floorState and floorState.depth) or pdSave(game).floor or 1
          SPECIAL.COOP.requestAdvance(game,depth,function()
            updateDeepest(game,depth)
            advanceFloor(game,false)
          end)
        end
      end,
    }))
  end

  local function interactFloorEntity(game,fx,fy)
    if not floorState then return false end
    local e=floorState.entityAt[fy*1024+fx]
    if not (e and e.active) then return false end
    if e.role=="healer" then healer(game,e)
    elseif e.role=="trader" then trader(game,e)
    elseif e.role=="trickster" then trickster(game,e)
    elseif e.role=="fossil" then fossil(game,e)
    elseif e.role=="extract" then confirmExtract(game)
    elseif e.role=="threshold_miner" then SPECIAL.handleThresholdExit(game)
    elseif e.role=="trainer" then trainerBattle(game,e)
    elseif e.role=="loot" then pickupLoot(game,e)
    elseif e.role=="shelf" then shelfInteract(game,e)
    elseif e.role=="floor_key" then
      local sf=floorState and floorState.specialFeature
      if sf then sf.keyFound=true end
      removeEntity(game,e)
      Sound.dropPressSfx()
      if game.world.playSfxNamed then game.world:playSfxNamed("Sfx_Item") else Sound.play(game.data,"Sfx_Item") end
      showPages(game.world,{"You found the FLOOR KEY!","A sealed mechanism should open now."},function()
        if game.world and game.world.pewterDungeonMonsterTurn then
          game.world:pewterDungeonMonsterTurn()
        end
      end)
    elseif e.role=="gate" then
      local sf=floorState and floorState.specialFeature
      if sf and sf.keyFound then
        sf.gateOpen=true
        removeEntity(game,e)
        Sound.dropPressSfx()
        if game.world.playSfxNamed then game.world:playSfxNamed("Sfx_Strength") end
        showPages(game.world,{"The FLOOR KEY turns.","The seal guarding the ladder retracts!"})
      else
        showPages(game.world,{"A heavy seal blocks the ladder.","There must be a key mechanism on this floor."})
      end
    elseif e.role=="monster" then startMonsterBattle(game,e)
    elseif e.role=="stairs" then useStairs(game,e)
    else return false end
    return true
  end

  -- Gen 2 handles NPC A-presses inline in World:interactBody. Keep the
  -- original engine method once, then install a fresh Dungeon Delvers wrapper
  -- every load. This avoids a stale closure from an older DEV build owning the
  -- rest-stop NPC interactions after a mod reload.
  World.__pewterDungeonBaseInteractBody=World.__pewterDungeonBaseInteractBody or World.interactBody
  do
    local baseInteractBody=World.__pewterDungeonBaseInteractBody
    function World:interactBody(...)
      local mapId=self.map and self.map.id
      if (mapId==PEWTER or mapId==LOBBY or mapId==UPSTAIRS or mapId==FLOOR)
          and self.player and not self.player.moving and not self:busy() then
        local d=Map.DELTA[self.player.facing]
        local fx,fy
        if d then
          fx=self.player.cellX+d[1]
          fy=self.player.cellY+d[2]
        end

        if mapId==PEWTER and fx==MUSEUM_SIGN_X and fy==MUSEUM_SIGN_Y then
          showPages(self,{"PEWTER MUSEUM\nDelve excavation","now open!"})
          return true
        end

        if mapId==UPSTAIRS then
          if fx==1 and fy==6 then
            showPages(self,{"*POKéMON\nPALEONTOLOGY","CENTER"})
            return true
          end
          if Fossils.tryExhibitInteraction(self.game,fx,fy) then return true end
        end

        -- The generated floor-state entity is authoritative. Service it first
        -- so the B10/B30/B50 Scientist always opens checkpoint extraction even
        -- if the reusable procedural map has stale pooled NPC metadata.
        if mapId==FLOOR and floorState and fx and fy then
          local direct=floorState.entityAt and floorState.entityAt[fy*1024+fx]
          if direct and direct.active then
            local live=self:facingObject()
            if live and live.facePlayer then pcall(live.facePlayer,live,self.player) end
            if interactFloorEntity(self.game,fx,fy) then return true end
          end
        end

        local npc=self:facingObject()
        local def=npc and npc.def
        local role=def and def.pewterRole
        if npc and role then
          if npc.facePlayer then pcall(npc.facePlayer,npc,self.player) end
          if self.freezeNpc then self:freezeNpc(npc) end
          self.talkNpc=npc
          if mapId==LOBBY then
            if role=="reception" then receptionist(self.game); return true end
          elseif mapId==UPSTAIRS then
            if role=="research" then Fossils.researchScientist(self.game); return true end
          elseif mapId==FLOOR then
            -- If pooled coordinates are stale, fall back to the tile the player
            -- is actually facing rather than silently doing nothing.
            if fx and fy and interactFloorEntity(self.game,fx,fy) then return true end
            if interactFloorEntity(self.game,def.x,def.y) then return true end
          end
        end
      end
      return baseInteractBody(self,...)
    end
    World.__pewterDungeonInteractVersion=95
  end

  -- Delve capture and faint rules -------------------------------------------------
  do
    local BattleState=require("src.ui.gen2.BattleState")
    if not BattleState.__pewterDelveBallWrapped then
      BattleState.__pewterDelveBallWrapped=true
      local baseUseItem=BattleState.useItem
      function BattleState:useItem(itemId)
        local ds=self.save and self.save.pewterDungeon
        if itemId==ITEM_DELVE_BALL and ds and ds.active
            and activeDelveBattleFocus and activeDelveBattleFocus.boss then
          self.message="The guardian bats\nthe Ball away!"; self.messageTimer=90; self.phase="resolving"; return
        end
        return baseUseItem(self,itemId)
      end
    end
  end

  -- DELVE BALLS use Great Ball odds, but their special expedition perk is
  -- applied only after a successful capture: the new party member arrives
  -- at full HP with its status cleared. PP is deliberately left as caught.
  mod.events:on("pokemon.caught",function(ev)
    local game=mod.game
    if not (game and isActive(game) and ev and ev.ball==ITEM_DELVE_BALL and ev.mon) then return end
    local mon=ev.mon
    mon.status=nil
    mon.hp=mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp
    if #(game.save.party or {})>3 then
      for i=#game.save.party,1,-1 do
        if game.save.party[i]==mon then table.remove(game.save.party,i); break end
      end
      pdSave(game).pendingCaughtMon=mon
    end
  end,30)

  local delveFaints=setmetatable({}, {__mode="k"})
  local function playerBattleMon(battle,mon)
    for _,m in ipairs((battle and battle.party) or {}) do if m==mon then return true end end
    return false
  end
  local function removeMonFromParty(party,mon)
    for i=#(party or {}),1,-1 do if party[i]==mon then table.remove(party,i); return true end end
    return false
  end
  mod.events:on("battle.fainted",function(ev)
    local game=mod.game; if not (game and isActive(game)) then return end
    local battle,mon=ev and ev.battle,ev and ev.battler
    if not (battle and mon and playerBattleMon(battle,mon)) then return end
    local rec=delveFaints[battle] or {seen=setmetatable({}, {__mode="k"})}; delveFaints[battle]=rec
    if rec.seen[mon] then return end; rec.seen[mon]=true
    if not removeMonFromParty(battle.party,mon) then removeMonFromParty(game.save.party,mon) end
  end,-20)
  mod.events:on("battle.ended",function(ev)
    local game=mod.game; if not (game and isActive(game)) then return end
    -- Gen2 battle.ended exposes the BattleState as ev.battle; the core Battle
    -- object is one level down at .battle.  More importantly, simultaneous
    -- recoil/Selfdestruct KOs can end the fight on the enemy-faint branch
    -- before battle.fainted is ever emitted for the player's 0-HP Pokemon.
    -- Sweep the live delve party here so a mon that was blown up by a guardian
    -- cannot survive in the party merely because the guardian fainted first.
    local state=ev and ev.battle; local battle=state and (state.battle or state)
    if not battle then return end
    delveFaints[battle]=nil
    local party=game.save.party or {}
    for i=#party,1,-1 do
      if (tonumber(party[i] and party[i].hp) or 0)<=0 then table.remove(party,i) end
    end
    if #party==0 and battle.outcome=="lose" then battle.outcome="draw" end
  end,35)

  -- Crystal's overworld poison script would normally white out to a Pokemon
  -- Center. During a delve, remove each fainted rental and end the run at the
  -- museum desk instead.
  if not World.__pewterPoisonFaintWrapped then
    World.__pewterPoisonFaintWrapped=true
    local basePoisonFaint=World.poisonFaintScript
    function World:poisonFaintScript(event)
      local ds=self.game and self.game.save and self.game.save.pewterDungeon
      if not (ds and ds.active and self.map and self.map.id==FLOOR) then return basePoisonFaint(self,event) end
      local party=self.game.save.party or {}; local lost={}
      local refs={}
      for _,idx in ipairs(event.fainted or {}) do if party[idx] then refs[#refs+1]=party[idx] end end
      for _,mon in ipairs(refs) do lost[#lost+1]=monName(self.game,mon); removeMonFromParty(party,mon) end
      if self.playSfxNamed then self:playSfxNamed("Sfx_Poison") end
      local pages={}; for _,name in ipairs(lost) do pages[#pages+1]=name.." fainted!\nIt left the delve." end
      showPages(self,pages,function()
        if #party==0 then loseRun(self.game,"YOUR DELVE ENDED.") end
      end)
    end
  end

  -- World events -----------------------------------------------------------------
  -- Custom Museum 2F maps do not always dispatch ROM-style warp events, so
  -- explicitly service the visible lower-left stair cell.
  mod.events:on("world.stepped",function(ev)
    local game=mod.game
    if game and ev and ev.mapId==UPSTAIRS and ev.x==1 and ev.y==7 then
      -- The custom return stair is serviced manually, so mirror the native
      -- first-floor stair's WarpSound before changing maps.
      if game.world and game.world.warpSound then game.world:warpSound() end
      safeWarp(game,LOBBY,13,0,"down")
    end
  end)

  mod.events:on("world.stepped",function(ev)
    local game=mod.game
    if not (game and isActive(game) and ev and ev.mapId==FLOOR and floorState)
        or transitioning or floorState.collapsing then return end

    -- The generated descent is handled directly from the stepped event rather
    -- than by a self-referential Crystal warp.  This makes every validated exit
    -- work even when the decorative stair block came from a different cave.
    if floorState.descent
        and ev.x==floorState.descent.x and ev.y==floorState.descent.y then
      if floorState.descent.thresholdExit then
        SPECIAL.handleThresholdExit(game)
        return
      end
      if floorState.bossAlive or floorState.descent.locked then return end
      useStairs(game,nil)
      return
    end

    if floorState.campFloor then
      exploredAround(floorState,ev.x or 0,ev.y or 0,2)
      return
    end

    local sf=floorState.specialFeature
    local cellKey=(ev.y or 0)*1024+(ev.x or 0)
    if sf and sf.links and sf.links[cellKey] then
      local dest=sf.links[cellKey]
      Sound.dropPressSfx()
      if game.world and game.world.playSfxNamed then game.world:playSfxNamed("Sfx_WarpTo") end
      safeWarp(game,FLOOR,dest.x,dest.y,"down")
      queuePostWarpMessage(game,{"The linked panel throws you across the floor!"},"Sfx_WarpFrom")
      return
    end
    if sf and sf.hazards and sf.hazards[cellKey] then
      local hz=sf.hazards[cellKey]
      if not hz.used then
        hz.used=true
        hz.revealed=true
        if SPECIAL.COOP then SPECIAL.COOP.trapState(game,hz,true) end
        local mon=randomPartyMon(game,true)
        if hz.kind=="TOXIC" then
          if mon then mon.status="poison" end
          trapSfx(game.world,"POISON")
          showPages(game.world,{"A hidden vent bursts open!",(mon and monName(game,mon) or "A partner").." was poisoned!"})
        else
          damageMon(mon,.08)
          trapSfx(game.world,"BOULDER")
          showPages(game.world,{"A hidden heat plate flares!",(mon and monName(game,mon) or "A partner").." took damage!"})
        end
      end
    end

    floorState.stability=math.max(0,(tonumber(floorState.stability) or 1)-1)
    local s=pdSave(game)
    s.stability=floorState.stability
    local exploreRadius=1
    if floorState.modifier and floorState.modifier.exploreRadius~=nil then
      exploreRadius=math.max(0,math.floor(tonumber(floorState.modifier.exploreRadius) or 0))
    end
    exploredAround(floorState,ev.x or 0,ev.y or 0,exploreRadius)

    -- Timed trap effects tick only on completed overworld steps. Chaos gets a
    -- fresh direction permutation after each step so it never settles into a
    -- single easy remapping.
    if (tonumber(s.blindSteps) or 0)>0 then
      s.blindSteps=math.max(0,s.blindSteps-1)
      if s.blindSteps==0 then refreshBlindPipeline(game) end
    end
    if (tonumber(s.chaosSteps) or 0)>0 then
      s.chaosSteps=math.max(0,s.chaosSteps-1)
      if s.chaosSteps>0 then
        s.chaosMap=newChaosMap(floorSeed(s,floorState.depth)
          +s.chaosSteps*977+(floorState.stability or 0)*13)
      else
        s.chaosMap=nil
      end
    end
    if (tonumber(s.slowSteps) or 0)>0 then s.slowSteps=math.max(0,s.slowSteps-1) end

    local trap=floorState.traps and floorState.traps[(ev.y or 0)*1024+(ev.x or 0)]
    if trap and not trap.used then
      trap.used=true
      trap.revealed=true
      if SPECIAL.COOP then SPECIAL.COOP.trapState(game,trap,false) end
      triggerTrap(game,trap,"A hidden plate clicks!")
      return
    end

    if floorState.stability<=0 then
      floorState.collapsing=true
      showPages(game.world,{"THE FLOOR IS\nCOLLAPSING!"},function() advanceFloor(game,true) end)
      return
    elseif floorState.stability<=120 and not floorState.warned120 then
      floorState.warned120=true
      floorState.warned250=true
      showPages(game.world,{
        "The whole floor is starting to collapse!",
        "Find the ladder! Now!",
      })
      return
    elseif floorState.stability<=250 and not floorState.warned250 then
      floorState.warned250=true
      showPages(game.world,{
        "The cavern shifts beneath your feet!",
        "You should find the ladder soon.",
      })
      return
    end

    -- No random wild battles. Every completed player step advances the
    -- visible wandering Pokemon one tile, Azure-Dreams style. Monsters within
    -- four tiles switch from wandering to pursuit and battle on contact.
    moveWanderingMonsters(game)
  end)

  local function gen2BattleScreenActive(game)
    local states=game and game.stack and game.stack.states or {}
    for i=#states,1,-1 do
      local state=states[i]
      if state and (state.screenId=="Gen2BattleState" or state.isGen2BattleState) then
        return true
      end
    end
    return false
  end

  -- render.hud is drawn AFTER the finished 160x144 frame, so anything placed
  -- here would otherwise sit on top of START, PARTY, SUMMARY, swap screens,
  -- text boxes, etc.  Only draw the delve HUD when the overworld is the sole
  -- active layer; any pushed UI state gets visual priority over it.
  local function delveUiOverlayActive(game)
    local states=game and game.stack and game.stack.states
    return type(states)=="table" and #states>0
  end

  -- Tiny Gen-II-style status panel. It intentionally only exists while the
  -- player is physically exploring a delve floor with no menu/text screen on
  -- top. render.hud is the final layer, so the stack gate is what lets Crystal
  -- menus properly cover (rather than be covered by) the delve HUD.
  mod.hooks:wrap("render.hud",function(next,game,viewport)
    local result=next(game,viewport)
    if viewport and game and isActive(game) and not gen2BattleScreenActive(game)
        and not delveUiOverlayActive(game)
        and game.world and game.world.map and game.world.map.id==FLOOR and floorState then
      local gx=viewport.gameX or 0; local gy=viewport.gameY or 0
      local gw=viewport.gameWidth or 160; local gh=viewport.gameHeight or 144
      local scale=math.max(1,math.floor(math.min(gw/160,gh/144)))
      love.graphics.push("all")
      love.graphics.translate(gx,gy); love.graphics.scale(scale,scale)

      love.graphics.setColor(1,1,1,.96); love.graphics.rectangle("fill",0,0,112,24)
      love.graphics.setColor(0,0,0,1)
      love.graphics.rectangle("line",0,0,111,23)
      love.graphics.rectangle("line",2,2,107,19)
      fitText("B"..tostring(floorState.depth).."  "..tostring(floorState.layer or floorState.tone or "CAVES"),5,3,102)
      if floorState.checkpoint then
        Font.draw("REST STOP",5,11)
      elseif floorState.bossFloor then
        Font.draw(floorState.majorBoss and "STRATUM BOSS" or "GUARDIAN",5,11)
      else
        fitText(tostring(floorState.modifier.label or "STABLE"),5,11,102)
      end
      -- Always-on explored mini-map in the opposite corner. HIDDEN FLOOR is
      -- a navigation condition: the entire minimap disappears for that floor,
      -- even if scanners have revealed specific objects.
      if not (floorState.modifier and floorState.modifier.hideMinimap) then
        local mw,mh=45,35; local mx,my=160-mw-2,2
        love.graphics.setColor(1,1,1,.92); love.graphics.rectangle("fill",mx,my,mw,mh)
        love.graphics.setColor(0,0,0,1); love.graphics.rectangle("line",mx,my,mw,mh)
        local cw,ch=math.max(1,floorState.cellWidth or 1),math.max(1,floorState.cellHeight or 1)
        local sx=(mw-4)/cw; local sy=(mh-4)/ch; local ps=math.max(.65,math.min(sx,sy))
        local ox=mx+2+(mw-4-cw*ps)/2; local oy=my+2+(mh-4-ch*ps)/2
        local reveal=floorState.mapRevealed==true
        for k in pairs(floorState.walkable or {}) do
          if reveal or (floorState.explored and floorState.explored[k]) then
            local y=math.floor(k/1024); local x=k-y*1024
            love.graphics.setColor(.44,.44,.44,1); love.graphics.rectangle("fill",ox+x*ps,oy+y*ps,math.max(1,ps),math.max(1,ps))
          end
        end
        local d=floorState.descent
        local exitKnown=d and not d.hidden and (floorState.checkpoint or floorState.thresholdUnlocked
          or floorState.exitRevealed or reveal
          or (floorState.explored and floorState.explored[d.y*1024+d.x]))
        if exitKnown then
          love.graphics.setColor(.1,.1,.1,1)
          local m=math.max(2,ps*2)
          love.graphics.rectangle("line",ox+d.x*ps,oy+d.y*ps,m,m)
        end
        for _,e in ipairs(floorState.entities or {}) do
          local known=reveal or (floorState.explored and floorState.explored[e.y*1024+e.x])
            or (e.role=="fossil" and (floorState.fossilsRevealed or pdSave(game).fossilRevealFloor==floorState.depth))
          if e.active and known and e.role=="trainer" then
            love.graphics.setColor(1,.05,.05,1)
            love.graphics.rectangle("fill",ox+e.x*ps,oy+e.y*ps,math.max(2,ps*2),math.max(2,ps*2))
          elseif e.active and known and (e.role=="loot" or e.role=="fossil" or e.role=="floor_key") then
            love.graphics.setColor(1,.72,.05,1)
            love.graphics.rectangle("fill",ox+e.x*ps,oy+e.y*ps,1,1)
          end
        end
        for _,tr in pairs(floorState.traps or {}) do
          if tr.used or tr.revealed then
            love.graphics.setColor(1,.12,.12,1)
            love.graphics.rectangle("fill",ox+tr.x*ps,oy+tr.y*ps,math.max(1,ps),math.max(1,ps))
          end
        end
        local sf=floorState.specialFeature
        if sf and sf.hazards then
          for _,hz in pairs(sf.hazards) do
            if hz.used or hz.revealed then
              if hz.kind=="TOXIC" then love.graphics.setColor(.72,.2,.9,1)
              else love.graphics.setColor(1,.42,.06,1) end
              love.graphics.rectangle("fill",ox+hz.x*ps,oy+hz.y*ps,math.max(1,ps),math.max(1,ps))
            end
          end
        end
        local p=game.world.player
        if p then love.graphics.setColor(.08,.28,1,1); love.graphics.rectangle("fill",ox+p.cellX*ps,oy+p.cellY*ps,math.max(2,ps),math.max(2,ps)) end
      end
      love.graphics.pop()
    end
    return result
  end,245)

  -- DEV115 co-op battle thought bubbles live in a separate module so this
  -- already-dense main chunk stays safely below LuaJIT's 200-local ceiling.
  assert(load(assert(mod:read("coop_bubbles.lua")),"@pewter_dungeon/coop_bubbles.lua"))()({
    mod=mod,floorMap=FLOOR,owner=OWNER,isActive=isActive,coop=SPECIAL.COOP,Font=Font,
    battleActive=gen2BattleScreenActive,overlayActive=delveUiOverlayActive,
    getFloorState=function() return floorState end,
  })

  -- Online co-op foundation. Networking lives in coop.lua so the main module
  -- stays below LuaJIT's top-level local-variable ceiling.
  SPECIAL.COOP.init({
    mod=mod,version="1.0.0",Menu=Menu,Font=Font,Chrome=Chrome,
    lobbyMap=LOBBY,floorMap=FLOOR,pdSave=pdSave,isActive=isActive,showPages=showPages,
    unlocks=function(game)
      local ds=pdSave(game)
      return {works=ds.worksUnlocked==true,megalith=ds.megalithUnlocked==true}
    end,
    prepareStarter=function(game,depth,cb) SPECIAL.prepareCoopStarter(game,depth,cb) end,
    startRun=function(game,species,seed,depth) return SPECIAL.startCoopRun(game,species,seed,depth) end,
    checkpointMeta=function(game)
      local cp=pdSave(game).checkpoint
      if type(cp)~="table" or not cp.coopExpeditionId or not cp.nextFloor or not cp.runSeed then return nil end
      return {id=cp.coopExpeditionId,floor=cp.nextFloor,seed=cp.runSeed,start=cp.runStartFloor or 1}
    end,
    resumeCheckpoint=function(game,id,depth,seed,startDepth)
      return resumeCheckpoint(game,{coop=true,id=id,floor=depth,seed=seed,start=startDepth})
    end,
    continueSolo=function(game)
      local ds=pdSave(game)
      ds.coopRun=nil; ds.coopRelicActive=nil; ds.coopExpeditionId=nil
    end,
    newSeed=function(game) return freshRunSeed(game) end,
    floorSnapshot=function(game)
      if not floorState then return nil end
      local msg={floor=tonumber(floorState.depth) or 0,n=0,tn=0,hn=0}
      local scalarFields={
        "role","x","y","index","active","used","species","level","item","shelfItem",
        "tradeGiveIndex","tradeGetIndex","boss","bossTier","moveDir","cooldown",
        "fossilRoot","fossilPart","specialKey","specialGate","propKind",
      }
      local n=0
      for _,entity in ipairs(floorState.entities or {}) do
        n=n+1; local pre="e"..tostring(n).."_"
        for _,key in ipairs(scalarFields) do
          local value=entity[key]
          if value~=nil then msg[pre..key]=value end
        end
        if entity.obj and entity.obj.sprite then msg[pre.."sprite"]=entity.obj.sprite end
      end
      msg.n=n
      local trapList={}
      for _,trap in pairs(floorState.traps or {}) do trapList[#trapList+1]=trap end
      table.sort(trapList,function(a,b) return tostring(a.id or (a.y*1024+a.x))<tostring(b.id or (b.y*1024+b.x)) end)
      for i,trap in ipairs(trapList) do
        local pre="t"..tostring(i).."_"
        msg[pre.."x"]=trap.x; msg[pre.."y"]=trap.y; msg[pre.."type"]=trap.type
        msg[pre.."id"]=trap.id; msg[pre.."used"]=trap.used and true or false
        msg[pre.."revealed"]=trap.revealed and true or false
      end
      msg.tn=#trapList
      local hazardList={}
      local sf=floorState.specialFeature
      if sf and sf.hazards then for _,hz in pairs(sf.hazards) do hazardList[#hazardList+1]=hz end end
      table.sort(hazardList,function(a,b) return (a.y*1024+a.x)<(b.y*1024+b.x) end)
      for i,hz in ipairs(hazardList) do
        local pre="h"..tostring(i).."_"
        msg[pre.."x"]=hz.x; msg[pre.."y"]=hz.y; msg[pre.."kind"]=hz.kind
        msg[pre.."used"]=hz.used and true or false; msg[pre.."revealed"]=hz.revealed and true or false
      end
      msg.hn=#hazardList
      return msg
    end,
    applyFloorSnapshot=function(game,msg)
      if not floorState or tonumber(msg.floor)~=tonumber(floorState.depth) then return false end
      local oldByIndex={}
      for _,entity in ipairs(floorState.entities or {}) do oldByIndex[tonumber(entity.index)]=entity end
      local nextEntities={}
      local scalarFields={
        "role","x","y","index","active","used","species","level","item","shelfItem",
        "tradeGiveIndex","tradeGetIndex","boss","bossTier","moveDir","cooldown",
        "fossilRoot","fossilPart","specialKey","specialGate","propKind",
      }
      for i=1,math.max(0,tonumber(msg.n) or 0) do
        local pre="e"..tostring(i).."_"
        local index=tonumber(msg[pre.."index"]) or i
        local entity=oldByIndex[index] or {index=index,obj={}}
        for _,key in ipairs(scalarFields) do
          if msg[pre..key]~=nil then entity[key]=msg[pre..key] end
        end
        entity.index=index
        entity.active=(msg[pre.."active"]~=false)
        local role=entity.role
        local sprite=msg[pre.."sprite"] or (entity.obj and entity.obj.sprite) or "SPRITE_POKE_BALL"
        entity.obj=entity.obj or {}
        entity.obj.index=index; entity.obj.sprite=sprite; entity.obj.x=entity.x; entity.obj.y=entity.y
        entity.obj.movement=(role=="monster" and 0x16
          or ((role=="shelf" or role=="loot" or role=="fossil" or role=="floor_key" or role=="gate") and "STAY" or 3))
        entity.obj.radius={x=0,y=0}; entity.obj.hours={-1,-1}; entity.obj.palette=0; entity.obj.type=0
        entity.obj.sight=(role=="trainer" and 4 or 0); entity.obj.text="TEXT_PEWTER_DUNGEON_DYNAMIC"
        entity.obj.runtime=true; entity.obj.owner=OWNER; entity.obj.pewterRole=role
        nextEntities[#nextEntities+1]=entity
      end
      floorState.entities=nextEntities; floorState.entityAt={}
      local anyBoss=false
      for _,entity in ipairs(nextEntities) do
        if entity.active then
          floorState.entityAt[(tonumber(entity.y) or 0)*1024+(tonumber(entity.x) or 0)]=entity
          if entity.boss then anyBoss=true end
        end
      end
      floorState.bossAlive=anyBoss
      local traps={}
      for i=1,math.max(0,tonumber(msg.tn) or 0) do
        local pre="t"..tostring(i).."_"
        local x,y=tonumber(msg[pre.."x"]),tonumber(msg[pre.."y"])
        if x and y then
          traps[y*1024+x]={x=x,y=y,type=msg[pre.."type"],id=msg[pre.."id"],
            used=msg[pre.."used"] and true or false,revealed=msg[pre.."revealed"] and true or false}
        end
      end
      floorState.traps=traps
      if math.max(0,tonumber(msg.hn) or 0)>0 then
        floorState.specialFeature=floorState.specialFeature or {id="HAZARD_GRID"}
        floorState.specialFeature.hazards={}
        for i=1,math.max(0,tonumber(msg.hn) or 0) do
          local pre="h"..tostring(i).."_"; local x,y=tonumber(msg[pre.."x"]),tonumber(msg[pre.."y"])
          if x and y then
            floorState.specialFeature.hazards[y*1024+x]={x=x,y=y,kind=msg[pre.."kind"],
              used=msg[pre.."used"] and true or false,revealed=msg[pre.."revealed"] and true or false}
          end
        end
      end

      local def=game.data.gen2Maps and game.data.gen2Maps[FLOOR]
      if def then
        -- A guest floor snapshot also replaces the entire object table, so use
        -- the same safe ghost teardown as ordinary floor generation.
        if SPECIAL.COOP and SPECIAL.COOP.beforeFloorRebuild then
          pcall(SPECIAL.COOP.beforeFloorRebuild,game)
        end
        def.objects={}
        for _,entity in ipairs(nextEntities) do
          if entity.active and entity.role~="threshold_miner" then def.objects[#def.objects+1]=entity.obj end
        end
        if game.world and game.world.maps then game.world.maps[FLOOR]=def end
      end

      if SPECIAL.reconcileFloorNpcs then pcall(SPECIAL.reconcileFloorNpcs,game) end
      ensureThresholdMinerLive(game)
      return true
    end,
    monsterSnapshot=function(game)
      if not floorState then return nil end
      local msg={floor=tonumber(floorState.depth) or 0,n=0}
      local sigParts={tostring(msg.floor)}
      local n=0
      for _,entity in ipairs(floorState.entities or {}) do
        if entity.active and entity.role=="monster" then
          n=n+1; local pre="m"..tostring(n).."_"
          msg[pre.."index"]=entity.index; msg[pre.."x"]=entity.x; msg[pre.."y"]=entity.y
          msg[pre.."moveDir"]=entity.moveDir or ""; msg[pre.."cooldown"]=tonumber(entity.cooldown) or 0
          sigParts[#sigParts+1]=table.concat({tostring(entity.index),tostring(entity.x),tostring(entity.y),tostring(entity.moveDir or ""),tostring(entity.cooldown or 0)},":")
        end
      end
      msg.n=n; msg.sig=table.concat(sigParts,"|")
      return msg
    end,
    applyMonsterSnapshot=function(game,msg)
      if not floorState or tonumber(msg.floor)~=tonumber(floorState.depth) then return false end
      local byIndex={}
      for _,entity in ipairs(floorState.entities or {}) do byIndex[tonumber(entity.index)]=entity end
      floorState.entityAt=floorState.entityAt or {}
      for i=1,math.max(0,tonumber(msg.n) or 0) do
        local pre="m"..tostring(i).."_"; local index=tonumber(msg[pre.."index"]); local entity=byIndex[index]
        if entity and entity.active and not entity.battling then
          local oldX,oldY=tonumber(entity.x) or 0,tonumber(entity.y) or 0
          local newX=tonumber(msg[pre.."x"]) or oldX
          local newY=tonumber(msg[pre.."y"]) or oldY
          floorState.entityAt[oldY*1024+oldX]=nil
          entity.x,entity.y=newX,newY
          entity.moveDir=msg[pre.."moveDir"] or entity.moveDir; entity.cooldown=tonumber(msg[pre.."cooldown"]) or 0
          floorState.entityAt[newY*1024+newX]=entity
          local npc=floorNpcForEntity(game.world,entity)
          if npc then
            local dx,dy=newX-oldX,newY-oldY
            local dist=math.abs(dx)+math.abs(dy)
            -- DEV117: host snapshots announce the roamer's new logical cell.
            -- On the guest, animate that delta with Crystal's normal NPC
            -- interpolation instead of placeAt(), which looked like a one-tile
            -- teleport every dungeon turn. SLOW's two-cell stride simply uses
            -- a longer interpolation window.
            if dist>0 and dist<=2 and (dx==0 or dy==0) then
              if npc.moving and tonumber(npc.targetX)==newX and tonumber(npc.targetY)==newY then
                -- This exact replicated step is already in flight.
              else
                if npc.moving then
                  local settleX=tonumber(npc.targetX) or tonumber(npc.cellX) or oldX
                  local settleY=tonumber(npc.targetY) or tonumber(npc.cellY) or oldY
                  npc.cellX,npc.cellY=settleX,settleY; npc.px,npc.py=settleX*16,settleY*16
                elseif tonumber(npc.cellX)~=oldX or tonumber(npc.cellY)~=oldY then
                  npc.cellX,npc.cellY=oldX,oldY; npc.px,npc.py=oldX*16,oldY*16
                end
                npc.targetX,npc.targetY=newX,newY
                npc.stepFrames=(dist>=2) and 32 or 26
                npc.progress=0; npc.moving=true
              end
            elseif dist==0 then
              -- Position already matches; leave any in-flight interpolation
              -- alone so a follow-up snapshot cannot snap its final pixels.
            else
              npc.moving=false; npc.targetX=nil; npc.targetY=nil
              if npc.placeAt then npc:placeAt(newX,newY,npc.facing or "down")
              else npc.cellX,npc.cellY=newX,newY; npc.px,npc.py=newX*16,newY*16 end
            end
          end
        end
      end
      return true
    end,
    runMonsterTurn=function(game,x,y,remote) return moveWanderingMonsters(game,x,y,remote) end,
    forceMonsterBattle=function(game,index)
      if not floorState then return false end
      for _,entity in ipairs(floorState.entities or {}) do
        if entity.active and entity.role=="monster" and tonumber(entity.index)==tonumber(index) then
          entity.coopEngagedBy=nil; entity.coopBattle=nil
          startMonsterBattle(game,entity)
          return true
        end
      end
      return false
    end,
    applyTrapState=function(game,x,y,hazard,used,revealed)
      if not floorState then return false end
      local key=(tonumber(y) or 0)*1024+(tonumber(x) or 0)
      local row
      if hazard then
        local sf=floorState.specialFeature
        row=sf and sf.hazards and sf.hazards[key]
      else
        row=floorState.traps and floorState.traps[key]
      end
      if not row then return false end
      row.used=used and true or false; row.revealed=revealed and true or false
      return true
    end,
    revealAllTraps=function(game)
      if not floorState then return false end
      floorState.trapsRevealed=true
      for _,tr in pairs(floorState.traps or {}) do tr.revealed=true end
      local sf=floorState.specialFeature
      if sf and sf.hazards then for _,hz in pairs(sf.hazards) do hz.revealed=true end end
      return true
    end,
    applyEntityEngage=function(game,index,role,phase,by,distance,dir,x,y)
      if not floorState then return false end
      local entity
      for _,row in ipairs(floorState.entities or {}) do
        if tonumber(row.index)==tonumber(index) and (not role or row.role==role) then entity=row; break end
      end
      if not entity or not entity.active then return false end
      entity.coopEngagedBy=tostring(by or "PARTNER")
      entity.coopBattle=(phase=="battle") and true or nil
      entity.engaging=(phase=="approach") and true or nil
      local npc=floorNpcForEntity(game.world,entity)
      if role=="trainer" and phase=="approach" and npc and distance and dir and distance>0 then
        local steps=Trainers.approach(distance,dir)
        if #steps>0 then
          local bytes={}
          for _,stepDir in ipairs(steps) do bytes[#bytes+1]=Movement.stepByte(stepDir) end
          bytes[#bytes+1]=Movement.STEP_END
          game.world:beginMovement((npc.def.index or 0)+1,bytes,function()
            if floorState and floorState.entityAt then floorState.entityAt[entity.y*1024+entity.x]=nil end
            entity.x,entity.y=npc.cellX or entity.x,npc.cellY or entity.y
            if floorState and floorState.entityAt then floorState.entityAt[entity.y*1024+entity.x]=entity end
            entity.engaging=nil; entity.coopBattle=true
          end)
        end
      elseif phase=="battle" then
        if x and y then
          if floorState.entityAt then floorState.entityAt[entity.y*1024+entity.x]=nil end
          entity.x,entity.y=x,y
          if floorState.entityAt then floorState.entityAt[entity.y*1024+entity.x]=entity end
          if npc and role=="trainer" and not npc.moving then
            if npc.placeAt then npc:placeAt(x,y,npc.facing or "down")
            else npc.cellX,npc.cellY=x,y; npc.px,npc.py=x*16,y*16 end
          end
        end
        if npc and role=="monster" then npc.moving=false; npc.targetX=nil; npc.targetY=nil end
      end
      return true
    end,
    applyEntityState=function(game,index,role,used)
      if not floorState then return false end
      for _,entity in ipairs(floorState.entities or {}) do
        if tonumber(entity.index)==tonumber(index) and (not role or entity.role==role) then
          entity.used=used and true or false; entity.engaging=nil; entity.coopEngagedBy=nil; entity.coopBattle=nil; return true
        end
      end
      return false
    end,
    removeEntityByIndex=function(game,index,role)
      if not floorState then return end
      if role=="floor_key" and floorState.specialFeature then floorState.specialFeature.keyFound=true end
      if role=="gate" and floorState.specialFeature then floorState.specialFeature.gateOpen=true end
      for _,entity in ipairs(floorState.entities or {}) do
        if entity.active and tonumber(entity.index)==tonumber(index) then
          removeEntity(game,entity); return
        end
      end
    end,
    receiveFossil=function(game,root,part,depth,integrity)
      Fossils.addRunFossil(game,root,part,depth,integrity)
    end,
    receiveItem=function(game,id,qty)
      local ds=pdSave(game); ds.carriedTreasures=ds.carriedTreasures or {}
      ds.carriedTreasures[id]=(ds.carriedTreasures[id] or 0)+(tonumber(qty) or 1)
    end,
    itemName=function(game,id) return itemName(game,id) end,
    tradeItems=function(game)
      local rows={}
      for _,id in ipairs(Bag.order(game.save,game.data) or {}) do
        local qty=tonumber(game.save.inventory and game.save.inventory[id]) or 0
        local def=game.data.items and game.data.items[id]
        local pocket=(def and def.pocket) or "ITEM"
        if qty>0 and not Bag.isBadge(id) and pocket~="KEY_ITEM"
            and id~=SPECIAL.FIELD_CASE and id~=SPECIAL.WORKS_KEY and id~=SPECIAL.MEGALITH_KEY
            and id~=SPECIAL.HEAD_FOSSIL and id~=SPECIAL.UBODY_FOSSIL and id~=SPECIAL.LBODY_FOSSIL then
          rows[#rows+1]={id=id,qty=qty,name=itemName(game,id)}
        end
      end
      return rows
    end,
    tradeItemQty=function(game,id)
      return tonumber(game.save.inventory and game.save.inventory[id]) or 0
    end,
    canReceiveTrade=function(game,id,qty)
      qty=math.max(1,math.floor(tonumber(qty) or 1))
      local inv=game.save.inventory or {}; local current=tonumber(inv[id]) or 0
      if current>0 then return current+qty<=99 end
      local pocket=Bag.pocketOf(id,game.data)
      return Bag.slots(game.save,game.data,pocket)<Bag.capacity(game.data,pocket) and qty<=99
    end,
    removeTradeItem=function(game,id,qty)
      qty=math.max(1,math.floor(tonumber(qty) or 1))
      if (tonumber(game.save.inventory and game.save.inventory[id]) or 0)<qty then return false end
      Bag.remove(game.save,id,qty); return true
    end,
    addTradeItem=function(game,id,qty)
      return Bag.add(game.save,id,math.max(1,math.floor(tonumber(qty) or 1)),game.data)
    end,
    hasRelic=function(game)
      for _,mon in ipairs(game.save.party or {}) do if mon.item==GEAR_CHARM then return true end end
      return false
    end,
    setSharedRelic=function(game,value) pdSave(game).coopRelicActive=value and true or false end,
  })

  -- Map scripts ------------------------------------------------------------------
  mod.content.map_scripts:register(PEWTER,{
    onInteract=function(game,ow,fx,fy)
      if fx==MUSEUM_SIGN_X and fy==MUSEUM_SIGN_Y then
        showPages(ow,{
          "PEWTER MUSEUM\nDelve excavation",
          "now open!",
        })
        return true
      end
      return false
    end,
  })

  mod.content.map_scripts:register(LOBBY,{
    talk={
      TEXT_PEWTER_DUNGEON_RECEPTION={{"show_text","DELVE DESK"}},
      TEXT_PEWTER_DUNGEON_RESEARCH={{"show_text","FOSSIL RESEARCH LAB"}},
    },
    onInteract=function(game,ow,fx,fy)
      if fx==lobbyReception.x and fy==lobbyReception.y then receptionist(game); return true end
      if fx==lobbyResearch.x and fy==lobbyResearch.y then Fossils.researchDesk(game); return true end
      return false
    end,
  })

  mod.content.map_scripts:register(FLOOR,{
    talk={TEXT_PEWTER_DUNGEON_DYNAMIC={{"show_text","DELVE ENCOUNTER"}}},
    onInteract=function(game,ow,fx,fy)
      return interactFloorEntity(game,fx,fy)
    end,
  })

  -- If a user updates/reloads the mod while a DEV run was saved, fail safe:
  -- restore escrow the next time the mod boots instead of risking a stranded
  -- temporary party. Mid-delve saving is deliberately unsupported in DEV7.
  do
    local game=mod.game
    local s=game and game.save and game.save.pewterDungeon
    if s and s.active and (s.partyBackup or s.inventoryBackup) then
      mod.log:warn("Dungeon Delvers DEV67: recovering an interrupted saved delve")
      Fossils.clearRunLoot(s)
      restoreEscrow(game)
      pdSave(game).recoverToLobby=true
    end
  end

  mod.events:on("map.entered",function(ev)
    if SPECIAL.COOP then SPECIAL.COOP.onMapEntered(mod.game,ev) end
    -- Belt-and-suspenders for B20/B40: if another engine path enters the same
    -- procedural map without going through safeWarp, make the threshold miner
    -- live here as well.
    if ev and ev.mapId==FLOOR then ensureThresholdMinerLive(mod.game) end
    local game=mod.game; local s=game and pdSave(game)
    if s and s.recoverToLobby and ev and ev.mapId==FLOOR then
      s.recoverToLobby=nil
      safeWarp(game,LOBBY,lobbyReception.x,lobbyReception.y+2,"up")
      return
    end
    if s and s.pendingDelveRecap and ev and ev.mapId==LOBBY then
      -- The map-enter event fires before the first museum frame is guaranteed
      -- to be presented. Prime a short delay so the player sees the desk and
      -- attendant before the report text opens.
      s.pendingDelveRecap.frames=math.max(6,tonumber(s.pendingDelveRecap.frames) or 0)
    end
    if game then refreshBlindPipeline(game) end
  end)

  mod.log:info("Dungeon Delvers 1.0 loaded")
end
