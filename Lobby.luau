local module = {}

local RS = game:GetService("RunService")
local CS = game:GetService("CollectionService")
local TeleportService = game:GetService("TeleportService")

local TARGET_PLACE_ID = 111473246436034 -- replace with your own place ID

local DebugMode = false
local UI = script.BillboardGui
local Tag = "TPZone"
local Util = _G["Utility"]
_G.SpawnPos = CFrame.new()

local Settings = {
	MinPlayer = 2,
	MaxPlayer = 8,
	TimeLimit = 30,
	FullPlayerTime = 10,
}

local LobbyList = {}
local PlayerInLobby = {}

local function TPPlayer(plr,CFram:CFrame)
	local chr = plr.Character or plr
	local Cast = Util.CastRay(CFram.Position,Vector3.new(0,-50,0))
	if Cast then
		chr.HumanoidRootPart.CFrame = CFrame.new(Cast.Position) * CFram.Rotation
	else
		chr.HumanoidRootPart.CFrame = CFram
	end
end

--------------------------------------------------------
local function CheckInPlayerInLobby(plr)
	for i,v in pairs(LobbyList) do
		local num = table.find(v.Players,plr)
		if num then
			return v,num
		end
	end
end
--------------------------------------------------------

function TeleportWithRetry(placeId,playersTable,teleportOptions:TeleportOptions)
	local ATTEMPT_LIMIT = 3
	local attemptIndex = 0
	local success, result

	repeat
		success, result = pcall(function()
			return TeleportService:TeleportAsync(placeId, playersTable, teleportOptions)
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
	local TPData = {
		Players 	= #Lobby.Players,
		Gamemode	= "Default",
		Place		= "Default",
	}
	TPOption:SetTeleportData(TPData)
	local result = TeleportWithRetry(TARGET_PLACE_ID, Lobby.Players, TPOption)
	task.wait(1)
	for _,plr in pairs(Lobby.Players) do
		module.ExitLobby(plr)
	end
	return result
end

local function LobbyState(Lobby,dt)
	if Lobby.Busy then return end
	local StateText = "Checking"
	if #Lobby.Players>=Lobby.MinPlayer then
		if #Lobby.Players >= Lobby.MaxPlayer then
			Lobby.Time -= dt*4
		else
			Lobby.Time -= dt
		end
		Lobby.State = "Counting Down"
	else
		Lobby.Time = Lobby.TimeLimit
		Lobby.State = "Waiting For Player"
	end
	if Lobby.Time < 0 then
		Lobby.Busy = true
		Lobby.State = "Teleporting Player"
		if TeleportToGame(Lobby) then
			Lobby.State = "Teleported"
		else
			Lobby.State = "Failed To Teleport"
		end
		Lobby.Busy = false
	elseif Lobby.Time < 3 then
		Lobby.State = "Preparing To Teleport"
	end
end

local function UpdateLobby(Lobby)
	RS.Heartbeat:Connect(function(dt)
		-- UI Update
		Lobby.UI.Time.Text = math.max(0,math.floor(Lobby.Time))
		Lobby.UI.Player.Text = #Lobby.Players.."/"..Lobby.MaxPlayer
		Lobby.UI.State.Text = Lobby.State
		
		LobbyState(Lobby,dt)
	end)
end

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

local function CreateWall(Hitbox:BasePart)
	local Part = Instance.new("Part")
	Part.Anchored = true
	Part.CanCollide = true
	Part.Transparency = DebugMode and .8 or 1
	local Pos = {"X","Y","Z"}
	local WallOffset = .5
	for i,v in pairs(Pos) do
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

function module.EnterLobby(player:Player,Lobby)
	if Lobby.MaxPlayer <= #Lobby.Players then return end
	if Lobby.Busy then return end
	if CheckInPlayerInLobby(player) then return end
	table.insert(Lobby.Players,player)
	
	local UI = script.LobbyUI:Clone()
	UI.Parent = player.PlayerGui
		
	TPPlayer(player,Lobby.Hitbox.CFrame)
	--print(("%s entered the zone!"):format(player.Name))
end

function module.ExitLobby(player:Players)
	local Lobby,num = CheckInPlayerInLobby(player)
	if Lobby then
		table.remove(Lobby.Players,num)
	end
	
	if player.Character then
		player:LoadCharacter()
		--TPPlayer(player,_G.SpawnPos)
	end
end

--------------------------------------------------------

local function SetupLobby(Hitbox:BasePart,Num)
	
	CreateWall(Hitbox)

	local Zone = Util.Zone.new(Hitbox)
	
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

function module.Init()
	for i,v in pairs(CS:GetTagged(Tag)) do
		SetupLobby(v,i)
	end
end

--------------------------------------------------------

function module.chradded(chr)
	local plr = game.Players:GetPlayerFromCharacter(chr)
	local hum = chr:WaitForChild("Humanoid")
	hum.Died:Connect(function()
		module.ExitLobby(plr)
	end)
end

function module.PlayerRemoving(plr)
	module.ExitLobby(plr)
end

--------------------------------------------------------


return module
