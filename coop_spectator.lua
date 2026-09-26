-- Dungeon Delvers co-op battle spectator screen (DEV131).
-- This is deliberately read-only: the battling client remains authoritative
-- and streams compact Gen-2 BattleAPI snapshots to the observer.

local Spectator = {}
local C
local SCREEN = "PewterDungeonCoopSpectator"

local Assets = require("src.render.Assets")
local BattleHud = require("src.ui.gen2.BattleHud")
local AnimRunner = require("src.battle.gen2.AnimRunner")
local BattleAnimView = require("src.ui.gen2.BattleAnimView")
local GbcPalette = require("src.render.GbcPalette")
local Palettes = require("src.world.gen2.Palettes")
local Sprites = require("src.pokemon.Sprites")

local STATUS = {
  poison="PSN", toxic="PSN", burn="BRN", freeze="FRZ",
  paralyze="PAR", sleep="SLP",
}

local function clamp(v,a,b)
  v=tonumber(v) or 0
  if v<a then return a end
  if v>b then return b end
  return v
end

local function drawMon(game,snap,back,shake,animState)
  if not (snap and snap.species) then return end
  local data=game.data or {}
  local path,trueColor=Sprites.path(data,snap.species,back and "back" or "front",{kind="battle"})
  if not path then return end
  local ok,img=pcall(Assets.image,path)
  if not ok or not img then return end
  local w,h=img:getDimensions()
  local boxTiles=back and 6 or 7
  local box=boxTiles*8
  local bx=(back and 2 or 12)*8
  local by=(back and 6 or 0)*8
  local scale=math.min(1,box/math.max(1,w),box/math.max(1,h))
  if animState and animState.hidden then return end
  local px=bx+math.floor((box-w*scale)/2)+(shake or 0)+((animState and animState.slide) or 0)
  local py=by+math.floor(box-h*scale)
  local colors=data.gen2Palettes and Palettes.monColors(data.gen2Palettes,snap.species,false)
  if colors and animState and animState.shade and GbcPalette.available() then
    colors=BattleAnimView.shadeColors(colors,animState.shade)
  end
  local function body()
    love.graphics.setColor(1,1,1,1)
    local sink=animState and tonumber(animState.faintSink) or 0
    if sink and sink>0 then
      -- Crystal's MonFaintedAnimation sinks one 8px picture row every two
      -- frames and removes rows that have crossed the bottom of the pic box.
      local visible=h-math.floor(sink/math.max(scale,0.001))
      if visible<=0 then return end
      local quad=love.graphics.newQuad(0,0,w,visible,w,h)
      love.graphics.draw(img,quad,px,py+sink,0,scale,scale)
    else
      love.graphics.draw(img,px,py,0,scale,scale)
    end
  end
  if colors and not trueColor and GbcPalette.available() then
    GbcPalette.with(colors,body)
  else
    body()
  end
end

local function statusLabel(mon)
  if not mon or not mon.status or mon.status=="" then return nil end
  return STATUS[tostring(mon.status)] or tostring(mon.status):upper():sub(1,3)
end

local function drawHud(game,hud,snap,playerHp,enemyHp)
  local Font=C.Font
  local old=Font.useBattleExtra and Font.useBattleExtra(true)
  local enemy=snap.enemy or {}
  local player=snap.player or {}
  C.Font.draw(tostring(enemy.name or enemy.species or "POKEMON"):sub(1,10),8,0)
  C.Font.draw(statusLabel(enemy) or ("<LV>"..tostring(enemy.level or 1)),48,8)
  C.Font.draw(tostring(player.name or player.species or "POKEMON"):sub(1,10),80,56)
  C.Font.draw(statusLabel(player) or ("<LV>"..tostring(player.level or 1)),112,64)
  local emax=math.max(1,tonumber(enemy.maxHp) or tonumber(enemy.hp) or 1)
  local pmax=math.max(1,tonumber(player.maxHp) or tonumber(player.hp) or 1)
  if hud and hud:available() then
    hud:drawHpBar(clamp(enemyHp or enemy.hp,0,emax),emax,2,2)
    hud:drawEnemyFrame()
    hud:drawHpBar(clamp(playerHp or player.hp,0,pmax),pmax,10,9)
    hud:drawPlayerFrame()
  else
    local function bar(x,y,hp,maxHp)
      love.graphics.setColor(0,0,0,1); love.graphics.rectangle("line",x,y,50,6)
      love.graphics.rectangle("fill",x+1,y+1,math.floor(48*clamp(hp,0,maxHp)/maxHp),4)
      love.graphics.setColor(1,1,1,1)
    end
    bar(16,18,enemyHp or enemy.hp,emax)
    bar(80,74,playerHp or player.hp,pmax)
  end
  C.Font.draw(("%d/%d"):format(math.floor(clamp(playerHp or player.hp,0,pmax)),pmax),112,80)
  if Font.useBattleExtra then Font.useBattleExtra(old) end
end

local function wrap(text,width,maxLines)
  local out,current={},""
  for word in tostring(text or ""):gmatch("%S+") do
    local nextLine=(current=="") and word or (current.." "..word)
    if current~="" and C.Font.width(nextLine)>width then
      out[#out+1]=current; current=word
      if #out>=maxLines then break end
    else
      current=nextLine
    end
  end
  if current~="" and #out<maxLines then out[#out+1]=current end
  return out
end

local function messageText(session,snap)
  local parts={}
  if snap then
    if snap.msg1 and snap.msg1~="" then parts[#parts+1]=snap.msg1 end
    if snap.msg2 and snap.msg2~="" then parts[#parts+1]=snap.msg2 end
  end
  if #parts>0 then return table.concat(parts," ") end
  local who=tostring((session and session.owner) or "PARTNER")
  local prompt=snap and snap.prompt
  if prompt=="menu" or prompt=="moves" or prompt=="party" then
    return who.." is choosing an action..."
  end
  return "Battle in progress..."
end

local function animPicState(runner,side)
  if not runner then return nil end
  local bg=runner.bg
  if not bg then return nil end
  return {
    hidden=bg.hidden and bg.hidden[side] or false,
    slide=bg.slide and (bg.slide[side] or 0) or 0,
    shade=bg.monShade and bg.monShade[side] or nil,
  }
end

local function combinedPicState(runner,side,faint,persistentHidden)
  local out=animPicState(runner,side) or {}
  out.hidden=(out.hidden or persistentHidden) and true or false
  if faint and faint.side==side then
    out.hidden=false
    out.faintSink=math.floor((tonumber(faint.frames) or 0)/2)*8
  end
  return out
end

local function makeAnimBattle(snap)
  return {
    player={species=snap and snap.player and snap.player.species,shiny=false},
    enemy={species=snap and snap.enemy and snap.enemy.species,shiny=false},
  }
end

local function startRemoteAnim(game,snap)
  if not (snap and snap.animActive and snap.animId) then return nil end
  local data=(game and game.data) or {}
  local anims=data.gen2BattleAnims
  if not (anims and anims.scripts) then return nil end
  local id=tostring(snap.animId)
  local key
  if snap.animIsMove then key=anims.moves and anims.moves[id] end
  if not key then key=anims.ids and anims.ids[id] end
  if not key then key=anims.moves and anims.moves[id] end
  if not key then return nil end
  local runner=AnimRunner.new({
    data=anims,
    constants=data.gen2Constants or {},
    battleTurn=tonumber(snap.animTurn) or 0,
    animId=id,
    param=tonumber(snap.animParam) or 0,
    sfxOrder=(data.audio or {}).sfxOrder,
    hooks={},
  })
  runner:start(key)
  -- Usually the start packet arrives on the first frame. If the relay was a
  -- little late, fast-forward the local script to roughly the battler's frame
  -- so the spectator does not watch an obviously delayed replay.
  local catchup=math.max(0,math.min(tonumber(snap.animFrame) or 0,90))
  for _=1,catchup do
    if not runner:step() then return nil end
  end
  runner.clearsHud=snap.animIsMove and true or false
  runner.hudSide=(tonumber(snap.animTurn) or 0)==0 and "player" or "enemy"
  return runner
end

function Spectator.init(ctx)
  C=ctx
  C.mod.content.screens:register(SCREEN,{
    new=function(game,opts)
      local st={game=game,isOpaque=true,endClock=0,displayPlayerHp=nil,displayEnemyHp=nil,
        targetPlayerHp=nil,targetEnemyHp=nil,pendingPlayerHp=nil,pendingEnemyHp=nil,
        playerShake=0,enemyShake=0,lastRevision=nil,lastPacketSeq=nil,
        lastAnimSeq=nil,animRunner=nil,animClock=0,lastFaintSeq=nil,
        faint=nil,faintClock=0,playerHidden=false,enemyHidden=false}
      st.hud=BattleHud.new((game.data or {}).gen2MenuGfx,(game.data or {}).gen2Palettes)
      if game.data and game.data.gen2BattleAnims and game.data.gen2BattleAnims.scripts then
        st.animView=BattleAnimView.new(game.data.gen2BattleAnims,game.data.gen2Palettes)
      end
      function st:update(dt)
        local session=C.session and C.session() or nil
        if not session then game.stack:pop(); return end
        local snap=session.snapshot
        if snap then
          -- Packet sequence is separate from BattleAPI revision: presentation
          -- events such as AnimateHPBar can begin without changing battle math.
          local packetSeq=tonumber(snap.seq) or tonumber(snap.revision) or 0
          local freshPacket=(packetSeq~=self.lastPacketSeq)
          if freshPacket then self.lastPacketSeq=packetSeq end

          local animSeq=tonumber(snap.animSeq) or 0
          if animSeq~=self.lastAnimSeq then
            self.lastAnimSeq=animSeq
            -- An "animation ended" packet must not kill the spectator's local
            -- replay a few frames early.  Let an existing runner finish on its
            -- own; only a newly-active animation replaces it.
            if snap.animActive then
              self.animRunner=startRemoteAnim(game,snap)
              self.animClock=0
            end
          end

          local faintSeq=tonumber(snap.faintSeq) or 0
          if faintSeq~=self.lastFaintSeq then
            self.lastFaintSeq=faintSeq
            if snap.faintActive and (snap.faintSide=="player" or snap.faintSide=="enemy") then
              local total=(snap.faintSide=="player") and 12 or 14
              self.faint={side=snap.faintSide,frames=clamp(tonumber(snap.faintFrame) or 0,0,total),total=total}
              self.faintClock=0
              if snap.faintSide=="player" then self.playerHidden=false else self.enemyHidden=false end
            end
          end

          if freshPacket then
            self.playerHidden=snap.playerHidden and true or false
            self.enemyHidden=snap.enemyHidden and true or false
            if self.faint then
              if self.faint.side=="player" then self.playerHidden=false else self.enemyHidden=false end
            end
            local php=tonumber(snap.player and snap.player.hp)
            local ehp=tonumber(snap.enemy and snap.enemy.hp)
            self.displayPlayerHp=self.displayPlayerHp or php
            self.displayEnemyHp=self.displayEnemyHp or ehp
            self.targetPlayerHp=self.targetPlayerHp or php
            self.targetEnemyHp=self.targetEnemyHp or ehp

            local hpSide=tostring(snap.hpAnimSide or "")
            local hpTo=tonumber(snap.hpAnimTo)
            if hpSide=="player" and hpTo then
              if self.targetPlayerHp and hpTo<self.targetPlayerHp then self.playerShake=.24 end
              if self.animRunner or snap.animActive then self.pendingPlayerHp=hpTo
              else self.targetPlayerHp=hpTo end
            elseif php and php~=self.targetPlayerHp and self.pendingPlayerHp==nil then
              -- Direct HUD changes (switch/send or an effect with no bar anim).
              self.targetPlayerHp=php
            end
            if hpSide=="enemy" and hpTo then
              if self.targetEnemyHp and hpTo<self.targetEnemyHp then self.enemyShake=.24 end
              if self.animRunner or snap.animActive then self.pendingEnemyHp=hpTo
              else self.targetEnemyHp=hpTo end
            elseif ehp and ehp~=self.targetEnemyHp and self.pendingEnemyHp==nil then
              self.targetEnemyHp=ehp
            end
          end

          local speed=math.max(1,60*(tonumber(dt) or 0))
          if self.displayPlayerHp and self.targetPlayerHp then
            local d=self.targetPlayerHp-self.displayPlayerHp
            self.displayPlayerHp=self.displayPlayerHp+clamp(d,-speed,speed)
          end
          if self.displayEnemyHp and self.targetEnemyHp then
            local d=self.targetEnemyHp-self.displayEnemyHp
            self.displayEnemyHp=self.displayEnemyHp+clamp(d,-speed,speed)
          end
        end
        if self.animRunner then
          self.animClock=self.animClock+math.max(0,(tonumber(dt) or 0)*60)
          while self.animRunner and self.animClock>=1 do
            self.animClock=self.animClock-1
            if not self.animRunner:step() then self.animRunner=nil end
          end
        end
        if self.faint then
          self.faintClock=self.faintClock+math.max(0,(tonumber(dt) or 0)*60)
          while self.faint and self.faintClock>=1 do
            self.faintClock=self.faintClock-1
            self.faint.frames=(tonumber(self.faint.frames) or 0)+1
            if self.faint.frames>=self.faint.total then
              if self.faint.side=="player" then self.playerHidden=true else self.enemyHidden=true end
              self.faint=nil
            end
          end
        end
        -- Never let an HP result visually spoil a replayed attack/effect.  Once
        -- the spectator's own animation is over, release the queued Crystal HP
        -- target and let the bar chase it normally.
        if not self.animRunner and not (snap and snap.animActive) then
          if self.pendingPlayerHp~=nil then
            self.targetPlayerHp=self.pendingPlayerHp; self.pendingPlayerHp=nil
          end
          if self.pendingEnemyHp~=nil then
            self.targetEnemyHp=self.pendingEnemyHp; self.pendingEnemyHp=nil
          end
        end
        self.playerShake=math.max(0,self.playerShake-(tonumber(dt) or 0))
        self.enemyShake=math.max(0,self.enemyShake-(tonumber(dt) or 0))
        if session.ended then
          self.endClock=self.endClock+(tonumber(dt) or 0)
          if self.endClock>=.8 then
            if C.finish then C.finish(game) end
            game.stack:pop(); return
          end
        end
        local input=game.input
        if input and input:wasPressed("b") and not session.ended then
          if C.stop then C.stop(game) end
          game.stack:pop(); return
        end
      end
      function st:draw()
        C.Chrome.clear()
        love.graphics.setColor(0,0,0,1)
        local session=C.session and C.session() or nil
        local snap=session and session.snapshot
        if not snap then
          C.Chrome.box(0,0,20,18)
          local function centered(t,y)
            t=tostring(t or ""); C.Font.draw(t,math.max(7,math.floor((160-C.Font.width(t))/2)),y)
          end
          centered("BATTLE SPECTATOR",26)
          centered((session and session.error) and tostring(session.error):sub(1,20) or "CONNECTING...",62)
          return
        end
        local phase=math.floor((love.timer.getTime()*20)%4)
        local pShake=(self.playerShake>0) and ((phase<2) and -2 or 2) or 0
        local eShake=(self.enemyShake>0) and ((phase<2) and 2 or -2) or 0
        local runner=self.animRunner
        local enemyAnim=combinedPicState(runner,"enemy",self.faint,self.enemyHidden)
        local playerAnim=combinedPicState(runner,"player",self.faint,self.playerHidden)
        local function panel()
          drawHud(game,self.hud,snap,self.displayPlayerHp,self.displayEnemyHp)
          drawMon(game,snap.enemy,false,eShake,enemyAnim)
          drawMon(game,snap.player,true,pShake,playerAnim)
          C.Chrome.box(0,12,20,6)
          local lines=wrap(messageText(session,snap),144,2)
          C.Font.draw(lines[1] or "",8,112)
          if lines[2] then C.Font.draw(lines[2],8,128) end
        end
        if runner and self.animView then
          local battle=makeAnimBattle(snap)
          self.animView:present(runner,panel,battle)
          self.animView:drawObjects(runner,battle)
        else
          panel()
        end
        if session.ended then
          love.graphics.setColor(1,1,1,.82); love.graphics.rectangle("fill",16,48,128,40)
          love.graphics.setColor(0,0,0,1)
          local text="BATTLE ENDED"
          C.Font.draw(text,math.floor((160-C.Font.width(text))/2),62)
        end
        love.graphics.setColor(1,1,1,1)
      end
      return st
    end,
  })
end

function Spectator.open(game)
  if C and C.mod and C.mod.ui then C.mod.ui.push(game,SCREEN,{}) end
end

return Spectator
