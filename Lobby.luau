local module = {}

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

local function TeleportToGame(Lobby)
	local TPOption = Instance.new("TeleportOptions")
	TPOption.ShouldReserveServer = true
	local TPData = {									-- Data that gonna be sent into game place
		Players 	= #Lobby.Players,					-- Amount of player that gonna be in the game
		Gamemode	= "Default",						-- The Gamemode
		Place		= "Default",						-- The Map
	}
	TPOption:SetTeleportData(TPData)
	local result = TeleportWithRetry(TARGET_PLACE_ID, Lobby.Players, TPOption)	-- Attempt At Teleport
	task.wait(1)
	for _,plr in pairs(Lobby.Players) do
		module.ExitLobby(plr)							-- Fail or not kicking out of the lobby
	end
	return result
end

-----------------------------------------------------------
-- Lobby State
-----------------------------------------------------------

local function LobbyState(Lobby,dt)
	if Lobby.Busy then return end					-- Its Teleporting
	local StateText = "Checking"
	if #Lobby.Players>=Lobby.MinPlayer then			-- More enough player required to initialize countdown
		if #Lobby.Players >= Lobby.MaxPlayer then
			Lobby.Time -= dt*4						-- Max Player reached speeding up
		else
			Lobby.Time -= dt						-- Count at normal rate
		end
		Lobby.State = "Counting Down"
	else
		Lobby.Time = Lobby.TimeLimit				-- Set the time back to max when there aren't enough players
		Lobby.State = "Waiting For Player"
	end
	if Lobby.Time < 0 then							-- When timer reach 0 its time to teleport
		Lobby.Busy = true
		Lobby.State = "Teleporting Player"
		if TeleportToGame(Lobby) then				-- Check if teleport successful
			Lobby.State = "Teleported"
		else
			Lobby.State = "Failed To Teleport"
		end
		Lobby.Busy = false
	elseif Lobby.Time < 3 then						-- its nearly time for departure
		Lobby.State = "Preparing To Teleport"
	end
end

local function UpdateLobby(Lobby)
	RS.Heartbeat:Connect(function(dt)
		-- UI Update
		Lobby.UI.Time.Text = math.max(0,math.floor(Lobby.Time))			-- Counting Down
		Lobby.UI.Player.Text = #Lobby.Players.."/"..Lobby.MaxPlayer		-- Update Player/MaxPlayer Text
		Lobby.UI.State.Text = Lobby.State								-- Show how's the lobby doing
		
		LobbyState(Lobby,dt)
	end)
end

-----------------------------------------------------------
-- Vector Utilities
-----------------------------------------------------------

local function Vector3ToTable(Vector)
	return {X=Vector.X,Y=Vector.Y,Z=Vector.Z}
end

local function Vector3SingleAxis(Vector,Axis,Number)
	local Siz = Vector3ToTable(Vector)
	Siz[Axis] = Number
	return Vector3.new(Siz.X,Siz.Y,Siz.Z)
end

local function Vector3Add(Vect1,Vect2)
	local Axis = {"X","Y","Z"}
	local Siz = Vector3ToTable(Vect1)
	local Siz2 = Vector3ToTable(Vect2)
	for i,v in pairs(Axis) do
		Siz[v] += Siz2[v]
	end
	return Vector3.new(Siz.X,Siz.Y,Siz.Z)
end

local function Vector3Change(Vect1,Vect2)
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
function module.EnterLobby(player:Player,Lobby)
	if Lobby.MaxPlayer <= #Lobby.Players then return end		-- Doesnt pass Limit
	if Lobby.Busy then return end								-- while it teleporting player to game
	if CheckInPlayerInLobby(player) then return end				-- player already in lobby
	table.insert(Lobby.Players,player)							-- add player in
	
	local UI = script.LobbyUI:Clone()
	UI.Parent = player.PlayerGui								-- Give player UI
		
	TPPlayer(player,Lobby.Hitbox.CFrame)						-- TP player into Box
	--print(("%s entered the zone!"):format(player.Name))
end

function module.ExitLobby(player:Players)
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
-- I dont think we need OOP for something like this
local function SetupLobby(Hitbox:BasePart,Num)
	
	CreateWall(Hitbox)								-- Setup invis wall

	local Zone = Util.Zone.new(Hitbox)				-- ZonePlus from utility tool I got
	
	-------------------------------------------
	local Lobby = {}
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
	UpdateLobby(Lobby)
	-------------------------------------------
	table.insert(LobbyList,Lobby)
	

	Zone.playerEntered:Connect(function(player)
		module.EnterLobby(player,Lobby)
	end)
end

--------------------------------------------------------
-- initialize the module
function module.Init()
	for i,v in pairs(CS:GetTagged(Tag)) do
		SetupLobby(v,i)
	end
end

--------------------------------------------------------
 -- character added from loader
function module.chradded(chr)
	local plr = game.Players:GetPlayerFromCharacter(chr)
	local hum = chr:WaitForChild("Humanoid")
	local con
	con = hum.Died:Connect(function() -- Make Player leave when reset
		con:Disconnect()
		module.ExitLobby(plr)
	end)
end
 -- player removed from loader
function module.PlayerRemoving(plr)
	module.ExitLobby(plr)  -- Make Player leave lobby when left the game
end

--------------------------------------------------------


return module
