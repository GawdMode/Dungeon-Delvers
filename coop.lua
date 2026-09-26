-- Dungeon Delvers co-op foundation (DEV129 PokeSurvive-anchored partner nametags).
-- Owns relay pairing, compatibility handshake, partner ghost, shared run start,
-- synchronized stair readiness, and mirrored excavation-case rewards.

local Coop = {}
local C
local Client
local Version
local Protocol
local Gen2BattleAPI
local Spectator

local SCREEN = "PewterDungeonCoopConnect"
local PROTOCOL = 1
local S = {
  net=nil, role=nil, helloSent=false, helloClock=0, peerHello=nil, ready=false,
  error=nil, notice=nil, noticePages=nil, remoteId=nil, remoteMap=nil, peerPos=nil,
  lastPosKey=nil, localReady=nil, peerReady=nil, pendingDepth=nil,
  runActive=false, runDepth=nil, advanceLocal=nil, advancePeer=nil,
  advanceExec=nil, suppressOutbound=false, pendingFloorSnapshots={},
  lastMonsterSig=nil, tradeSeq=0, outgoingTrade=nil, incomingTrade=nil,
  tradePromptPending=false, peerBattle=nil, partnerTalkGuard=false,
  pokeSwapSeq=0, outgoingPokeSwap=nil, incomingPokeSwap=nil, pokeSwapPromptPending=false,
  peerCheckpoint=nil, resumeLocal=nil, resumePeer=nil, resumePromptPending=false, orphanedRun=false,
  spectateSeq=0, spectating=nil, spectateServing=nil,
}

local function resetRunState()
  S.localReady=nil; S.peerReady=nil; S.pendingDepth=nil
  S.runActive=false; S.runDepth=nil
  S.advanceLocal=nil; S.advancePeer=nil; S.advanceExec=nil
  S.pendingFloorSnapshots={}
  S.lastMonsterSig=nil
  S.outgoingTrade=nil; S.incomingTrade=nil; S.tradePromptPending=false
  S.outgoingPokeSwap=nil; S.incomingPokeSwap=nil; S.pokeSwapPromptPending=false
  S.peerBattle=nil
  S.notice=nil; S.noticePages=nil
  S.spectating=nil; S.spectateServing=nil
  S.resumeLocal=nil; S.resumePeer=nil; S.resumePromptPending=false; S.orphanedRun=false
end

local function isPartnerDef(def)
  return def and def.coopPartner==true and def.name=="PD_COOP_PARTNER"
end

-- Runtime object ids are derived from the generated object's numeric index.
-- PEWTER_DUNGEON_FLOOR replaces its entire object list at every depth, so an
-- old partner id can later name a completely different generated actor (most
-- visibly the B10 Scientist). Never remove or reuse an id unless the object
-- still carries our explicit co-op identity marker.
local function removeRemote()
  if C and C.mod and C.mod.world then
    local game=C.mod.game
    local world=game and game.world
    local ids={}
    local seen={}
    if world and world.maps then
      for mapId,def in pairs(world.maps) do
        for _,obj in ipairs((def and def.objects) or {}) do
          if obj.runtime and isPartnerDef(obj) then
            local id=tostring(mapId).."_obj_"..tostring(obj.index)
            if not seen[id] then seen[id]=true; ids[#ids+1]=id end
          end
        end
      end
    end
    -- Only trust the cached id as a fallback when the live handle itself still
    -- identifies as the partner. This prevents a recycled Scientist id from
    -- being deleted during a same-map B9 -> B10 transition.
    if #ids==0 and S.remoteId and S.remoteMap then
      local ok,h=pcall(C.mod.world.npc,C.mod.world,S.remoteMap,S.remoteId)
      if ok and h and h.npc and isPartnerDef(h.npc.def) then ids[1]=S.remoteId end
    end
    for _,id in ipairs(ids) do pcall(C.mod.world.removeNpc,C.mod.world,id) end

    -- If the floor definition was already replaced, the old actor can exist
    -- only as an orphaned live NPC. Strip that marked ghost directly; unlike
    -- index-based removal this cannot touch a generated Scientist/trainer/etc.
    if world then
      local function strip(list)
        local out={}
        for _,npc in ipairs(list or {}) do
          if not (npc and isPartnerDef(npc.def)) then out[#out+1]=npc end
        end
        return out
      end
      world.npcs=strip(world.npcs)
      world.entities=strip(world.entities)
      if world.peopleFromMap then
        for npc in pairs(world.peopleFromMap) do
          if npc and isPartnerDef(npc.def) then world.peopleFromMap[npc]=nil end
        end
      end
    end
  end
  S.remoteId=nil; S.remoteMap=nil
end

local function closeNet()
  removeRemote()
  if S.net then pcall(S.net.close,S.net) end
  S.net=nil; S.role=nil; S.helloSent=false; S.helloClock=0; S.peerHello=nil; S.ready=false
  S.peerPos=nil; S.lastPosKey=nil; S.error=nil; S.peerBattle=nil; S.partnerTalkGuard=false
  S.spectating=nil; S.spectateServing=nil
  S.outgoingPokeSwap=nil; S.incomingPokeSwap=nil; S.pokeSwapPromptPending=false
  S.peerCheckpoint=nil
  resetRunState()
end

local function hashStep(h,text)
  text=tostring(text or "")
  for i=1,#text do h=(h*131+text:byte(i))%2147483647 end
  return h
end

local function contentFingerprint(game)
  local h=104729
  local ids={}
  for id in pairs((game.data and game.data.pokemon) or {}) do ids[#ids+1]=id end
  table.sort(ids)
  for _,id in ipairs(ids) do
    local d=game.data.pokemon[id] or {}
    h=hashStep(h,id); h=hashStep(h,d.index)
    for _,t in ipairs(d.types or {}) do h=hashStep(h,t) end
    local b=d.baseStats or {}
    for _,k in ipairs({"hp","attack","defense","speed","specialAttack","specialDefense","special"}) do
      h=hashStep(h,b[k])
    end
  end
  local tms={}
  for id,d in pairs((game.data and game.data.items) or {}) do
    if type(d)=="table" and type(d.machine)=="table" and d.machine.kind=="TM" then
      tms[#tms+1]=id
    end
  end
  table.sort(tms)
  for _,id in ipairs(tms) do
    local d=game.data.items[id] or {}; local m=d.machine or {}
    h=hashStep(h,id); h=hashStep(h,m.move or m.moveId or d.move)
  end
  return tostring(h)..":"..tostring(#ids)..":"..tostring(#tms)
end

local function coopProfile(game)
  return {
    engine=2,
    version="crystal",
    engineVersion=(Version and Version.engine) or "0.3.8",
    apiVersion=(Version and Version.modApi) or 2,
    fingerprint=contentFingerprint(game),
    rulesetId="gen2",
    -- The relay validates room profiles through ArenaBoot, whose supported
    -- kinds are "vanilla" and "cart".  Dungeon Delvers still performs its
    -- own exact mod/fingerprint handshake once paired, but the transport room
    -- itself must use a relay-valid profile kind.
    kind="vanilla",
    -- The relay will not forward room_msg traffic until both seats send
    -- room_ready.  We only need the ready packet to activate the transport,
    -- so use a one-Pokemon rule and submit one real party member per client.
    rule={partySize=1,minLevel=1,maxLevel=100},
  }
end

-- Online co-op rides gen1recomp's persistent v2 relay Client.  The relay uses
-- opaque room ids (r + 16 hex digits), so Dungeon Delvers exposes the last six
-- hex digits as a human-sized join code.  JOIN ONLINE scans the current relay
-- lobby for the matching open room and then joins by the real room id.
--
-- RoomSession only accepts engine-sanctioned wire message types.  DEV107/108
-- tunneled Delvers packets through game3_mg_input, which survives the local
-- fake relay but is a Gen-3 message inside an engine-2 Crystal room.  The live
-- relay can filter that mismatch.  DEV109 instead uses the native Gen-1/2
-- records message as a small typed key/value envelope.  Every Delvers packet is
-- shallow, so this keeps the full payload without borrowing a Gen-3 protocol.
local CODE_LEN=6
local CODE_CHARS="0123456789ABCDEF"
local DD_WIRE_MARK="DDELVE1"

local function encodeDD(msg)
  if type(msg)~="table" then return nil end
  local fields={__dd=DD_WIRE_MARK}
  for k,v in pairs(msg) do
    if type(k)=="string" then
      local tv=type(v)
      if tv=="string" then
        fields[k]="s:"..v
      elseif tv=="number" then
        fields[k]="n:"..tostring(v)
      elseif tv=="boolean" then
        fields[k]=v and "b:1" or "b:0"
      end
    end
  end
  return {type="records",pokemon=fields,moves={}}
end

local function decodeDD(wire)
  if type(wire)~="table" or wire.type~="records" then return nil end
  local fields=wire.pokemon
  if type(fields)~="table" or fields.__dd~=DD_WIRE_MARK then return nil end
  local msg={}
  for k,v in pairs(fields) do
    if k~="__dd" and type(k)=="string" and type(v)=="string" then
      local tag=v:sub(1,2)
      local body=v:sub(3)
      if tag=="s:" then msg[k]=body
      elseif tag=="n:" then msg[k]=tonumber(body)
      elseif tag=="b:" then msg[k]=(body=="1")
      end
    end
  end
  if type(msg.type)~="string" or msg.type:sub(1,3)~="dd_" then return nil end
  return msg
end

local function roomCode(roomId)
  local id=tostring(roomId or ""):lower()
  local hex=id:match("^r([0-9a-f]+)$")
  if not hex or #hex<CODE_LEN then return nil end
  return hex:sub(-CODE_LEN):upper()
end

local function normalizeCode(code)
  local out={}
  for ch in tostring(code or ""):upper():gmatch(".") do
    if CODE_CHARS:find(ch,1,true) then
      out[#out+1]=ch
      if #out>=CODE_LEN then break end
    end
  end
  return table.concat(out)
end

local function playerName(game)
  local save=game and game.save or {}
  return tostring((save.player and save.player.name) or "DELVER"):sub(1,16)
end

-- The v2 relay only opens room_msg traffic after both players send room_ready.
-- Dungeon Delvers does not use the relay's battle party, but room_ready itself
-- is still validated against the room rule.  Submit one real, non-egg party
-- Pokemon so the room can enter its active match state without touching the
-- player's actual team or the Delvers rental selection.
local function relayReadyParty(game)
  local party=(game and game.save and game.save.party) or {}
  local mon=nil
  for _,candidate in ipairs(party) do
    if type(candidate)=="table" and not candidate.isEgg then mon=candidate; break end
  end
  mon=mon or party[1]
  if type(mon)~="table" then return nil,"You need a Pokemon in your party to start online co-op." end
  local ok,packed=pcall(Protocol.packMon2,mon)
  if not ok or type(packed)~="table" then
    return nil,"Could not prepare the online co-op link."
  end
  return {packed}
end

local function relayTransport(game,role,code)
  local profile=coopProfile(game)
  local wanted=normalizeCode(code)
  local t={role=role,paired=false,wireOpen=false,readySent=false,closed=false,error=nil,address=nil,profile=profile,
    pending=nil,session=nil,roomId=nil,wanted=wanted,created=false,joined=false,
    online=false,scanClock=0,waitClock=0,advertised=false,status="CONNECTING TO RELAY"}

  -- Client is a process singleton.  A fresh Delvers connection intentionally
  -- owns it until close(), so stale launcher/previous-room state cannot leak in.
  pcall(Client.reset)
  local ok,err=Client.connect({
    name=playerName(game),
    profiles={profile},
    presence={where="game",status="recruiting",version=tostring(C.version or ""),engine=2},
  })
  if not ok then
    t.closed=true; t.error=tostring(err or Client.error() or "Could not reach the online relay.")
    return t
  end

  local function fail(self,text)
    self.error=tostring(text or Client.error() or "Online co-op connection failed.")
    self.closed=true
    pcall(Client.disconnect)
  end

  local function attach(self)
    local room=Client.room and Client.room() or nil
    if not room or not room.room then return false end
    self.roomId=room.room
    self.address=roomCode(room.room)
    self.session=Client.roomSession and Client.roomSession() or nil
    if not self.session then return false end
    local players=room.players or {}
    self.paired=#players>=2
    self.wireOpen=(room.stage=="battling") or (self.session.match and self.session:match()~=nil)
    if self.wireOpen then
      self.status="LINK OPEN - HANDSHAKING"
    elseif self.paired then
      self.status=self.readySent and "OPENING CO-OP LINK" or "PARTNER IN ROOM"
    elseif self.role=="host" then
      self.status="WAITING FOR PARTNER"
    else
      self.status="JOINED - WAITING FOR HOST"
    end
    -- Public Gen 2 rooms normally appear in the relay lobby on their own.
    -- Advertising as well gives the room an explicit DD marker and keeps
    -- discovery reliable on relay builds that filter non-battle room rows.
    if self.role=="host" and self.address and not self.advertised then
      self.advertised=true
      if Client.advertise then
        pcall(Client.advertise,"trade",self.profile,"DDELVE:"..self.address)
      end
    end
    return true
  end

  local function findRoom(self)
    if self.wanted=="" or #self.wanted~=CODE_LEN then return nil end
    local seen={}
    local candidates={}
    local function add(list)
      for _,entry in ipairs(list or {}) do
        if type(entry)=="table" then
          local key=tostring(entry.room or "").."|"..tostring(entry.id or "")
          if not seen[key] then
            seen[key]=true
            candidates[#candidates+1]=entry
          end
        end
      end
    end
    -- openRooms() is the normal path, but some relay room intents are not
    -- exposed there even though their lobby entry still carries the room id.
    add((Client.openRooms and Client.openRooms()) or {})
    add((Client.lobby and Client.lobby()) or {})

    local exact=nil
    for _,entry in ipairs(candidates) do
      local rid=entry and entry.room
      local note=tostring(entry and entry.note or ""):upper()
      local codeMatch=roomCode(rid)==self.wanted or note:find("DDELVE:"..self.wanted,1,true)~=nil
      if rid and codeMatch then
        -- Prefer a Gen 2 / matching-fingerprint room.  The explicit Delvers
        -- hello still performs the final build/setup compatibility check.
        local p=entry.profile or {}
        if tonumber(entry.engine or p.engine)==2 and tostring(p.fingerprint or "")==tostring(profile.fingerprint or "") then
          return entry
        end
        exact=exact or entry
      end
    end
    return exact
  end

  function t:update(dt)
    if self.closed then return end
    Client.update(dt or 0)
    local state=Client.state and Client.state() or "error"
    if state=="error" then return fail(self,Client.error()) end
    if state=="offline" then return fail(self,"The online relay disconnected.") end
    if state~="online" then
      self.status="CONNECTING TO RELAY"
      return
    end
    self.online=true

    if self.role=="host" and not self.created then
      self.status="CREATING ROOM"
      self.created=true
      -- Use a Gen-2-native room intent.  DEV107 used chat, which can exist as
      -- a room but is not consistently surfaced in the Gen 2 open-room list.
      self.pending=Client.createRoom({
        intent="trade", profile=self.profile, playing=true, maxSpectators=0,
        private=false, seats=2, auto=false, note="DUNGEON DELVERS",
      })
    elseif self.role=="guest" and not self.joined then
      self.status="SEARCHING FOR ROOM"
      self.waitClock=(self.waitClock or 0)+(tonumber(dt) or 0)
      local entry=findRoom(self)
      if entry then
        self.status="ROOM FOUND - JOINING"
        self.joined=true
        self.pending=Client.joinRoom(entry.room,"player",self.profile)
      else
        if self.waitClock>=20 then return fail(self,"Room code not found. Check the code and make sure the host is still waiting.") end
        self.scanClock=(self.scanClock or 0)+(tonumber(dt) or 0)
        if self.scanClock>=0.5 then
          self.scanClock=0
          if Client.sendRaw then Client.sendRaw({type="lobby_query"}) end
        end
      end
    elseif self.role=="guest" and self.joined and self.pending and not self.pending.done then
      self.status="JOIN REQUEST SENT"
    end

    if self.pending and self.pending.done and self.pending.error then
      return fail(self,self.pending.error)
    end
    attach(self)

    -- A live v2 relay only forwards room_msg packets while the room is in its
    -- active match state.  Pairing alone is not enough: both seated players
    -- must send room_ready first.  DEV109 skipped this, so its hello retries
    -- were correctly sanitized but silently dropped by the real relay.
    if self.paired and not self.readySent then
      local packed,why=relayReadyParty(game)
      if not packed then return fail(self,why) end
      self.readySent=true
      self.status="OPENING CO-OP LINK"
      Client.ready(packed,"DDELVE-"..tostring(contentFingerprint(game)))
    end

    -- room_ready causes a new room_state/match_start asynchronously, so refresh
    -- once more after the pump on later frames.  wireOpen gates every custom
    -- packet until the relay says the match really exists.
    attach(self)
  end

  function t:send(msg)
    if self.closed or not self.session or not self.wireOpen or type(msg)~="table" then return end
    local wire=encodeDD(msg)
    if wire then self.session:send(wire) end
  end

  function t:poll()
    if self.closed or not self.session then return {} end
    local out={}
    for _,wire in ipairs(self.session:poll() or {}) do
      local msg=decodeDD(wire)
      if msg then out[#out+1]=msg end
    end
    return out
  end

  function t:close()
    if self._closedClean then return end
    self._closedClean=true
    self.closed=true
    if self.role=="host" and self.advertised and Client.unadvertise then pcall(Client.unadvertise) end
    if self.session then pcall(self.session.close,self.session) end
    pcall(Client.disconnect)
  end

  return t
end

local function codeDigits(code)
  code=normalizeCode(code)
  local out={}
  for i=1,CODE_LEN do
    local ch=code:sub(i,i)
    local n=tonumber(ch,16)
    out[i]=n or 0
  end
  return out
end

local function digitsCode(digits)
  local out={}
  for i=1,CODE_LEN do
    local n=math.max(0,math.min(15,tonumber(digits[i]) or 0))
    out[i]=("%X"):format(n)
  end
  return table.concat(out)
end

local function checkpointMeta(game)
  if not (C and C.checkpointMeta) then return nil end
  local ok,meta=pcall(C.checkpointMeta,game)
  if not ok or type(meta)~="table" or not meta.id or not meta.floor or not meta.seed then return nil end
  return {id=tostring(meta.id),floor=tonumber(meta.floor),seed=tonumber(meta.seed),start=tonumber(meta.start) or 1}
end

local function checkpointFromMessage(msg)
  if type(msg)~="table" or type(msg.cpId)~="string" or msg.cpId=="" then return nil end
  local floor,seed=tonumber(msg.cpFloor),tonumber(msg.cpSeed)
  if not floor or not seed then return nil end
  return {id=msg.cpId,floor=floor,seed=seed,start=tonumber(msg.cpStart) or 1}
end

local function checkpointMatches(a,b)
  return type(a)=="table" and type(b)=="table"
    and tostring(a.id or "")==tostring(b.id or "")
    and tonumber(a.floor)==tonumber(b.floor)
    and tonumber(a.seed)==tonumber(b.seed)
    and tonumber(a.start or 1)==tonumber(b.start or 1)
end

local function addCheckpointFields(msg,meta)
  msg.cpId=meta and tostring(meta.id or "") or ""
  msg.cpFloor=meta and tonumber(meta.floor) or 0
  msg.cpSeed=meta and tonumber(meta.seed) or 0
  msg.cpStart=meta and tonumber(meta.start) or 0
  return msg
end

local function localHello(game,kind)
  local unlocks=C.unlocks and C.unlocks(game) or {}
  local save=game.save or {}
  local hello={
    type=kind or "dd_hello", protocol=PROTOCOL, version=C.version,
    fingerprint=contentFingerprint(game),
    name=(save.player and save.player.name) or "PARTNER",
    gender=(save.player and save.player.gender) or "male",
    works=unlocks.works and true or false,
    megalith=unlocks.megalith and true or false,
  }
  return addCheckpointFields(hello,checkpointMeta(game))
end

local function send(msg)
  if S.net and not S.net.closed then S.net:send(msg) end
end

local function setError(text)
  S.error=tostring(text or "Co-op error")
end

local function validateHello(game,msg)
  if tonumber(msg.protocol)~=PROTOCOL then return false,"Co-op protocol mismatch." end
  if tostring(msg.version or "")~=tostring(C.version or "") then
    return false,"Dungeon Delvers builds do not match."
  end
  if tostring(msg.fingerprint or "")~=contentFingerprint(game) then
    return false,"Pokemon data/mod setup does not match."
  end
  return true
end

local function peerSprite()
  return S.peerHello and S.peerHello.gender=="female" and "SPRITE_KRIS" or "SPRITE_CHRIS"
end

local function samePeerMap(game)
  local world=game and game.world
  local pos=S.peerPos
  if not (world and world.map and pos and pos.map==world.map.id) then return false end
  if pos.map==C.floorMap then
    local ds=C.pdSave(game)
    if tonumber(pos.floor)~=tonumber(ds.floor) then return false end
  end
  return true
end

local function spawnRemote(game)
  if not samePeerMap(game) then removeRemote(); return end
  local pos=S.peerPos
  local mapId=pos.map
  if S.remoteId and S.remoteMap==mapId then
    local h=C.mod.world:npc(mapId,S.remoteId)
    if h and h.npc and isPartnerDef(h.npc.def) then return h end
    -- The cached id was recycled by a generated floor rebuild. Do NOT remove
    -- that id here because it now belongs to somebody else. Forget it and find
    -- (or create) the actual marked partner instead.
    S.remoteId=nil; S.remoteMap=nil
  end

  local existing=C.mod.world:npc(mapId,"PD_COOP_PARTNER")
  if existing and existing.npc and isPartnerDef(existing.npc.def) then
    S.remoteId=existing.npc.id; S.remoteMap=mapId
    return existing
  end

  removeRemote()
  local id,err=C.mod.world:spawnNpc(mapId,{
    name="PD_COOP_PARTNER", sprite=peerSprite(), x=pos.x, y=pos.y,
    movement="STAY", radius={x=0,y=0}, hours={-1,-1}, palette=0,type=0,sight=0,
    coopPartner=true,
  })
  if not id then return nil,err end
  S.remoteId=id; S.remoteMap=mapId
  local h=C.mod.world:npc(mapId,id)
  if h then h:setPassable(true); h:placeAt(pos.x,pos.y,pos.facing or "down") end
  return h
end

local function updateRemote(game)
  if not S.ready then removeRemote(); return end
  if not samePeerMap(game) then removeRemote(); return end
  local h=spawnRemote(game)
  if not h then return end
  local npc=h.npc
  local x,y=h:position()
  local px,py=S.peerPos.x,S.peerPos.y
  -- During a partner battle, keep their overworld ghost pinned to the cell
  -- where the encounter began.  This prevents a queued interpolation step from
  -- making the battling player appear to keep walking on the observer's view.
  if S.peerBattle and S.peerBattle.active then
    px=tonumber(S.peerBattle.x) or px
    py=tonumber(S.peerBattle.y) or py
    h:placeAt(px,py,S.peerBattle.facing or S.peerPos.facing or "down")
    return
  end

  -- DEV116 transmits a step as soon as the remote player STARTS moving, not
  -- only after cellX/cellY advance at the end of Crystal's 16-frame walk.
  -- Mirror that step with the engine's real NPC interpolation so the partner
  -- walks with the normal leg frames instead of teleporting one tile at a time.
  if S.peerPos.moving and S.peerPos.tx~=nil and S.peerPos.ty~=nil then
    local tx,ty=tonumber(S.peerPos.tx),tonumber(S.peerPos.ty)
    local dx,dy=tx-px,ty-py
    local dir
    if math.abs(dx)+math.abs(dy)==1 then
      if dx==1 then dir="right" elseif dx==-1 then dir="left"
      elseif dy==1 then dir="down" else dir="up" end
    end
    if dir then
      if npc and npc.moving and tonumber(npc.targetX)==tx and tonumber(npc.targetY)==ty then
        return -- already animating this exact remote step
      end
      if x==tx and y==ty then
        h:face(S.peerPos.facing or dir)
        return
      end
      if x~=px or y~=py then h:placeAt(px,py,S.peerPos.facing or dir) end
      if npc then npc.stepFrames=math.max(1,tonumber(S.peerPos.frames) or 16) end
      h:stepNow(dir)
      return
    end
  end

  -- The stopped packet normally arrives while our mirrored step is still
  -- completing.  If it is already heading to the reported final cell, let the
  -- animation finish naturally instead of snapping the last few pixels.
  if npc and npc.moving and tonumber(npc.targetX)==tonumber(px) and tonumber(npc.targetY)==tonumber(py) then
    return
  end
  if x==px and y==py then
    h:face(S.peerPos.facing or "down")
    return
  end
  local dx,dy=px-x,py-y
  local dir
  if math.abs(dx)+math.abs(dy)==1 then
    if dx==1 then dir="right" elseif dx==-1 then dir="left"
    elseif dy==1 then dir="down" else dir="up" end
  end
  if dir and not (npc and npc.moving) then
    if npc then npc.stepFrames=16 end
    h:stepNow(dir)
  else
    h:placeAt(px,py,S.peerPos.facing or "down")
  end
end

local function sendPosition(game)
  if not S.ready then return end
  local world=game and game.world
  if not (world and world.map and world.player) then return end
  local mapId=world.map.id
  if mapId~=C.lobbyMap and mapId~=C.floorMap then return end
  local ds=C.pdSave(game)
  local floor=(mapId==C.floorMap) and tonumber(ds.floor) or 0
  local p=world.player
  local x,y=p.cellX,p.cellY
  local facing=p.facing or "down"
  local moving=p.moving and p.targetX~=nil and p.targetY~=nil
  local tx=moving and p.targetX or nil
  local ty=moving and p.targetY or nil
  local frames=moving and (tonumber(p.stepFrames) or 16) or nil
  local key=table.concat({mapId,tostring(floor),tostring(x),tostring(y),facing,
    moving and "1" or "0",tostring(tx or ""),tostring(ty or ""),tostring(frames or "")},"|")
  if key==S.lastPosKey then return end
  S.lastPosKey=key
  send({type="dd_pos",map=mapId,floor=floor,x=x,y=y,facing=facing,name=playerName(game),
    moving=moving,tx=tx,ty=ty,frames=frames})
end

local function applyPeerEntityRemoval(game,msg)
  if not (S.runActive and tonumber(msg.floor)==tonumber(C.pdSave(game).floor)) then return end
  if C.removeEntityByIndex then
    S.suppressOutbound=true
    pcall(C.removeEntityByIndex,game,tonumber(msg.index),msg.role)
    S.suppressOutbound=false
  end
end

local function applySharedFind(game,msg)
  if not S.runActive then return end
  if msg.kind=="fossil" and C.receiveFossil then
    C.receiveFossil(game,msg.root,msg.part,msg.depth,msg.integrity)
  elseif msg.kind=="item" and C.receiveItem then
    C.receiveItem(game,msg.id,tonumber(msg.qty) or 1)
  end
end

local function maybeBeginHost(game)
  if S.role~="host" or not (S.localReady and S.peerReady) then return end
  if tonumber(S.localReady.depth)~=tonumber(S.peerReady.depth) then
    setError("Partner selected a different delve stratum.")
    return
  end
  local depth=tonumber(S.localReady.depth) or 1
  local seed=C.newSeed and C.newSeed(game) or os.time()
  send({type="dd_begin",depth=depth,seed=seed})
  local species=S.localReady.species
  S.runActive=true; S.runDepth=depth; S.localReady=nil; S.peerReady=nil
  C.startRun(game,species,seed,depth)
end

local function markLocalReady(game,species,depth)
  S.localReady={species=species,depth=depth}
  send({type="dd_ready",species=species,depth=depth})
  if S.role=="host" then maybeBeginHost(game) end
end

local function openPartnerPicker(game,depth)
  if not C.prepareStarter then return end
  C.prepareStarter(game,depth,function(species)
    if not species then
      send({type="dd_prepare_cancel"})
      S.localReady=nil; S.pendingDepth=nil
      return
    end
    markLocalReady(game,species,depth)
    C.showPages(game.world,{"Ready for co-op.","Waiting for your partner."})
  end)
end


local function tradeLabel(game,id,qty)
  local name=(C.itemName and C.itemName(game,id)) or tostring(id or "ITEM")
  return name.." x"..tostring(tonumber(qty) or 1)
end

local function canTradeNow(game)
  return S.ready and S.runActive and samePeerMap(game)
    and game and game.world and not game.world.battleActive
end

local function sendTradeOffer(game,id,qty)
  if not canTradeNow(game) then
    return C.showPages(game.world,{"Stay on the same delve floor to trade."})
  end
  if S.outgoingTrade or S.incomingTrade then
    return C.showPages(game.world,{"Finish the current trade first."})
  end
  qty=math.max(1,math.floor(tonumber(qty) or 1))
  local have=(C.tradeItemQty and C.tradeItemQty(game,id)) or 0
  if have<qty then return C.showPages(game.world,{"You no longer have enough of that item."}) end
  S.tradeSeq=(tonumber(S.tradeSeq) or 0)+1
  local tradeId=(S.role=="host" and "H" or "G")..tostring(S.tradeSeq).."-"..tostring(os.time())
  S.outgoingTrade={id=tradeId,item=id,qty=qty}
  send({type="dd_trade_offer",tradeId=tradeId,item=id,qty=qty,from=playerName(game)})
  C.showPages(game.world,{"Offered "..tradeLabel(game,id,qty)..".","Waiting for "..tostring((S.peerHello and S.peerHello.name) or "PARTNER").."."})
end

local function openTradeQuantityMenu(game,row)
  local qty=math.max(1,tonumber(row and row.qty) or 1)
  local items={
    {label="GIVE 1",onSelect=function() sendTradeOffer(game,row.id,1) end},
  }
  if qty>1 then
    items[#items+1]={label="GIVE ALL x"..tostring(qty),onSelect=function() sendTradeOffer(game,row.id,qty) end}
  end
  items[#items+1]={label="BACK",onSelect=function() end}
  game.stack:push(C.Menu.new(game,items,{tx=5,ty=4,tw=14,rowStep=2,cancelable=true,maxVisible=5}))
end

local function openTradeItemMenu(game)
  if not canTradeNow(game) then
    return C.showPages(game.world,{"Stay on the same delve floor to trade."})
  end
  local rows=(C.tradeItems and C.tradeItems(game)) or {}
  local items={}
  for _,row in ipairs(rows) do
    local copy={id=row.id,qty=row.qty,name=row.name}
    items[#items+1]={label=tostring(copy.name or copy.id).." x"..tostring(copy.qty or 1),onSelect=function()
      openTradeQuantityMenu(game,copy)
    end}
  end
  if #items==0 then
    return C.showPages(game.world,{"You have no tradable PACK items."})
  end
  items[#items+1]={label="BACK",onSelect=function() end}
  game.stack:push(C.Menu.new(game,items,{tx=3,ty=1,tw=17,rowStep=2,cancelable=true,maxVisible=7,title="TRADE ITEM"}))
end

local function pokeName(game,mon)
  if not mon then return "POKEMON" end
  local def=game and game.data and game.data.pokemon and game.data.pokemon[mon.species]
  return tostring(mon.nickname or (def and def.name) or mon.name or mon.species or "POKEMON")
end

local function pokeFingerprint(mon)
  if not mon then return "" end
  local parts={tostring(mon.species or ""),tostring(mon.nickname or ""),tostring(mon.level or 0),
    tostring(mon.experience or 0),tostring(mon.hp or 0),tostring(mon.item or "")}
  for _,k in ipairs({"attack","defense","speed","special"}) do parts[#parts+1]=tostring((mon.dvs or {})[k] or 0) end
  for _,mv in ipairs(mon.moves or {}) do parts[#parts+1]=tostring(mv.id or "")..":"..tostring(mv.pp or 0) end
  for _,id in ipairs(mon._ddIndividualTypes or {}) do parts[#parts+1]=tostring(id) end
  return table.concat(parts,"|")
end

-- Delvers already negotiated an identical Pokemon/move fingerprint at connect
-- time.  Flatten Protocol.packMon2 into primitive dd_* fields so the native
-- Gen-2 records envelope can carry an expedition Pokemon without inventing a
-- second nested wire format.
local function putPackedMon(msg,prefix,mon)
  local packed=Protocol.packMon2(mon)
  local function put(key,value) if value~=nil then msg[prefix..key]=value end end
  put("species",packed.species); put("level",packed.level); put("experience",packed.experience)
  put("hp",packed.hp); put("status",packed.status); put("nickname",packed.nickname); put("item",packed.item)
  put("happiness",packed.happiness); put("pokerus",packed.pokerus); put("caughtLevel",packed.caughtLevel)
  put("caughtTime",packed.caughtTime); put("caughtLocation",packed.caughtLocation)
  put("caughtByGender",packed.caughtByGender); put("ot",packed.ot); put("otId",packed.otId)
  put("isEgg",packed.isEgg and true or false); put("eggSteps",packed.eggSteps)
  for _,k in ipairs({"attack","defense","speed","special"}) do put("dv_"..k,(packed.dvs or {})[k]) end
  for _,k in ipairs({"hp","attack","defense","speed","special"}) do put("se_"..k,(packed.statExp or {})[k]) end
  for i,mv in ipairs(packed.moves or {}) do
    put("move"..i,mv.id); put("pp"..i,mv.pp); put("up"..i,mv.ppUps)
  end
  put("rental",mon._pewterDungeonRental and true or false)
  put("personality",mon.pokesurvivePersonality)
  if type(mon._ddIndividualTypes)=="table" then
    put("ddType1",mon._ddIndividualTypes[1]); put("ddType2",mon._ddIndividualTypes[2])
  end
  return msg
end

local function getPackedMon(game,msg,prefix)
  local species=msg[prefix.."species"]
  if type(species)~="string" or species=="" then return nil,"Missing Pokemon data." end
  local packed={species=species,level=msg[prefix.."level"],experience=msg[prefix.."experience"],
    hp=msg[prefix.."hp"],status=msg[prefix.."status"],nickname=msg[prefix.."nickname"],item=msg[prefix.."item"],
    happiness=msg[prefix.."happiness"],pokerus=msg[prefix.."pokerus"],caughtLevel=msg[prefix.."caughtLevel"],
    caughtTime=msg[prefix.."caughtTime"],caughtLocation=msg[prefix.."caughtLocation"],
    caughtByGender=msg[prefix.."caughtByGender"],ot=msg[prefix.."ot"],otId=msg[prefix.."otId"],
    isEgg=msg[prefix.."isEgg"] and true or nil,eggSteps=msg[prefix.."eggSteps"],dvs={},statExp={},moves={}}
  for _,k in ipairs({"attack","defense","speed","special"}) do packed.dvs[k]=tonumber(msg[prefix.."dv_"..k]) or 0 end
  for _,k in ipairs({"hp","attack","defense","speed","special"}) do packed.statExp[k]=tonumber(msg[prefix.."se_"..k]) or 0 end
  for i=1,4 do
    local id=msg[prefix.."move"..i]
    if type(id)=="string" and id~="" then packed.moves[#packed.moves+1]={id=id,pp=msg[prefix.."pp"..i],ppUps=msg[prefix.."up"..i]} end
  end
  local mon,err=Protocol.unpackMon2(game.data,packed,{strict=true})
  if not mon then return nil,err or "Pokemon could not be reconstructed." end
  if msg[prefix.."rental"] then mon._pewterDungeonRental=true end
  if msg[prefix.."personality"] then mon.pokesurvivePersonality=msg[prefix.."personality"] end
  local t1,t2=msg[prefix.."ddType1"],msg[prefix.."ddType2"]
  local chart=game.data and game.data.type_chart and game.data.type_chart.types
  if type(t1)=="string" and (not chart or chart[t1]) then
    mon._ddIndividualTypes={t1}
    if type(t2)=="string" and t2~=t1 and (not chart or chart[t2]) then mon._ddIndividualTypes[2]=t2 end
    mon.types={mon._ddIndividualTypes[1],mon._ddIndividualTypes[2]}
  end
  return mon
end

local function sendPartyState(game)
  local party=(game.save and game.save.party) or {}
  local msg={type="dd_party_state",count=math.min(3,#party),from=playerName(game)}
  for i=1,msg.count do putPackedMon(msg,"p"..tostring(i).."_",party[i]) end
  send(msg)
end

local function openPeerPartyView(game,msg)
  local party={}
  for i=1,math.max(0,math.min(3,tonumber(msg.count) or 0)) do
    local mon=getPackedMon(game,msg,"p"..tostring(i).."_")
    if mon then party[#party+1]=mon end
  end
  if #party==0 then return C.showPages(game.world,{"Your partner has no Pokemon to show."}) end
  local PartyMenu=require("src.ui.gen2.PartyMenu")
  local SummaryMenu=require("src.ui.gen2.SummaryMenu")
  local peer=tostring(msg.from or (S.peerHello and S.peerHello.name) or "PARTNER")
  local viewer
  viewer=PartyMenu.new(game,{
    party=party,prompt="PARTNER'S PARTY",
    onChoose=function(index,mon)
      game.stack:push(SummaryMenu.new(game,{
        party=party,index=index,save={party=party,player={name=peer,id=0}},
        onClose=function() game.stack:pop() end,
      }))
    end,
    onCancel=function() game.stack:pop() end,
  })
  game.stack:push(viewer)
end

local function requestPeerParty(game)
  if not (S.ready and S.runActive and samePeerMap(game)) then
    return C.showPages(game.world,{"Stay on the same delve floor to view your partner's party."})
  end
  -- Do not open a transient dialogue box here.  PartyMenu is pushed when the
  -- partner reply arrives; leaving a text page underneath it caused that stale
  -- message to reappear after closing the party viewer.
  send({type="dd_party_request"})
end

local function canPokeSwapNow(game)
  return canTradeNow(game) and not S.outgoingPokeSwap and not S.incomingPokeSwap
end

local function partyRows(game)
  local rows={}
  for i,mon in ipairs((game.save and game.save.party) or {}) do
    if type(mon)=="table" and not mon.isEgg then rows[#rows+1]={slot=i,mon=mon} end
  end
  return rows
end

local function sendPokeSwapOffer(game,row)
  if not canPokeSwapNow(game) then return C.showPages(game.world,{"Finish the current swap first."}) end
  S.pokeSwapSeq=(tonumber(S.pokeSwapSeq) or 0)+1
  local swapId=(S.role=="host" and "H" or "G").."P"..tostring(S.pokeSwapSeq).."-"..tostring(os.time())
  local mon=row.mon
  S.outgoingPokeSwap={id=swapId,slot=row.slot,fingerprint=pokeFingerprint(mon),offered=mon}
  local msg={type="dd_pkmn_offer",swapId=swapId,slot=row.slot,from=playerName(game),offerName=pokeName(game,mon)}
  putPackedMon(msg,"a_",mon); send(msg)
  C.showPages(game.world,{"Offered "..pokeName(game,mon)..".","Waiting for "..tostring((S.peerHello and S.peerHello.name) or "PARTNER").."."})
end

local function openPokeSwapPicker(game,onPick,title)
  local rows=partyRows(game); local items={}
  for _,row in ipairs(rows) do
    local copy={slot=row.slot,mon=row.mon}
    local label=pokeName(game,copy.mon).." Lv"..tostring(copy.mon.level or "?")
    items[#items+1]={label=label,onSelect=function() onPick(copy) end}
  end
  if #items==0 then return C.showPages(game.world,{"You have no Pokemon available to swap."}) end
  items[#items+1]={label="BACK",onSelect=function() end}
  game.stack:push(C.Menu.new(game,items,{tx=3,ty=1,tw=17,rowStep=2,cancelable=true,maxVisible=7,title=title or "PKMN SWAP"}))
end

local function openPokeSwapMenu(game)
  if not canPokeSwapNow(game) then
    return C.showPages(game.world,{"Stay together on the same floor and finish any current swap first."})
  end
  openPokeSwapPicker(game,function(row)
    C.showPages(game.world,{"Offer "..pokeName(game,row.mon).." for a partner Pokemon?"},function()
      game.stack:push(C.Menu.new(game,{
        {label="YES",onSelect=function() sendPokeSwapOffer(game,row) end},
        {label="NO",onSelect=function() end},
      },{tx=12,ty=8,tw=8,rowStep=2,cancelable=true}))
    end)
  end,"PKMN SWAP")
end


local function cleanSpectateText(text)
  text=tostring(text or "")
  text=text:gsub("[\r\n\v\f]+"," "):gsub("%s+"," ")
  if #text>60 then text=text:sub(1,60) end
  return text
end

-- The public BattleAPI intentionally exposes semantic battle state rather than
-- renderer internals. Spectating can still mirror the engine's own Gen 2
-- animation scripts by peeking at the live battle screen while we are serving
-- a watcher. Only tiny animation descriptors cross the wire; the spectator
-- runs the same extracted Crystal animation locally.
local function activeGen2BattleScreen(game)
  local states=game and game.stack and game.stack.states or {}
  for i=#states,1,-1 do
    local st=states[i]
    if st and (st.screenId=="Gen2BattleState" or st.isGen2BattleState) then
      return st
    end
  end
  return nil
end

local function liveSpectateAnim(game,serving)
  local screen=activeGen2BattleScreen(game)
  local anim=screen and screen.anim or nil
  if anim and anim.done then
    local ok,done=pcall(anim.done,anim)
    if ok and done then anim=nil end
  end
  if anim~=serving.animObj then
    serving.animObj=anim
    serving.animSeq=(tonumber(serving.animSeq) or 0)+1
    return screen,anim,true
  end
  return screen,anim,false
end

local function spectateTargetLabel(game,pb,e)
  local role=(e and e.role) or (pb and pb.role)
  local species=(e and e.species) or (pb and pb.species)
  if role=="monster" and species then
    local def=game and game.data and game.data.pokemon and game.data.pokemon[species]
    return tostring((def and def.name) or species)
  end
  if role=="trainer" then return "a Delver" end
  return "an opponent"
end

local function putSpectateMon(msg,prefix,mon)
  if type(mon)~="table" then return end
  msg[prefix.."species"]=mon.species
  msg[prefix.."name"]=cleanSpectateText(mon.name or mon.species)
  msg[prefix.."level"]=tonumber(mon.level) or 1
  msg[prefix.."hp"]=tonumber(mon.hp) or 0
  msg[prefix.."maxHp"]=tonumber(mon.maxHp) or math.max(1,tonumber(mon.hp) or 1)
  if mon.status then msg[prefix.."status"]=tostring(mon.status) end
end

local function sendSpectateState(game,force,dt)
  local serving=S.spectateServing
  if not serving then return end
  serving.clock=(tonumber(serving.clock) or 0)+(tonumber(dt) or 0)
  serving.api=serving.api or (Gen2BattleAPI and Gen2BattleAPI.new(game))
  local ok,snap=pcall(function() return serving.api and serving.api:snapshot() end)
  if not ok or not snap then
    send({type="dd_spectate_end",watchId=serving.id})
    S.spectateServing=nil
    return
  end

  local screen,anim,animChanged=liveSpectateAnim(game,serving)
  local rev=tonumber(snap.revision) or 0

  -- The battle engine resolves turn math before Crystal presents it.  Its own
  -- battle HUD deliberately draws from shownHp/shownStatus instead of mon.hp
  -- so damage, healing items and held-item heals do not visibly happen before
  -- their animation/message.  Spectators must mirror that *presentation* state
  -- rather than the already-resolved BattleAPI value.
  local shownPlayerHp=(screen and screen.shownHp and tonumber(screen.shownHp.player))
    or tonumber(snap.player and snap.player.hp) or 0
  local shownEnemyHp=(screen and screen.shownHp and tonumber(screen.shownHp.enemy))
    or tonumber(snap.enemy and snap.enemy.hp) or 0
  local shownPlayerStatus=(screen and screen.shownStatus and screen.shownStatus.player)
  local shownEnemyStatus=(screen and screen.shownStatus and screen.shownStatus.enemy)
  if shownPlayerStatus==false then shownPlayerStatus=nil end
  if shownEnemyStatus==false then shownEnemyStatus=nil end

  local hpAnim=screen and screen.hpAnim or nil
  local hpAnimChanged=(hpAnim~=serving.hpAnimObj)
  if hpAnimChanged then serving.hpAnimObj=hpAnim end

  -- Presentation-only faint state. Gen 2 sinks the fainted picture before the
  -- faint text; BattleAPI's HP=0 alone happens too early for a spectator.
  local faintSlide=screen and screen.faintSlide or nil
  local faintChanged=(faintSlide~=serving.faintObj)
  if faintChanged then
    serving.faintObj=faintSlide
    if faintSlide then serving.faintSeq=(tonumber(serving.faintSeq) or 0)+1 end
  end
  local pHidden=(screen and screen.picHidden and screen.picHidden.player) and true or false
  local eHidden=(screen and screen.picHidden and screen.picHidden.enemy) and true or false
  local hiddenChanged=(pHidden~=serving.lastPlayerHidden) or (eHidden~=serving.lastEnemyHidden)

  local directHudChanged=false
  if not hpAnim then
    directHudChanged=(serving.lastShownPlayerHp~=shownPlayerHp)
      or (serving.lastShownEnemyHp~=shownEnemyHp)
      or (serving.lastShownPlayerStatus~=shownPlayerStatus)
      or (serving.lastShownEnemyStatus~=shownEnemyStatus)
  end

  -- Semantic battle state only needs an occasional keepalive, but animation
  -- starts/ends and the start of Crystal's HP-bar chase must be pushed
  -- immediately.  The latter is the exact moment the real battle allows its
  -- displayed HP to begin changing.
  if not force and rev==serving.lastRevision and not animChanged
      and not hpAnimChanged and not faintChanged and not hiddenChanged
      and not directHudChanged and serving.clock<.7 then return end
  serving.lastRevision=rev; serving.clock=0
  serving.lastShownPlayerHp=shownPlayerHp
  serving.lastShownEnemyHp=shownEnemyHp
  serving.lastShownPlayerStatus=shownPlayerStatus
  serving.lastShownEnemyStatus=shownEnemyStatus
  serving.lastPlayerHidden=pHidden
  serving.lastEnemyHidden=eHidden
  serving.txSeq=(tonumber(serving.txSeq) or 0)+1

  local msg={type="dd_spectate_state",watchId=serving.id,revision=rev,seq=serving.txSeq,
    owner=playerName(game),kind=snap.kind or "battle",prompt=snap.prompt or "locked",
    turn=tonumber(snap.turn) or 0,
    animSeq=tonumber(serving.animSeq) or 0,
    animActive=anim and true or false}
  local shownPlayer=(screen and screen.shownMon and screen.shownMon.player) or snap.player
  local shownEnemy=(screen and screen.shownMon and screen.shownMon.enemy) or snap.enemy
  putSpectateMon(msg,"p_",shownPlayer)
  putSpectateMon(msg,"e_",shownEnemy)
  msg.p_hp=shownPlayerHp
  msg.e_hp=shownEnemyHp
  msg.p_status=shownPlayerStatus
  msg.e_status=shownEnemyStatus

  -- When Crystal begins AnimateHPBar, send its final target separately.  The
  -- spectator waits until its locally replayed attack/effect animation is over
  -- before chasing this value, preventing network timing from spoiling damage
  -- or healing a few frames early.
  if hpAnim and hpAnim.side and hpAnim.to~=nil then
    msg.hpAnimSide=tostring(hpAnim.side)
    msg.hpAnimTo=tonumber(hpAnim.to)
  end

  msg.faintSeq=tonumber(serving.faintSeq) or 0
  msg.faintActive=faintSlide and true or false
  if faintSlide then
    msg.faintSide=tostring(faintSlide.side or "")
    msg.faintFrame=tonumber(faintSlide.frames) or 0
  end
  msg.p_hidden=pHidden
  msg.e_hidden=eHidden

  if type(snap.message)=="table" then
    msg.msg1=cleanSpectateText(snap.message[1])
    msg.msg2=cleanSpectateText(snap.message[2])
  end
  if anim then
    local animId=anim.animId
    if animId~=nil then msg.animId=tostring(animId) end
    msg.animTurn=tonumber(anim.env and anim.env.battleTurn) or 0
    msg.animParam=tonumber(anim.param) or 0
    msg.animFrame=tonumber(anim.frames) or 0
    local pools=screen and screen.anims
    msg.animIsMove=(pools and pools.moves and animId~=nil and pools.moves[animId]~=nil) and true or false
  end
  send(msg)
end

local function beginSpectating(game,e)
  local pb=Coop.peerBattleInfo(game)
  if not pb then return C.showPages(game.world,{"That battle has already ended."}) end
  if e and tonumber(pb.index)~=tonumber(e.index) then
    return C.showPages(game.world,{"That is not your partner's current battle."})
  end
  S.spectateSeq=(tonumber(S.spectateSeq) or 0)+1
  local watchId=(S.role=="host" and "H" or "G").."W"..tostring(S.spectateSeq).."-"..tostring(os.time())
  S.spectating={id=watchId,owner=tostring(pb.by or (S.peerHello and S.peerHello.name) or "PARTNER"),
    target=spectateTargetLabel(game,pb,e),snapshot=nil,ended=false}
  send({type="dd_spectate_request",watchId=watchId,floor=tonumber(C.pdSave(game).floor) or 0})
  if Spectator then Spectator.open(game) end
end

local function promptSpectate(game,e,skipIntro)
  local pb=Coop.peerBattleInfo(game)
  if not pb then return false end
  if e and tonumber(pb.index)~=tonumber(e.index) then return false end
  local peer=tostring(pb.by or (S.peerHello and S.peerHello.name) or "PARTNER")
  local target=spectateTargetLabel(game,pb,e)
  local function ask()
    C.showPages(game.world,{"Watch the battle?"},function()
      game.stack:push(C.Menu.new(game,{
        {label="YES",onSelect=function() beginSpectating(game,e) end},
        {label="NO",onSelect=function() end},
      },{tx=12,ty=8,tw=8,rowStep=2,cancelable=true}))
    end)
  end
  if skipIntro then ask()
  else C.showPages(game.world,{peer.." is battling "..target.."."},ask) end
  return true
end

local function stopSpectating(game)
  if S.spectating then send({type="dd_spectate_stop",watchId=S.spectating.id}) end
  S.spectating=nil
end

local function finishSpectating(game)
  S.spectating=nil
end

local function openPartnerMenu(game)
  local peer=tostring((S.peerHello and S.peerHello.name) or "PARTNER")
  if S.runActive and S.peerBattle and S.peerBattle.active and samePeerMap(game) then
    return promptSpectate(game,nil,false)
  end
  if not S.runActive then
    return C.showPages(game.world,{peer.." is your co-op partner."})
  end
  local items={
    {label="VIEW PARTY",onSelect=function() requestPeerParty(game) end},
    {label="TRADE ITEM",onSelect=function() openTradeItemMenu(game) end},
    {label="PKMN SWAP",onSelect=function() openPokeSwapMenu(game) end},
    {label="PARTNER",onSelect=function() C.showPages(game.world,{"Delving with "..peer.."."}) end},
    {label="BACK",onSelect=function() end},
  }
  game.stack:push(C.Menu.new(game,items,{tx=5,ty=3,tw=14,rowStep=2,cancelable=true,maxVisible=6}))
end

local function promptIncomingTrade(game)
  local tr=S.incomingTrade
  if not tr or not canTradeNow(game) then return end
  S.tradePromptPending=false
  local peer=tostring(tr.from or (S.peerHello and S.peerHello.name) or "PARTNER")
  local label=tradeLabel(game,tr.item,tr.qty)
  C.showPages(game.world,{peer.." offers "..label..".","Accept the item?"},function()
    game.stack:push(C.Menu.new(game,{
      {label="YES",onSelect=function()
        local ok=(C.canReceiveTrade and C.canReceiveTrade(game,tr.item,tr.qty))
        if not ok then
          send({type="dd_trade_decline",tradeId=tr.id,reason="Partner's PACK cannot hold it."})
          S.incomingTrade=nil
          return C.showPages(game.world,{"Your PACK cannot hold "..label.."."})
        end
        send({type="dd_trade_accept",tradeId=tr.id})
        C.showPages(game.world,{"Trade accepted.","Waiting for the item..."})
      end},
      {label="NO",onSelect=function()
        send({type="dd_trade_decline",tradeId=tr.id,reason=peer.." declined the trade."})
        S.incomingTrade=nil
      end},
    },{tx=12,ty=8,tw=8,rowStep=2,cancelable=true}))
  end)
end

local function promptIncomingPokeSwap(game)
  local tr=S.incomingPokeSwap
  if not tr or not canTradeNow(game) then return end
  S.pokeSwapPromptPending=false
  local peer=tostring(tr.from or (S.peerHello and S.peerHello.name) or "PARTNER")
  C.showPages(game.world,{peer.." offers "..pokeName(game,tr.mon)..".","Choose a Pokemon to swap?"},function()
    game.stack:push(C.Menu.new(game,{
      {label="YES",onSelect=function()
        openPokeSwapPicker(game,function(row)
          tr.localSlot=row.slot; tr.localFingerprint=pokeFingerprint(row.mon); tr.localMon=row.mon
          local out={type="dd_pkmn_counter",swapId=tr.id,slot=row.slot,offerName=pokeName(game,row.mon)}
          putPackedMon(out,"b_",row.mon); send(out)
          C.showPages(game.world,{"Offered "..pokeName(game,row.mon).." back.","Waiting for "..peer.."."})
        end,"SWAP FOR")
      end},
      {label="NO",onSelect=function()
        send({type="dd_pkmn_decline",swapId=tr.id,reason=peer.." declined the Pokemon swap."})
        S.incomingPokeSwap=nil
      end},
    },{tx=12,ty=8,tw=8,rowStep=2,cancelable=true}))
  end)
end

local function handle(game,msg)
  if type(msg)~="table" then return end
  if msg.type=="dd_hello" or msg.type=="dd_hello_ack" then
    local ok,why=validateHello(game,msg)
    if not ok then
      send({type="dd_reject",reason=why}); setError(why); return
    end
    S.peerHello=msg; S.peerCheckpoint=checkpointFromMessage(msg); S.ready=true
    -- The ACK carries our full hello data too.  This closes the asymmetric case
    -- where only one side's first hello made it through, without creating an
    -- endless hello/hello echo loop.
    if msg.type=="dd_hello" then send(localHello(game,"dd_hello_ack")) end
  elseif msg.type=="dd_reject" then
    setError(msg.reason or "Partner rejected the connection.")
  elseif msg.type=="dd_unlocks" then
    S.peerHello=S.peerHello or {}
    S.peerHello.works=msg.works and true or false
    S.peerHello.megalith=msg.megalith and true or false
  elseif msg.type=="dd_checkpoint_meta" then
    S.peerCheckpoint=checkpointFromMessage(msg)
  elseif msg.type=="dd_checkpoint_prepare" then
    if S.resumePromptPending then return end
    local world=game.world
    local localCp=checkpointMeta(game)
    local wanted={id=tostring(msg.cpId or ""),floor=tonumber(msg.cpFloor),seed=tonumber(msg.cpSeed),start=tonumber(msg.cpStart) or 1}
    if S.role~="guest" or not (world and world.map and world.map.id==C.lobbyMap) or C.isActive(game)
        or not checkpointMatches(localCp,wanted) then
      send({type="dd_checkpoint_refuse",reason="Matching co-op checkpoint is not available."})
      return
    end
    S.resumeLocal=localCp; S.resumePromptPending=true
    local peer=tostring((S.peerHello and S.peerHello.name) or "HOST")
    C.showPages(world,{peer.." wants to resume the shared delve at B"..tostring(localCp.floor).."."},function()
      game.stack:push(C.Menu.new(game,{
        {label="CONTINUE",onSelect=function()
          S.resumePromptPending=false
          if not checkpointMatches(checkpointMeta(game),S.resumeLocal) then
            S.resumeLocal=nil
            send({type="dd_checkpoint_refuse",reason="Checkpoint changed before resuming."})
            return C.showPages(game.world,{"That checkpoint is no longer available."})
          end
          send(addCheckpointFields({type="dd_checkpoint_ready"},S.resumeLocal))
          C.showPages(game.world,{"Shared checkpoint ready.","Waiting for the host."})
        end},
        {label="NOT NOW",onSelect=function()
          S.resumePromptPending=false; S.resumeLocal=nil
          send({type="dd_checkpoint_refuse",reason="Partner declined the shared checkpoint."})
        end},
      },{tx=7,ty=7,tw=12,rowStep=2,cancelable=false}))
    end)
  elseif msg.type=="dd_checkpoint_ready" then
    if S.role~="host" or not S.resumeLocal then return end
    local peerCp=checkpointFromMessage(msg)
    local localCp=checkpointMeta(game)
    if not (checkpointMatches(peerCp,S.resumeLocal) and checkpointMatches(localCp,S.resumeLocal)) then
      S.resumeLocal=nil; S.resumePeer=nil
      return setError("Shared checkpoint changed before resuming.")
    end
    S.resumePeer=peerCp
    local begin=addCheckpointFields({type="dd_checkpoint_begin"},localCp)
    S.runActive=true; S.runDepth=localCp.floor
    send(begin)
    local ok=C.resumeCheckpoint and C.resumeCheckpoint(game,localCp.id,localCp.floor,localCp.seed,localCp.start)
    if ok==false then
      S.runActive=false; S.runDepth=nil
      send({type="dd_checkpoint_abort",reason="Host could not restore the shared checkpoint."})
    end
    S.resumeLocal=nil; S.resumePeer=nil
  elseif msg.type=="dd_checkpoint_begin" then
    if S.role~="guest" then return end
    local wanted=checkpointFromMessage(msg)
    local localCp=checkpointMeta(game)
    if not checkpointMatches(localCp,wanted) then
      S.resumeLocal=nil
      return setError("Matching co-op checkpoint is no longer available.")
    end
    S.runActive=true; S.runDepth=localCp.floor
    local ok=C.resumeCheckpoint and C.resumeCheckpoint(game,localCp.id,localCp.floor,localCp.seed,localCp.start)
    if ok==false then S.runActive=false; S.runDepth=nil end
    S.resumeLocal=nil; S.resumePeer=nil; S.resumePromptPending=false
  elseif msg.type=="dd_checkpoint_refuse" or msg.type=="dd_checkpoint_abort" then
    S.resumeLocal=nil; S.resumePeer=nil; S.resumePromptPending=false
    S.notice=msg.reason or "Shared checkpoint was not resumed."
  elseif msg.type=="dd_pos" then
    S.peerPos={map=msg.map,floor=msg.floor,x=tonumber(msg.x) or 0,y=tonumber(msg.y) or 0,facing=msg.facing,
      name=tostring(msg.name or (S.peerHello and S.peerHello.name) or "PARTNER"),
      moving=msg.moving and true or false,tx=tonumber(msg.tx),ty=tonumber(msg.ty),frames=tonumber(msg.frames)}
    updateRemote(game)
  elseif msg.type=="dd_prepare" then
    local world=game.world
    if not (world and world.map and world.map.id==C.lobbyMap) or C.isActive(game) then
      send({type="dd_prepare_refuse",reason="Partner is not ready at the delve desk."})
      return
    end
    S.pendingDepth=tonumber(msg.depth) or 1
    S.localReady=nil; S.peerReady=nil
    openPartnerPicker(game,S.pendingDepth)
  elseif msg.type=="dd_prepare_refuse" then
    setError(msg.reason or "Partner is not ready.")
  elseif msg.type=="dd_prepare_cancel" then
    S.peerReady=nil; S.pendingDepth=nil
    S.notice="Partner cancelled the co-op delve."
  elseif msg.type=="dd_ready" then
    S.peerReady={species=msg.species,depth=tonumber(msg.depth) or 1}
    if S.role=="host" then maybeBeginHost(game) end
  elseif msg.type=="dd_begin" then
    if S.role~="guest" or not S.localReady then return end
    local depth=tonumber(msg.depth) or 1
    local species=S.localReady.species
    S.runActive=true; S.runDepth=depth; S.localReady=nil; S.peerReady=nil
    C.startRun(game,species,tonumber(msg.seed) or os.time(),depth)
  elseif msg.type=="dd_stair_ready" then
    S.advancePeer={depth=tonumber(msg.depth),relic=msg.relic and true or false}
    if S.role=="host" and S.advanceLocal and S.advancePeer.depth==S.advanceLocal.depth then
      local depth=S.advanceLocal.depth
      local sharedRelic=(S.advanceLocal.relic or S.advancePeer.relic) and true or false
      if C.setSharedRelic then C.setSharedRelic(game,sharedRelic) end
      send({type="dd_advance",depth=depth,relic=sharedRelic})
      S.advanceExec=S.advanceLocal.cb; S.advanceLocal=nil; S.advancePeer=nil
    end
  elseif msg.type=="dd_advance" then
    if S.advanceLocal and tonumber(msg.depth)==tonumber(S.advanceLocal.depth) then
      if C.setSharedRelic then C.setSharedRelic(game,msg.relic and true or false) end
      S.advanceExec=S.advanceLocal.cb; S.advanceLocal=nil; S.advancePeer=nil
    end
  elseif msg.type=="dd_run_ended" then
    if S.runActive then
      resetRunState()
      -- Keep the local save flagged as the shared expedition while the player
      -- is still standing on the same rest stop. This gives them a chance to
      -- use the Scientist too and create the matching checkpoint. The moment
      -- they descend without their partner, requestAdvance converts the run
      -- into a true solo branch so later boss floors do not spawn two guardians.
      S.orphanedRun=true
      S.notice="Your partner left the co-op delve. You can checkpoint too or continue solo."
    end
  elseif msg.type=="dd_floor_need" then
    if S.role=="host" and S.runActive and C.floorSnapshot then
      local ok,snap=pcall(C.floorSnapshot,game)
      if ok and type(snap)=="table" and tonumber(snap.floor)==tonumber(msg.floor) then
        snap.type="dd_floor_snapshot"; send(snap)
      end
    end
  elseif msg.type=="dd_floor_snapshot" then
    if S.role=="guest" and S.runActive and C.applyFloorSnapshot then
      local depth=tonumber(msg.floor) or 0
      local ok,applied=pcall(C.applyFloorSnapshot,game,msg)
      if not ok or not applied then S.pendingFloorSnapshots[tostring(depth)]=msg
      else S.pendingFloorSnapshots[tostring(depth)]=nil end
    end
  elseif msg.type=="dd_monsters" then
    if S.role=="guest" and S.runActive and C.applyMonsterSnapshot then
      pcall(C.applyMonsterSnapshot,game,msg)
    end
  elseif msg.type=="dd_monster_turn" then
    if S.role=="host" and S.runActive and C.runMonsterTurn
        and tonumber(msg.floor)==tonumber(C.pdSave(game).floor) then
      -- A guest turn must use the guest's position as the roaming-Pokemon
      -- target.  This also lets the host keep advancing the authoritative
      -- monster simulation while the host itself is inside a battle.
      pcall(C.runMonsterTurn,game,tonumber(msg.x),tonumber(msg.y),true)
      -- Do not rely on a later overworld update to replicate this turn.  The
      -- host may be inside a battle, where ordinary world presentation is
      -- paused; publish the authoritative roamer cells immediately.
      if C.monsterSnapshot then
        local ok,snap=pcall(C.monsterSnapshot,game)
        if ok and type(snap)=="table" then
          S.lastMonsterSig=snap.sig or S.lastMonsterSig
          snap.sig=nil; snap.type="dd_monsters"; send(snap)
        end
      end
    end
  elseif msg.type=="dd_entity_state" then
    if S.runActive and C.applyEntityState
        and tonumber(msg.floor)==tonumber(C.pdSave(game).floor) then
      S.suppressOutbound=true
      pcall(C.applyEntityState,game,tonumber(msg.index),msg.role,msg.used and true or false)
      S.suppressOutbound=false
    end
  elseif msg.type=="dd_entity_remove" then
    applyPeerEntityRemoval(game,msg)
  elseif msg.type=="dd_trap_state" then
    if S.runActive and C.applyTrapState and tonumber(msg.floor)==tonumber(C.pdSave(game).floor) then
      S.suppressOutbound=true
      pcall(C.applyTrapState,game,tonumber(msg.x),tonumber(msg.y),msg.hazard and true or false,msg.used and true or false,msg.revealed and true or false)
      S.suppressOutbound=false
    end
  elseif msg.type=="dd_traps_reveal_all" then
    if S.runActive and C.revealAllTraps and tonumber(msg.floor)==tonumber(C.pdSave(game).floor) then
      S.suppressOutbound=true; pcall(C.revealAllTraps,game); S.suppressOutbound=false
    end
  elseif msg.type=="dd_entity_engage" then
    if S.runActive and C.applyEntityEngage and tonumber(msg.floor)==tonumber(C.pdSave(game).floor) then
      pcall(C.applyEntityEngage,game,tonumber(msg.index),msg.role,msg.phase,msg.by,tonumber(msg.distance),msg.dir,tonumber(msg.x),tonumber(msg.y))
    end
  elseif msg.type=="dd_battle_state" then
    if msg.active and S.runActive and tonumber(msg.floor)==tonumber(C.pdSave(game).floor) then
      S.peerBattle={active=true,floor=tonumber(msg.floor),index=tonumber(msg.index),role=msg.role,
        species=msg.species,x=tonumber(msg.x),y=tonumber(msg.y),facing=msg.facing,by=msg.by}
      updateRemote(game)
    else
      S.peerBattle=nil
      if S.spectating then S.spectating.ended=true end
    end
  elseif msg.type=="dd_spectate_request" then
    if not (S.ready and S.runActive and tonumber(msg.floor)==tonumber(C.pdSave(game).floor)) then
      send({type="dd_spectate_refuse",watchId=msg.watchId,reason="The battle is no longer available."})
    else
      local api=Gen2BattleAPI and Gen2BattleAPI.new(game)
      local ok,snap=pcall(function() return api and api:snapshot() end)
      if not ok or not snap then
        send({type="dd_spectate_refuse",watchId=msg.watchId,reason="The battle has already ended."})
      else
        S.spectateServing={id=msg.watchId,api=api,lastRevision=nil,clock=0,animObj=nil,animSeq=0,
          hpAnimObj=nil,faintObj=nil,faintSeq=0,txSeq=0,
          lastShownPlayerHp=nil,lastShownEnemyHp=nil,
          lastShownPlayerStatus=nil,lastShownEnemyStatus=nil,
          lastPlayerHidden=nil,lastEnemyHidden=nil}
        sendSpectateState(game,true,0)
      end
    end
  elseif msg.type=="dd_spectate_state" then
    local watch=S.spectating
    if watch and watch.id==msg.watchId then
      watch.owner=msg.owner or watch.owner
      watch.snapshot={revision=tonumber(msg.revision) or 0,seq=tonumber(msg.seq) or tonumber(msg.revision) or 0,
        kind=msg.kind,prompt=msg.prompt,turn=tonumber(msg.turn) or 0,
        msg1=msg.msg1,msg2=msg.msg2,
        animSeq=tonumber(msg.animSeq) or 0,animActive=msg.animActive and true or false,
        animId=msg.animId,animTurn=tonumber(msg.animTurn) or 0,
        animParam=tonumber(msg.animParam) or 0,animFrame=tonumber(msg.animFrame) or 0,
        animIsMove=msg.animIsMove and true or false,
        hpAnimSide=msg.hpAnimSide,hpAnimTo=tonumber(msg.hpAnimTo),
        faintSeq=tonumber(msg.faintSeq) or 0,faintActive=msg.faintActive and true or false,
        faintSide=msg.faintSide,faintFrame=tonumber(msg.faintFrame) or 0,
        playerHidden=msg.p_hidden and true or false,enemyHidden=msg.e_hidden and true or false,
        player={species=msg.p_species,name=msg.p_name,level=tonumber(msg.p_level),hp=tonumber(msg.p_hp),
          maxHp=tonumber(msg.p_maxHp),status=msg.p_status},
        enemy={species=msg.e_species,name=msg.e_name,level=tonumber(msg.e_level),hp=tonumber(msg.e_hp),
          maxHp=tonumber(msg.e_maxHp),status=msg.e_status}}
    end
  elseif msg.type=="dd_spectate_end" then
    if S.spectating and S.spectating.id==msg.watchId then S.spectating.ended=true end
    if S.spectateServing and S.spectateServing.id==msg.watchId then S.spectateServing=nil end
  elseif msg.type=="dd_spectate_stop" then
    if S.spectateServing and S.spectateServing.id==msg.watchId then S.spectateServing=nil end
  elseif msg.type=="dd_spectate_refuse" then
    if S.spectating and S.spectating.id==msg.watchId then
      S.spectating.error=tostring(msg.reason or "That battle cannot be watched.")
      S.spectating.ended=true
    end
  elseif msg.type=="dd_force_monster_battle" then
    if S.role=="guest" and S.runActive and C.forceMonsterBattle
        and tonumber(msg.floor)==tonumber(C.pdSave(game).floor) then
      pcall(C.forceMonsterBattle,game,tonumber(msg.index))
    end
  elseif msg.type=="dd_trade_offer" then
    if not canTradeNow(game) then
      send({type="dd_trade_decline",tradeId=msg.tradeId,reason="Partner is not available to trade."})
    elseif S.incomingTrade or S.outgoingTrade then
      send({type="dd_trade_decline",tradeId=msg.tradeId,reason="Partner is already trading."})
    else
      S.incomingTrade={id=msg.tradeId,item=msg.item,qty=math.max(1,math.floor(tonumber(msg.qty) or 1)),from=msg.from}
      S.tradePromptPending=true
    end
  elseif msg.type=="dd_trade_accept" then
    local tr=S.outgoingTrade
    if tr and tr.id==msg.tradeId then
      local have=(C.tradeItemQty and C.tradeItemQty(game,tr.item)) or 0
      if have<tr.qty or not (C.removeTradeItem and C.removeTradeItem(game,tr.item,tr.qty)) then
        send({type="dd_trade_cancel",tradeId=tr.id,reason="The offered item is no longer available."})
        S.outgoingTrade=nil
        S.notice="Trade cancelled. The item is no longer in your PACK."
      else
        send({type="dd_trade_commit",tradeId=tr.id,item=tr.item,qty=tr.qty})
      end
    end
  elseif msg.type=="dd_trade_commit" then
    local tr=S.incomingTrade
    if tr and tr.id==msg.tradeId then
      local ok=C.addTradeItem and C.addTradeItem(game,msg.item,tonumber(msg.qty) or 1)
      if ok then
        send({type="dd_trade_done",tradeId=tr.id})
        S.notice="Received "..tradeLabel(game,msg.item,msg.qty).." from "..tostring(tr.from or "your partner").."."
      else
        send({type="dd_trade_failed",tradeId=tr.id,item=msg.item,qty=msg.qty,reason="PACK could not accept the item."})
        S.notice="Trade failed because your PACK could not accept the item."
      end
      S.incomingTrade=nil
    end
  elseif msg.type=="dd_trade_done" then
    local tr=S.outgoingTrade
    if tr and tr.id==msg.tradeId then
      S.notice="Trade complete. Sent "..tradeLabel(game,tr.item,tr.qty).."."
      S.outgoingTrade=nil
    end
  elseif msg.type=="dd_trade_failed" then
    local tr=S.outgoingTrade
    if tr and tr.id==msg.tradeId then
      if C.addTradeItem then C.addTradeItem(game,tr.item,tr.qty) end
      S.notice=tostring(msg.reason or "Trade failed.").." Your item was returned."
      S.outgoingTrade=nil
    end
  elseif msg.type=="dd_trade_decline" or msg.type=="dd_trade_cancel" then
    if S.outgoingTrade and S.outgoingTrade.id==msg.tradeId then S.outgoingTrade=nil end
    if S.incomingTrade and S.incomingTrade.id==msg.tradeId then S.incomingTrade=nil end
    S.notice=tostring(msg.reason or "Trade cancelled.")
  elseif msg.type=="dd_pkmn_offer" then
    if not canTradeNow(game) or S.incomingPokeSwap or S.outgoingPokeSwap then
      send({type="dd_pkmn_decline",swapId=msg.swapId,reason="Partner is not available to swap Pokemon."})
    else
      local mon,why=getPackedMon(game,msg,"a_")
      if not mon then send({type="dd_pkmn_decline",swapId=msg.swapId,reason=why or "Pokemon data did not match."})
      else
        S.incomingPokeSwap={id=msg.swapId,remoteSlot=tonumber(msg.slot),from=msg.from,mon=mon}
        S.pokeSwapPromptPending=true
      end
    end
  elseif msg.type=="dd_pkmn_counter" then
    local tr=S.outgoingPokeSwap
    if tr and tr.id==msg.swapId then
      local mon,why=getPackedMon(game,msg,"b_")
      if not mon then
        send({type="dd_pkmn_decline",swapId=tr.id,reason=why or "Pokemon data did not match."}); S.outgoingPokeSwap=nil
      else
        tr.remoteMon=mon; tr.remoteSlot=tonumber(msg.slot)
        local mine=game.save.party and game.save.party[tr.slot]
        if not mine or pokeFingerprint(mine)~=tr.fingerprint then
          send({type="dd_pkmn_decline",swapId=tr.id,reason="Offered Pokemon changed before the swap."}); S.outgoingPokeSwap=nil
        else
          C.showPages(game.world,{tostring((S.peerHello and S.peerHello.name) or "PARTNER").." offers "..pokeName(game,mon)..".",
            "Swap "..pokeName(game,mine).." for it?"},function()
            game.stack:push(C.Menu.new(game,{
              {label="YES",onSelect=function() send({type="dd_pkmn_commit",swapId=tr.id}) end},
              {label="NO",onSelect=function()
                send({type="dd_pkmn_decline",swapId=tr.id,reason="Pokemon swap cancelled."}); S.outgoingPokeSwap=nil
              end},
            },{tx=12,ty=8,tw=8,rowStep=2,cancelable=true}))
          end)
        end
      end
    end
  elseif msg.type=="dd_pkmn_commit" then
    local tr=S.incomingPokeSwap
    if tr and tr.id==msg.swapId and tr.localSlot and tr.localMon then
      local mine=game.save.party and game.save.party[tr.localSlot]
      if not mine or pokeFingerprint(mine)~=tr.localFingerprint then
        send({type="dd_pkmn_decline",swapId=tr.id,reason="Selected Pokemon changed before the swap."}); S.incomingPokeSwap=nil
      else
        game.save.party[tr.localSlot]=tr.mon
        send({type="dd_pkmn_committed",swapId=tr.id})
      end
    end
  elseif msg.type=="dd_pkmn_committed" then
    local tr=S.outgoingPokeSwap
    if tr and tr.id==msg.swapId and tr.remoteMon then
      local mine=game.save.party and game.save.party[tr.slot]
      if mine and pokeFingerprint(mine)==tr.fingerprint then
        game.save.party[tr.slot]=tr.remoteMon
        send({type="dd_pkmn_done",swapId=tr.id})
        S.notice="Pokemon swap complete. "..pokeName(game,tr.remoteMon).." joined your delve party."
        S.outgoingPokeSwap=nil
      end
    end
  elseif msg.type=="dd_pkmn_done" then
    local tr=S.incomingPokeSwap
    if tr and tr.id==msg.swapId then
      S.notice="Pokemon swap complete. "..pokeName(game,tr.mon).." joined your partner's party."
      S.incomingPokeSwap=nil
    end
  elseif msg.type=="dd_pkmn_decline" then
    if S.outgoingPokeSwap and S.outgoingPokeSwap.id==msg.swapId then S.outgoingPokeSwap=nil end
    if S.incomingPokeSwap and S.incomingPokeSwap.id==msg.swapId then S.incomingPokeSwap=nil end
    S.notice=tostring(msg.reason or "Pokemon swap cancelled.")
  elseif msg.type=="dd_party_request" then
    if S.ready and S.runActive then sendPartyState(game) end
  elseif msg.type=="dd_party_state" then
    if S.ready and S.runActive then openPeerPartyView(game,msg) end
  elseif msg.type=="dd_find" then
    applySharedFind(game,msg)
  elseif msg.type=="dd_mining_done" then
    local who=tostring(msg.from or (S.peerHello and S.peerHello.name) or "PARTNER"):upper():sub(1,16)
    S.noticePages={who.."\nfinished mining!","Shared finds are\nin your DELVE CASE."}
  end
end

function Coop.update(game,dt)
  if not S.net then return end
  S.net:update(dt)
  if S.net.error and not S.error then S.error=tostring(S.net.error) end
  if S.net.closed then
    if not S.error then S.error="Co-op connection closed." end
    removeRemote()
    S.ready=false
    return
  end
  if S.net.paired and S.net.wireOpen and not S.ready then
    S.helloClock=(S.helloClock or 0)+(tonumber(dt) or 0)
    if not S.helloSent or S.helloClock>=1 then
      S.helloSent=true
      S.helloClock=0
      send(localHello(game))
    end
  end
  for _,msg in ipairs(S.net:poll() or {}) do handle(game,msg) end
  if S.spectateServing then sendSpectateState(game,false,dt) end
  if S.ready then
    sendPosition(game)
    updateRemote(game)
  end
  if S.ready and S.runActive and S.role=="host" and C.monsterSnapshot then
    local ok,snap=pcall(C.monsterSnapshot,game)
    if ok and type(snap)=="table" and snap.sig and snap.sig~=S.lastMonsterSig then
      S.lastMonsterSig=snap.sig
      snap.sig=nil
      snap.type="dd_monsters"
      send(snap)
    end
  end
  if S.advanceExec and game.world and not game.world:busy() and not game.world.battleActive then
    local cb=S.advanceExec; S.advanceExec=nil
    cb()
  end
  if S.tradePromptPending and S.incomingTrade and game.world and not game.world:busy() and not game.world.battleActive then
    promptIncomingTrade(game)
  end
  if S.pokeSwapPromptPending and S.incomingPokeSwap and game.world and not game.world:busy() and not game.world.battleActive then
    promptIncomingPokeSwap(game)
  end
  if S.noticePages and game.world and not game.world:busy() and not game.world.battleActive then
    local pages=S.noticePages; S.noticePages=nil
    C.showPages(game.world,pages)
  elseif S.notice and game.world and not game.world:busy() and not game.world.battleActive then
    local n=S.notice; S.notice=nil
    C.showPages(game.world,{n})
  end
end

local function beginHost(game)
  closeNet()
  S.role="host"
  S.net=relayTransport(game,"host")
  if not S.net or S.net.closed then
    setError((S.net and S.net.error) or "Could not host co-op.")
    C.showPages(game.world,{S.error})
    return false
  end
  C.mod.ui.push(game,SCREEN,{mode="host"})
  return true
end

local function beginJoin(game,code)
  closeNet()
  S.role="guest"
  S.net=relayTransport(game,"guest",code)
  if not S.net or S.net.closed then
    setError((S.net and S.net.error) or "Could not join co-op.")
    C.showPages(game.world,{S.error})
    return false
  end
  C.mod.ui.push(game,SCREEN,{mode="joining"})
  return true
end

local function refreshUnlocks(game)
  if not S.ready then return end
  local u=C.unlocks and C.unlocks(game) or {}
  send({type="dd_unlocks",works=u.works and true or false,megalith=u.megalith and true or false})
end

local function requestCheckpointResume(game)
  if not (S.ready and S.role=="host" and not S.runActive) then return end
  local world=game.world
  if not (world and world.map and world.map.id==C.lobbyMap) or C.isActive(game) then
    return C.showPages(world,{"Return to the delve desk before resuming co-op."})
  end
  local localCp=checkpointMeta(game)
  if not checkpointMatches(localCp,S.peerCheckpoint) then
    return C.showPages(world,{"Your partner does not have the same co-op checkpoint."})
  end
  S.resumeLocal=localCp; S.resumePeer=nil
  send(addCheckpointFields({type="dd_checkpoint_prepare"},localCp))
  C.showPages(world,{"Shared B"..tostring(localCp.floor).." checkpoint found.","Waiting for your partner to confirm."})
end

local function startDepthMenu(game)
  refreshUnlocks(game)
  local localU=C.unlocks and C.unlocks(game) or {}
  local peer=S.peerHello or {}
  local items={{label="NATURAL CAVERNS",onSelect=function() Coop.requestStart(game,1) end}}
  if localU.works and peer.works then
    items[#items+1]={label="BURIED WORKS",onSelect=function() Coop.requestStart(game,21) end}
  end
  if localU.megalith and peer.megalith then
    items[#items+1]={label="BURIED SANCTUM",onSelect=function() Coop.requestStart(game,41) end}
  end
  items[#items+1]={label="BACK",onSelect=function() end}
  game.stack:push(C.Menu.new(game,items,{tx=3,ty=1,tw=15,rowStep=2,cancelable=true,maxVisible=7}))
end

function Coop.requestStart(game,depth)
  if not (S.ready and S.role=="host") then return end
  local world=game.world
  if not (world and world.map and world.map.id==C.lobbyMap) or C.isActive(game) then
    return C.showPages(world,{"Return to the delve desk before starting co-op."})
  end
  S.pendingDepth=depth; S.localReady=nil; S.peerReady=nil
  send({type="dd_prepare",depth=depth})
  openPartnerPicker(game,depth)
end

function Coop.openMenu(game)
  local items={}
  if not S.net or S.net.closed then
    items[#items+1]={label="HOST ONLINE",onSelect=function() beginHost(game) end}
    items[#items+1]={label="JOIN ONLINE",onSelect=function() C.mod.ui.push(game,SCREEN,{mode="code"}) end}
  elseif S.ready then
    if S.role=="host" then
      local localCp=checkpointMeta(game)
      if checkpointMatches(localCp,S.peerCheckpoint) then
        items[#items+1]={label="CONTINUE B"..tostring(localCp.floor),onSelect=function() requestCheckpointResume(game) end}
      end
      items[#items+1]={label="START CO-OP",onSelect=function() startDepthMenu(game) end}
    else
      items[#items+1]={label="WAIT FOR HOST",onSelect=function()
        C.showPages(game.world,{"Connected to "..tostring((S.peerHello and S.peerHello.name) or "HOST")..".","The host chooses the delve."})
      end}
    end
    items[#items+1]={label="PARTNER",onSelect=function()
      C.showPages(game.world,{"Connected: "..tostring((S.peerHello and S.peerHello.name) or "PARTNER")})
    end}
    items[#items+1]={label="DISCONNECT",onSelect=function() closeNet(); C.showPages(game.world,{"Co-op disconnected."}) end}
  else
    items[#items+1]={label="CONNECTION",onSelect=function() C.mod.ui.push(game,SCREEN,{mode=S.role=="host" and "host" or "joining"}) end}
    items[#items+1]={label="DISCONNECT",onSelect=function() closeNet() end}
  end
  items[#items+1]={label="BACK",onSelect=function() end}
  game.stack:push(C.Menu.new(game,items,{tx=5,ty=3,tw=14,rowStep=2,cancelable=true,maxVisible=6}))
end

function Coop.requestAdvance(game,depth,cb)
  if not (S.ready and S.runActive) then
    if S.orphanedRun then
      S.orphanedRun=false
      if C.continueSolo then pcall(C.continueSolo,game) end
    end
    cb(); return true
  end
  depth=tonumber(depth) or 1
  local relic=(C.hasRelic and C.hasRelic(game)) and true or false
  S.advanceLocal={depth=depth,cb=cb,relic=relic}
  send({type="dd_stair_ready",depth=depth,relic=relic})
  if S.role=="host" and S.advancePeer and S.advancePeer.depth==depth then
    local sharedRelic=(relic or S.advancePeer.relic) and true or false
    if C.setSharedRelic then C.setSharedRelic(game,sharedRelic) end
    send({type="dd_advance",depth=depth,relic=sharedRelic})
    S.advanceExec=cb; S.advanceLocal=nil; S.advancePeer=nil
  else
    C.showPages(game.world,{"Waiting for your partner at the stairs."})
  end
  return true
end

function Coop.entityRemoved(game,e)
  if S.suppressOutbound or not (S.ready and S.runActive and e and e.index) then return end
  send({type="dd_entity_remove",floor=tonumber(C.pdSave(game).floor) or 0,index=e.index,role=e.role})
end

function Coop.shareFind(game,find)
  if not (S.ready and S.runActive and type(find)=="table") then return end
  local msg={type="dd_find",kind=find.kind}
  for k,v in pairs(find) do if k~="type" then msg[k]=v end end
  send(msg)
end

function Coop.miningComplete(game,summary)
  if not (S.ready and S.runActive) then return end
  summary=type(summary)=="table" and summary or {}
  send({type="dd_mining_done",from=playerName(game),count=tonumber(summary.count) or 0,
    collapsed=summary.collapsed and true or false})
end

-- Called before Dungeon Delvers replaces PEWTER_DUNGEON_FLOOR's generated
-- object definition. Runtime ids are index-derived, so the partner must be
-- removed while its marked object row still exists. It will respawn from the
-- next position update after the new floor is live.
function Coop.beforeFloorRebuild(game)
  removeRemote()
end

function Coop.floorGenerated(game,fs)
  if not (S.ready and S.runActive and fs) then return end
  local depth=tonumber(fs.depth) or tonumber(C.pdSave(game).floor) or 0
  if S.role=="host" then
    if C.floorSnapshot then
      local ok,snap=pcall(C.floorSnapshot,game)
      if ok and type(snap)=="table" then snap.type="dd_floor_snapshot"; send(snap) end
    end
  else
    local pending=S.pendingFloorSnapshots[tostring(depth)]
    if pending and C.applyFloorSnapshot then
      local ok,applied=pcall(C.applyFloorSnapshot,game,pending)
      if ok and applied then S.pendingFloorSnapshots[tostring(depth)]=nil end
    end
    send({type="dd_floor_need",floor=depth})
  end
end

function Coop.entityState(game,e)
  if S.suppressOutbound or not (S.ready and S.runActive and e and e.index) then return end
  send({type="dd_entity_state",floor=tonumber(C.pdSave(game).floor) or 0,index=e.index,role=e.role,used=e.used and true or false})
end

function Coop.trapState(game,trap,hazard)
  if S.suppressOutbound or not (S.ready and S.runActive and trap) then return end
  send({type="dd_trap_state",floor=tonumber(C.pdSave(game).floor) or 0,x=trap.x,y=trap.y,
    hazard=hazard and true or false,used=trap.used and true or false,revealed=trap.revealed and true or false})
end

function Coop.revealAllTraps(game)
  if S.suppressOutbound or not (S.ready and S.runActive) then return end
  send({type="dd_traps_reveal_all",floor=tonumber(C.pdSave(game).floor) or 0})
end

function Coop.entityEngage(game,e,phase,distance,dir)
  if S.suppressOutbound or not (S.ready and S.runActive and e and e.index) then return end
  send({type="dd_entity_engage",floor=tonumber(C.pdSave(game).floor) or 0,index=e.index,role=e.role,
    phase=phase or "battle",by=playerName(game),distance=tonumber(distance) or 0,dir=dir or "",x=e.x,y=e.y})
end

function Coop.requestMonsterTurn(game)
  if S.ready and S.runActive and S.role=="guest" then
    local p=game and game.world and game.world.player
    send({type="dd_monster_turn",floor=tonumber(C.pdSave(game).floor) or 0,
      x=p and p.cellX or nil,y=p and p.cellY or nil})
  end
end

function Coop.battleState(game,e,active)
  if not (S.ready and S.runActive) then return end
  local p=game and game.world and game.world.player
  send({type="dd_battle_state",floor=tonumber(C.pdSave(game).floor) or 0,
    active=active and true or false,index=e and e.index or 0,role=e and e.role or "",species=e and e.species or nil,
    x=p and p.cellX or (e and e.x),y=p and p.cellY or (e and e.y),
    facing=p and p.facing or "down",by=playerName(game)})
  if not active and S.spectateServing then
    send({type="dd_spectate_end",watchId=S.spectateServing.id})
    S.spectateServing=nil
  end
end

function Coop.forcePeerMonsterBattle(game,e)
  if not (S.ready and S.runActive and S.role=="host" and e and e.index) then return end
  send({type="dd_force_monster_battle",floor=tonumber(C.pdSave(game).floor) or 0,index=e.index})
end

function Coop.offerSpectate(game,e,skipIntro)
  return promptSpectate(game,e,skipIntro and true or false)
end

function Coop.peerBattleInfo(game)
  if not (S.ready and S.runActive and S.peerBattle and S.peerBattle.active) then return nil end
  if not samePeerMap(game) then return nil end
  return S.peerBattle
end

function Coop.isGuest() return S.ready and S.role=="guest" end
function Coop.isHost() return S.ready and S.role=="host" end
function Coop.peerPosition(game)
  if not samePeerMap(game) then return nil end
  return S.peerPos
end

function Coop.onMapEntered(game,ev)
  S.lastPosKey=nil
  removeRemote()
  if S.ready then sendPosition(game); updateRemote(game) end
end

function Coop.checkpointChanged(game)
  if not S.ready then return end
  send(addCheckpointFields({type="dd_checkpoint_meta"},checkpointMeta(game)))
end

function Coop.runEnded()
  if S.ready and S.runActive then send({type="dd_run_ended"}) end
  resetRunState()
end

function Coop.isRunActive() return S.ready and S.runActive end
function Coop.isConnected() return S.ready end
function Coop.peerName()
  return (S.peerHello and S.peerHello.name) or (S.peerPos and S.peerPos.name)
end

-- DEV129: expose the live remote ghost using the exact world/camera/playfield
-- transform used by PokeSurvive resident chatter.  render.hud runs in final
-- window coordinates, so returning a 160x144 virtual position and then
-- rescaling through viewport (DEV126/127) double-transformed the tag.
function Coop.peerRenderAnchor(game)
  if not (S.ready and samePeerMap(game) and S.remoteId and S.remoteMap) then return nil end
  local ok,h=pcall(C.mod.world.npc,C.mod.world,S.remoteMap,S.remoteId)
  if not ok or not (h and h.npc and isPartnerDef(h.npc.def)) then return nil end
  local npc=h.npc
  local ow=C.mod.world and C.mod.world:overworld()
  if not (ow and ow.camera and love and love.graphics) then return nil end

  local okScale,worldScale=pcall(function() return ow:zoomScale() end)
  if not okScale or type(worldScale)~="number" or worldScale<=0 then worldScale=1 end

  local Playfield=require("src.render.Playfield")
  local ww,wh=love.graphics.getDimensions()
  local pfx,pfy=Playfield.rect(ww,wh)
  local px=tonumber(npc.px) or ((tonumber(npc.cellX) or 0)*16)
  local py=tonumber(npc.py) or ((tonumber(npc.cellY) or 0)*16)
  local cam=ow.camera
  local sx=(tonumber(pfx) or 0)+(px+8-(tonumber(cam.x) or 0))*worldScale
  local sy=(tonumber(pfy) or 0)+(py-1-(tonumber(cam.y) or 0))*worldScale
  return sx,sy,worldScale
end

function Coop.isSpectating() return S.spectating~=nil end

local function uiWrap(text,maxWidth,maxLines)
  local lines={}
  local current=""
  for word in tostring(text or ""):gmatch("%S+") do
    local candidate=(current=="") and word or (current.." "..word)
    if current~="" and C.Font.width(candidate)>maxWidth then
      lines[#lines+1]=current
      current=word
      if maxLines and #lines>=maxLines then break end
    else
      current=candidate
    end
  end
  if current~="" and (not maxLines or #lines<maxLines) then lines[#lines+1]=current end
  if #lines==0 then lines[1]="" end
  return lines
end

local function drawCentered(text,y)
  text=tostring(text or "")
  local x=math.max(7,math.floor((160-C.Font.width(text))/2))
  C.Font.draw(text,x,y)
end

local function registerScreen()
  C.mod.content.screens:register(SCREEN,{
    new=function(game,opts)
      opts=opts or {}
      local st={game=game,isOpaque=true,mode=opts.mode or "host",digits=codeDigits("000000"),digitPos=1}
      function st:update(dt)
        Coop.update(game,dt)
        local input=game.input
        if not input then return end
        if self.mode=="code" then
          if input:wasPressed("b") then game.stack:pop(); return end
          if input:wasPressed("left") then self.digitPos=math.max(1,self.digitPos-1)
          elseif input:wasPressed("right") then self.digitPos=math.min(CODE_LEN,self.digitPos+1)
          elseif input:wasPressed("up") then self.digits[self.digitPos]=((self.digits[self.digitPos] or 0)+1)%16
          elseif input:wasPressed("down") then self.digits[self.digitPos]=((self.digits[self.digitPos] or 0)+15)%16
          elseif input:wasPressed("a") then
            local code=digitsCode(self.digits)
            game.stack:pop()
            beginJoin(game,code)
          end
          return
        end
        if input:wasPressed("b") and not S.ready then closeNet(); game.stack:pop(); return end
        if input:wasPressed("a") and S.ready then game.stack:pop(); return end
      end
      function st:draw()
        C.Chrome.clear(); C.Chrome.box(0,0,20,18)
        love.graphics.setColor(0,0,0,1)
        if self.mode=="code" then
          drawCentered("JOIN ONLINE",14)
          drawCentered("ROOM CODE",38)
          local display=digitsCode(self.digits)
          drawCentered(display,62)
          local total=C.Font.width(display)
          local base=math.max(7,math.floor((160-total)/2))
          local prefix=C.Font.width(display:sub(1,self.digitPos-1))
          love.graphics.rectangle("fill",base+prefix,74,7,2)
          drawCentered("UP/DN CHANGE",91)
          drawCentered("A JOIN  B BACK",112)
          return
        end
        C.Font.draw("CO-OP DELVE",34,14)
        if S.error then
          drawCentered("CONNECTION ERROR",38)
          local lines=uiWrap(S.error,142,3)
          for i,line in ipairs(lines) do drawCentered(line,58+(i-1)*18) end
          drawCentered("B BACK",118)
        elseif S.ready then
          drawCentered("PARTNER CONNECTED",42)
          drawCentered(tostring((S.peerHello and S.peerHello.name) or "PARTNER"):sub(1,18),66)
          drawCentered("A CONTINUE",112)
        elseif S.role=="host" then
          drawCentered("HOST ONLINE",24)
          if S.net and S.net.address then
            drawCentered("ROOM CODE",46)
            drawCentered(tostring(S.net.address),66)
            if S.net.wireOpen then
              drawCentered("CO-OP LINK OPEN",90)
              drawCentered("HANDSHAKING...",106)
            elseif S.net.paired then
              drawCentered("PARTNER IN ROOM",90)
              drawCentered("OPENING LINK...",106)
            else
              drawCentered("WAITING FOR",90)
              drawCentered("PARTNER...",106)
            end
          elseif S.net and S.net.online then
            drawCentered("CREATING ROOM...",58)
            drawCentered("PLEASE WAIT",82)
          else
            drawCentered("CONNECTING...",58)
            drawCentered("PLEASE WAIT",82)
          end
          drawCentered("B CANCEL",126)
        else
          drawCentered("JOIN ONLINE",34)
          drawCentered(tostring((S.net and S.net.status) or "JOINING ROOM..."):sub(1,22),58)
          if S.net and S.net.wanted and S.net.wanted~="" then
            drawCentered("CODE "..tostring(S.net.wanted),82)
          end
          drawCentered("B CANCEL",116)
        end
      end
      return st
    end,
  })
end

function Coop.init(ctx)
  C=ctx
  Client=require("src.online.Client")
  Version=require("src.core.Version")
  Protocol=require("src.link.Protocol")
  Gen2BattleAPI=require("src.battle.gen2.BattleAPI")
  Spectator=assert(load(assert(C.mod:read("coop_spectator.lua")),"@pewter_dungeon/coop_spectator.lua"))()
  Spectator.init({mod=C.mod,Font=C.Font,Chrome=C.Chrome,
    session=function() return S.spectating end,
    stop=stopSpectating,finish=finishSpectating})
  registerScreen()
  C.mod.hooks:wrap("world.talk",function(next,ow,target)
    if target and target.def and target.def.coopPartner then
      S.partnerTalkGuard=true
      openPartnerMenu((ow and ow.game) or C.mod.game)
      return
    end
    return next(ow,target)
  end,170)
  -- world.talk is intentionally skipped by Crystal while an NPC is mid-step.
  -- world.interacted still fires for that A press, so use it as a fallback for
  -- the animated co-op ghost.  The guard avoids opening the menu twice when
  -- the ordinary non-moving world.talk path already handled the same press.
  C.mod.events:on("world.interacted",function(ev)
    local target=ev and ev.target
    local targetIsPartner=target and target.def and target.def.coopPartner
    local peerCell=ev and S.peerPos and samePeerMap(C.mod.game)
      and tonumber(ev.x)==tonumber(S.peerPos.x) and tonumber(ev.y)==tonumber(S.peerPos.y)
    if not (targetIsPartner or peerCell) then return end
    if S.partnerTalkGuard then S.partnerTalkGuard=false; return end
    openPartnerMenu(C.mod.game)
  end)
end

return Coop
