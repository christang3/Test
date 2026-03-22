local module = {}
module.__index = module

local RS = game:GetService("RunService")					-- better than while true do
local CS = game:GetService("CollectionService")				-- for all thing with tag
local TeleportService = game:GetService("TeleportService")	-- for teleport

local TARGET_PLACE_ID = 111473246436034 -- replace with your own place ID

local DebugMode = false
local UI = script.BillboardGui								-- the ui of lobby
local Tag = "TPZone"										-- Find all box with this tag
local Util = _G["Utility"]									-- all the other utility/libs I have
_G.SpawnPos = CFrame.new()									-- this one wasn't used

local Settings = {
	MinPlayer = 2,
	MaxPlayer = 8,
	TimeLimit = 30,
}

local LobbyList = {}

--------------------------------------------------------
local function CheckInPlayerInLobby(plr) -- Check each Lobby For The Player
	for i,v in pairs(LobbyList) do
		local num = table.find(v.Players,plr)
		if num then
			return v,num
		end
	end
end
-----------------------------------------------------------
-- Teleport
-----------------------------------------------------------

function TeleportWithRetry(placeId,playersTable,teleportOptions:TeleportOptions)
	local ATTEMPT_LIMIT = 3
	local attemptIndex = 0
	local success, result

	repeat
		success, result = pcall(function()
			return TeleportService:TeleportAsync(placeId, playersTable, teleportOptions)	-- Attemp at teleport (Limit 3 try every 2 sec)
		end)

		attemptIndex += 1
		if not success then
			task.wait(2)
		end

		--print(attemptIndex,ATTEMPT_LIMIT)
	until success or attemptIndex == ATTEMPT_LIMIT

	if not success then
		warn("Teleport Failure:",result)
	else
		task.wait(1)
	end

	return success, result
end

function module:TeleportToGame()
	local TPOption = Instance.new("TeleportOptions")
	TPOption.ShouldReserveServer = true
	local TPData = {									-- Data that gonna be sent into game place
		Players 	= #self.Players,					-- Amount of player that gonna be in the game
		Gamemode	= "Default",						-- The Gamemode
		Place		= "Default",						-- The Map
	}
	TPOption:SetTeleportData(TPData)
	local result = TeleportWithRetry(TARGET_PLACE_ID, self.Players, TPOption)	-- Attempt At Teleport
	task.wait(1)
	for _,plr in pairs(self.Players) do
		module:ExitLobby(plr)							-- Fail or not kicking out of the lobby
	end
	return result
end

-----------------------------------------------------------
-- Lobby State
-----------------------------------------------------------

function module:State(dt)
	if self.Busy then return end					-- Its Teleporting rn so wait till it done
	local StateText = "Checking"
	if #self.Players>=self.MinPlayer then			-- More enough player required to initialize countdown
		if #self.Players >= self.MaxPlayer then
			self.Time -= dt*4						-- Max Player reached speeding up
		else
			self.Time -= dt						-- Count at normal rate
		end
		self.State = "Counting Down"
	else
		self.Time = self.TimeLimit				-- Set the time back to max when there aren't enough players
		self.State = "Waiting For Player"
	end
	if self.Time < 0 then							-- When timer reach 0 its time to teleport
		self.Busy = true
		self.State = "Teleporting Player"
		if self:TeleportToGame() then				-- Check if teleport successful
			self.State = "Teleported"
		else
			self.State = "Failed To Teleport"
		end
		self.Busy = false
	elseif self.Time < 3 then						-- its nearly time for departure
		self.State = "Preparing To Teleport"
	end
end

function module:run()
	RS.Heartbeat:Connect(function(dt)
		-- UI Update
		self.UI.Time.Text = math.max(0,math.floor(self.Time))			-- Counting Down
		self.UI.Player.Text = #self.Players.."/"..self.MaxPlayer		-- Update Player/MaxPlayer Text
		self.UI.State.Text = self.State									-- Show how's the lobby doing
		
		self:State(dt)
	end)
end

-----------------------------------------------------------
-- Vector Utilities
-----------------------------------------------------------
-- convert Vector3 to table value easier to handle on math
local function Vector3ToTable(Vector:Vector3): Table
	return {X=Vector.X,Y=Vector.Y,Z=Vector.Z}		-- from Vector3.new(1,1,1) -> {X=1,Y=1,Z=1}
end

-- change only 1 axis
local function Vector3SingleAxis(Vector:Vector3,Axis:string,Number:number): Vector3
	local Siz = Vector3ToTable(Vector)
	Siz[Axis] = Number
	return Vector3.new(Siz.X,Siz.Y,Siz.Z)
end

-- add up 2 vector
local function Vector3Add(Vect1:Vector3,Vect2:Vector3): Vector3
	local Axis = {"X","Y","Z"}
	local Siz = Vector3ToTable(Vect1)
	local Siz2 = Vector3ToTable(Vect2)
	for i,v in pairs(Axis) do
		Siz[v] += Siz2[v]
	end
	return Vector3.new(Siz.X,Siz.Y,Siz.Z)
end

-- change into 2nd vector part that arent 0
local function Vector3Change(Vect1:Vector3,Vect2:Vector3):Vector3
	local Axis = {"X","Y","Z"}
	local Siz = Vector3ToTable(Vect1)
	local Siz2 = Vector3ToTable(Vect2)
	for i,v in pairs(Axis) do
		if Siz2 == 0 then continue end
		Siz[v] = Siz2[v]
	end
	return Vector3.new(Siz.X,Siz.Y,Siz.Z)
end

-----------------------------------------------------------
-- Other Utilities
-----------------------------------------------------------
-- Teleport The Player Inside the box
local function TPPlayer(plr,CFram:CFrame)
	local chr = plr.Character or plr
	local Cast = Util.CastRay(CFram.Position,Vector3.new(0,-50,0))
	if Cast then	-- If The Ray Hit the floor there's something solid player can stand on
		chr.HumanoidRootPart.CFrame = CFrame.new(Cast.Position) * CFram.Rotation
	else
		chr.HumanoidRootPart.CFrame = CFram
	end
end

-- Create Invisble Wall Around Lobby Room
local function CreateWall(Hitbox:BasePart)
	local Part = Instance.new("Part")
	Part.Anchored = true
	Part.CanCollide = true
	Part.Transparency = DebugMode and .8 or 1
	local Pos = {"X","Y","Z"}
	local WallOffset = .5
	for i,v in pairs(Pos) do						-- Creating Both side of the wall on one axis
		local Clon = Part:Clone()
		local HitboxSize = Vector3Add(Hitbox.Size,-Vector3.new(WallOffset,WallOffset,WallOffset))
		local Size = Vector3SingleAxis(HitboxSize,v,.2)
		Clon.Size = Size
		-----------
		local Offset = CFrame.new(Vector3SingleAxis(Vector3.new(),v,Hitbox.Size[v]/2-WallOffset))
		Clon.CFrame = Hitbox.CFrame * Offset
		Clon.Parent = Hitbox
		-----------
		local Clon2 = Clon:Clone()
		local Offset = CFrame.new(Vector3SingleAxis(Vector3.new(),v,-(Hitbox.Size[v]/2-WallOffset)))
		Clon2.CFrame = Hitbox.CFrame * Offset
		Clon2.Parent = Hitbox
	end
end

-----------------------------------------------------------
-- API Part
-----------------------------------------------------------
-- pretty self explanatory
function module:EnterLobby(player:Player,Lobby)
	if Lobby.MaxPlayer <= #Lobby.Players then return end		-- Doesnt pass Limit
	if Lobby.Busy then return end								-- while it teleporting player to game
	if CheckInPlayerInLobby(player) then return end				-- player already in lobby
	table.insert(Lobby.Players,player)							-- add player in
	
	local UI = script.LobbyUI:Clone()
	UI.Parent = player.PlayerGui								-- Give player UI
		
	TPPlayer(player,Lobby.Hitbox.CFrame)						-- TP player into Box
	--print(("%s entered the zone!"):format(player.Name))
end

function module:ExitLobby(player:Players)
	local Lobby,num = CheckInPlayerInLobby(player)				-- Check If player actually in lobby
	if Lobby then
		table.remove(Lobby.Players,num)							-- Remove Player
	end
	
	if player.Character then
		player:LoadCharacter()									-- Respawn Player
		--TPPlayer(player,_G.SpawnPos)
	end
end

--------------------------------------------------------
--
--------------------------------------------------------
-- set up OOP like y'kno usual
function module.new(Hitbox:BasePart)
	
	CreateWall(Hitbox)								-- Setup invis wall

	local Zone = Util.Zone.new(Hitbox)				-- ZonePlus from utility tool I got
	
	-------------------------------------------
	local Lobby = setmetatable({},module)
	Lobby.Zone = Zone
	Lobby.Hitbox = Hitbox
	Lobby.MaxPlayer = Settings.MaxPlayer
	Lobby.MinPlayer = Settings.MinPlayer
	Lobby.Players = {}
	--Lobby.Host = nil
	Lobby.TimeLimit = Settings.TimeLimit
	Lobby.Time = Lobby.TimeLimit
	Lobby.State = "Waiting For Player"
	local UI = script.BillboardGui:Clone()
	--UI.Title.Text = "Lobby "..Num
	UI.Title.Text = Hitbox.Name
	UI.Parent = Hitbox	
	Lobby.UI = UI
	Lobby:run()
	-------------------------------------------
	table.insert(LobbyList,Lobby)
	

	Zone.playerEntered:Connect(function(player)			-- Player Enter Lobby by just touching the thing
		Lobby:EnterLobby(player)
	end)
end

--------------------------------------------------------
-- initialize the module
function module.Init()
	for i,v in pairs(CS:GetTagged(Tag)) do
		module.new(v)
	end
end

--------------------------------------------------------
 -- character added from loader
function module.chradded(chr)
	local plr = game.Players:GetPlayerFromCharacter(chr)
	local hum = chr:WaitForChild("Humanoid")
	local con
	con = hum.Died:Once(function() -- Make Player leave when reset
		module:ExitLobby(plr)
	end)
end
 -- player removed from loader
function module.PlayerRemoving(plr)
	module:ExitLobby(plr)  -- Make Player leave lobby when left the game
end

--------------------------------------------------------


return module
