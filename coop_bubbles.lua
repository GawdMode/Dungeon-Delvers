-- Dungeon Delvers co-op overhead renderer (DEV131).
-- Nameplates and battle thought bubbles share PokeSurvive's proven
-- final-window anchoring path: world pixels -> live camera -> zoom -> Playfield.

return function(ctx)
  local mod=ctx.mod
  local FLOOR=ctx.floorMap
  local OWNER=ctx.owner
  local isActive=ctx.isActive
  local Coop=ctx.coop
  local getFloorState=ctx.getFloorState
  local Font=ctx.Font
  local battleActive=ctx.battleActive
  local overlayActive=ctx.overlayActive

  local battleBubbleImage=nil

  local function worldRenderContext()
    local ow=mod.world and mod.world:overworld()
    local cam=ow and ow.camera
    if not (ow and cam and love and love.graphics) then return nil end
    local ok,worldScale=pcall(function() return ow:zoomScale() end)
    if not ok or type(worldScale)~="number" or worldScale<=0 then worldScale=1 end
    local Playfield=require("src.render.Playfield")
    local ww,wh=love.graphics.getDimensions()
    local pfx,pfy=Playfield.rect(ww,wh)
    return ow,cam,worldScale,tonumber(pfx) or 0,tonumber(pfy) or 0,ww,wh
  end

  local function npcScreenAnchor(npc,rc)
    if not (npc and rc) then return nil end
    local _,cam,worldScale,pfx,pfy=rc[1],rc[2],rc[3],rc[4],rc[5]
    local px=tonumber(npc.px) or ((tonumber(npc.cellX) or 0)*16)
    local py=tonumber(npc.py) or ((tonumber(npc.cellY) or 0)*16)
    return pfx+(px+8-(tonumber(cam.x) or 0))*worldScale,
      pfy+(py-1-(tonumber(cam.y) or 0))*worldScale,worldScale
  end

  local function liveOwnedNpc(game,index)
    index=tonumber(index)
    if not index then return nil end
    local world=game and game.world
    for _,npc in ipairs((world and world.npcs) or {}) do
      local d=npc and npc.def or {}
      if d.owner==OWNER and tonumber(d.index)==index then return npc end
    end
    return nil
  end

  local function playerOverlapsTag(game,bx,by,bw,bh,worldScale)
    local ow=mod.world and mod.world:overworld()
    local p=ow and ow.player
    local cam=ow and ow.camera
    if not (p and cam and love and love.graphics) then return false end
    local Playfield=require("src.render.Playfield")
    local ww,wh=love.graphics.getDimensions()
    local pfx,pfy=Playfield.rect(ww,wh)
    local ppx=tonumber(p.px) or ((tonumber(p.cellX) or 0)*16)
    local ppy=tonumber(p.py) or ((tonumber(p.cellY) or 0)*16)
    local psx=(tonumber(pfx) or 0)+(ppx-(tonumber(cam.x) or 0))*worldScale
    local psy=(tonumber(pfy) or 0)+(ppy-(tonumber(cam.y) or 0))*worldScale
    local sw=16*worldScale
    local sh=16*worldScale
    return psx < bx+bw and psx+sw > bx and psy < by+bh and psy+sh > by
  end

  -- Match the same stepped visibility aperture used by the delve darkness.
  local function pointInsideVisibility(game,x,y)
    local fs=getFloorState and getFloorState() or nil
    if not fs or fs.campFloor then return true end
    local ow=mod.world and mod.world:overworld()
    local p=ow and ow.player
    if not (p and x~=nil and y~=nil) then return false end

    local s=game and game.save and game.save.pewterDungeon or nil
    local now=love.timer and love.timer.getTime and love.timer.getTime() or 0
    local blinded=s and (tonumber(s.blindSteps) or 0)>0
    local radiusTiles
    if blinded then
      radiusTiles=2.6 + 0.12*math.sin(now*2.6)
    else
      radiusTiles=9.75 + 0.475*math.sin(now*1.85) + 0.175*math.sin(now*4.9)
      local modf=fs.modifier
      if modf and tonumber(modf.visionMul) then radiusTiles=radiusTiles*tonumber(modf.visionMul) end
    end

    local r=math.max(12,radiusTiles*8)
    local ppx=(tonumber(p.px) or ((tonumber(p.cellX) or 0)*16))+8
    local ppy=(tonumber(p.py) or ((tonumber(p.cellY) or 0)*16))+4
    local qpx=(tonumber(x) or 0)*16+8
    local qpy=(tonumber(y) or 0)*16+4
    local dx=math.abs(qpx-ppx)
    local dy=math.abs(qpy-ppy)
    if dy>r then return false end
    local frac=dy/r
    local half
    if frac>=0.75 then half=r*0.48
    elseif frac>=0.50 then half=r*0.72
    elseif frac>=0.25 then half=r*0.90
    else half=r end
    return dx<=half
  end

  local function peerInsideVisibility(game)
    local pos=Coop and Coop.peerPosition and Coop.peerPosition(game) or nil
    return pos and pointInsideVisibility(game,pos.x,pos.y) or false
  end

  local function drawBattleBubble(sx,sy,worldScale)
    if not (sx and sy and love and love.graphics) then return end
    if not battleBubbleImage then
      local ok,img=pcall(love.graphics.newImage,mod.path.."/assets/coop/battle.png")
      if ok and img then img:setFilter("nearest","nearest"); battleBubbleImage=img end
    end
    if not battleBubbleImage then return end
    local G=love.graphics
    local bs=tonumber(worldScale) or 1
    G.push("all")
    G.setColor(1,1,1,1)
    -- PokeSurvive positions the 16x16 bubble 17 native pixels above the
    -- actor's sprite origin. peer/npc anchors here are actor-center X.
    G.draw(battleBubbleImage,math.floor(sx-8*bs),math.floor(sy-17*bs),0,bs,bs)
    G.pop()
  end

  if not mod.__pewterDungeonCoopNameHud131 then
    mod.__pewterDungeonCoopNameHud131=true
    mod.hooks:wrap("render.hud",function(next,game,viewport)
      local result=next(game,viewport)
      if not (viewport and game and love and love.graphics and Font and Coop
          and isActive(game) and game.world and game.world.map and game.world.map.id==FLOOR) then
        return result
      end
      if battleActive and battleActive(game) then return result end
      if Coop.isSpectating and Coop.isSpectating() then return result end
      if overlayActive and overlayActive(game) then return result end

      local rc={worldRenderContext()}
      if not rc[1] then return result end
      local worldScale,ww,wh=rc[3],rc[6],rc[7]

      -- The partner battle bubble itself is rendered in the partner NPC's own
      -- draw pass below (matching PokeSurvive exactly). Keep only the battle
      -- state here so the nametag knows to lift out of the bubble's way.
      local pb=Coop.peerBattleInfo and Coop.peerBattleInfo(game) or nil
      if not peerInsideVisibility(game) then return result end
      local name=Coop.peerName and Coop.peerName() or nil
      local sx,sy,tagWorldScale
      if Coop.peerRenderAnchor then sx,sy,tagWorldScale=Coop.peerRenderAnchor(game) end
      if type(name)~="string" or name=="" or sx==nil or sy==nil then return result end
      tagWorldScale=tonumber(tagWorldScale) or worldScale or 1

      if sx < -32*tagWorldScale or sx > ww+32*tagWorldScale
          or sy < -48*tagWorldScale or sy > wh+32*tagWorldScale then return result end

      name=tostring(name):upper()
      while #name>1 and Font.width(name)>64 do name=name:sub(1,#name-1) end

      local split=Font.split(name)
      local chars=type(split)=="table" and #split or #name
      local tw=math.max(4,chars+2)
      local th=3
      local nativeW=tw*8
      local nativeH=th*8
      local tagScale=math.max(0.6,tagWorldScale*0.6)
      local bw=nativeW*tagScale
      local bh=nativeH*tagScale
      local battling=pb and true or false
      local gap=(battling and 19*tagWorldScale or 3*tagWorldScale)
      local bx=math.floor(sx-bw/2)
      local by=math.floor(sy-gap-bh)
      bx=math.max(2,math.min(ww-bw-2,bx))
      by=math.max(2,by)

      local canvas=love.graphics.newCanvas(nativeW,nativeH)
      local G=love.graphics
      G.push("all")
      G.setCanvas(canvas)
      G.clear(0,0,0,0)
      G.setColor(1,1,1,1)
      Font.drawBox(0,0,tw,th)
      local textX=math.floor((nativeW-Font.width(name))/2)
      Font.draw(name,textX,8)
      G.setCanvas()
      local alpha=playerOverlapsTag(game,bx,by,bw,bh,tagWorldScale) and 0.72 or 1
      G.setColor(1,1,1,alpha)
      G.draw(canvas,bx,by,0,tagScale,tagScale)
      G.pop()
      return result
    end,244)
  end

  -- DEV138: render the remote player's battle thought bubble from the exact
  -- same NPC draw seam used by PokeSurvive resident battle bubbles.  The HUD
  -- path is excellent for nameplates, but the bubble belongs to the actor's
  -- sprite coordinate space so it follows Crystal camera/OAM transforms
  -- naturally and cannot drift or vanish from a mismatched coordinate space.
  pcall(function()
    local NPC=require("src.world.gen2.Npc")
    if NPC.__pewterDungeonCoopPlayerBubble138 then return end
    local baseDraw=NPC.draw
    NPC.__pewterDungeonCoopPlayerBubble138=true
    NPC.draw=function(self,ox,oy,scale,oamRow)
      baseDraw(self,ox,oy,scale,oamRow)
      local game=mod.game
      local d=self.def or {}
      if not (d.coopPartner==true or d.name=="PD_COOP_PARTNER") then return end
      if not (game and isActive(game) and game.world and game.world.map
          and game.world.map.id==FLOOR) then return end
      if not (scale and oamRow~="bottom" and self.sprite and love and love.graphics) then return end
      if battleActive and battleActive(game) then return end
      if Coop.isSpectating and Coop.isSpectating() then return end
      if overlayActive and overlayActive(game) then return end
      local pb=Coop.peerBattleInfo and Coop.peerBattleInfo(game) or nil
      if not pb or not peerInsideVisibility(game) then return end

      if not battleBubbleImage then
        local ok,img=pcall(love.graphics.newImage,mod.path.."/assets/coop/battle.png")
        if ok and img then
          img:setFilter("nearest","nearest")
          battleBubbleImage=img
        end
      end
      if not battleBubbleImage then return end

      local sx,sy=self.sprite:getScreenOrigin(self.px,
        self.py+(self.spriteYOffset or 0),0,0)
      local G=love.graphics
      G.push("all")
      G.translate(ox or 0,oy or 0)
      G.scale(scale,scale)
      G.setColor(1,1,1,1)
      G.draw(battleBubbleImage,math.floor(sx),math.floor(sy-17))
      G.pop()
    end
  end)

  return true
end
