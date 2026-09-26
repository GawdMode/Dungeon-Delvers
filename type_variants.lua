-- Individual delve types. Keep the roll private to this expedition, without
-- changing the shared species definition used by the rest of Crystal.
local V={}
local TYPES={"NORMAL","FIGHTING","FLYING","POISON","GROUND","ROCK","BUG","GHOST","STEEL","FIRE","WATER","GRASS","ELECTRIC","PSYCHIC_TYPE","ICE","DRAGON","DARK"}
local function copy(types) local out={} for i=1,math.min(2,#(types or {})) do out[i]=types[i] end return out end

function V.install(mod,Mon,Battle)
  if not Mon.__ddTypeIdentityWrapped then
    Mon.__ddTypeIdentityWrapped=true
    local original=Mon.syncIdentity
    Mon.syncIdentity=function(mon,data,...)
      local result=original(mon,data,...)
      if mon and mon._ddIndividualTypes then mon.types=copy(mon._ddIndividualTypes) end
      return result
    end
  end
  if not Battle.__ddTypeDefWrapped then
    Battle.__ddTypeDefWrapped=true
    local original=Battle.speciesDef
    function Battle:speciesDef(mon)
      local def=original(self,mon)
      if not (def and mon and mon._ddIndividualTypes) then return def end
      local proxy=setmetatable({types=copy(mon._ddIndividualTypes)},{__index=def})
      return proxy
    end
  end
  return function(game,mon)
    if not (game and mon and mod.find) then return mon end
    local ps=mod.find("pokemon_survival")
    local api=ps and ps.exports and ps.exports.anglers
    if not (api and api.randomPokemonEnabled and api.randomPokemonEnabled()
        and api.randomTypesEnabled and api.randomTypesEnabled()) then return mon end
    local available={}
    local chart=game.data and game.data.type_chart
    for _,id in ipairs(TYPES) do
      if not chart or not chart.types or chart.types[id] then available[#available+1]=id end
    end
    if #available==0 then available=TYPES end
    local first=available[math.random(#available)]
    local rolled={first}
    if #available>1 and math.random(100)<=60 then
      local second=first
      while second==first do second=available[math.random(#available)] end
      rolled[2]=second
    end
    mon._ddIndividualTypes=rolled
    mon.types=copy(rolled)
    return mon
  end
end

return V
