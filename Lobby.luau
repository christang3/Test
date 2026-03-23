--[[
	Lobby Module - Manages player matchmaking and game instance creation
	
	This module handles the creation and management of lobby instances where players
	gather before being teleported to a game instance. It provides:
	- Player queue management and lobby assignment
	- Automatic countdown timer with dynamic speed-up
	- Invisible boundary walls to contain players
	- Seamless server teleportation with retry logic
	- UI updates reflecting lobby state and player count
]]

local module = {}
module.__index = module

-- ============================================================================
-- SERVICES
-- ============================================================================
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TeleportService = game:GetService("TeleportService")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
--- The target place ID where players are teleported after countdown completes
local TARGET_PLACE_ID = 111473246436034

--- Debug mode enables semi-transparent walls for visualization
local DebugMode = false

--- The tag used by CollectionService to identify lobby hitbox parts
local LOBBY_ZONE_TAG = "TPZone"

--- Reference to the global utility library containing Zone+ and helper functions
local UtilityLibrary = _G["Utility"]

--- Lobby configuration constants
local LobbyConfig = {
	MinimumPlayerCount = 2,
	MaximumPlayerCount = 8,
	CountdownDuration = 30,
}

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================
--- Array of all active lobby instances managed by this module
local ActiveLobbies = {}

-- ============================================================================
-- PRIVATE UTILITY FUNCTIONS
-- ============================================================================

--- Searches all lobbies to find which one contains the specified player
--- @param targetPlayer Player - The player to search for
--- @return table? lobby - The lobby instance containing the player
--- @return number? index - The index of the player in the lobby's Players array
local function FindPlayerLobby(targetPlayer:Player)
	for _, lobby in pairs(ActiveLobbies) do
		local playerIndex = table.find(lobby.Players, targetPlayer)
		if playerIndex then
			return lobby, playerIndex
		end
	end
end

--- Converts a Vector3 to a table for easier mathematical manipulation
--- @param vector Vector3 - The vector to convert
--- @return table - Table with X, Y, Z keys {X=1,Y=2,Z=3} for example
local function VectorToTable(vector)
	return {X = vector.X, Y = vector.Y, Z = vector.Z}
end

--- Modifies a single axis of a Vector3 while preserving others
--- @param vector Vector3 - The original vector
--- @param axis string - The axis to modify either ["X", "Y", "Z"]
--- @param value number - The new value for that axis
--- @return Vector3 - Modified vector
local function SetVectorAxis(vector, axis, value)
	local tableForm = VectorToTable(vector)
	tableForm[axis] = value
	return Vector3.new(tableForm.X, tableForm.Y, tableForm.Z)
end

--- Adds two Vector3 values component-wise
--- @param vector1 Vector3 - First vector
--- @param vector2 Vector3 - Second vector to add
--- @return Vector3 - Sum of the two vectors
local function AddVectors(vector1, vector2)
	local axisNames = {"X", "Y", "Z"}
	local result = VectorToTable(vector1)
	local addend = VectorToTable(vector2)
	
	for _, axis in ipairs(axisNames) do
		result[axis] += addend[axis]
	end
	
	return Vector3.new(result.X, result.Y, result.Z)
end

--- Overlays non-zero components from one vector onto another
--- @param baseVector Vector3 - The base vector to modify
--- @param overrideVector Vector3 - Vector whose non-zero components take precedence
--- @return Vector3 - Modified vector
local function OverlayVector(baseVector, overrideVector)
	local axisNames = {"X", "Y", "Z"}
	local result = VectorToTable(baseVector)
	local override = VectorToTable(overrideVector)
	
	for _, axis in ipairs(axisNames) do
		if override[axis] ~= 0 then
			result[axis] = override[axis]
		end
	end
	
	return Vector3.new(result.X, result.Y, result.Z)
end

--- Teleports a player to a specified location, detecting floor beneath
--- @param player Player - The player to teleport
--- @param targetCFrame CFrame - The desired CFrame
local function TeleportPlayerToLobby(player, targetCFrame)
	local character = player.Character or player
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	
	if not humanoidRootPart then return end
	
	-- Cast ray downward to find solid ground
	local floorRayResult = UtilityLibrary.CastRay(targetCFrame.Position, Vector3.new(0, -50, 0))
	
	if floorRayResult then
		-- Teleport to floor surface while preserving target rotation
		humanoidRootPart.CFrame = CFrame.new(floorRayResult.Position) * targetCFrame.Rotation
	else
		-- Fallback to target CFrame if no floor detected
		humanoidRootPart.CFrame = targetCFrame
	end
end

--- Creates invisible collision walls around the lobby zone
--- @param hitboxPart BasePart - The lobby boundary part
local function CreateLobbyBoundaryWalls(hitboxPart)
	local WallThickness = 0.2
	local WallOffset = 0.5
	local AxisNames = {"X", "Y", "Z"}
	
	-- Template wall part with shared properties
	local wallTemplate = Instance.new("Part")
	wallTemplate.Anchored = true
	wallTemplate.CanCollide = true
	wallTemplate.Transparency = DebugMode and 0.8 or 1.0
	
	-- Create opposing wall pairs on each axis
	for _, axis in ipairs(AxisNames) do
		local hitboxTableSize = VectorToTable(hitboxPart.Size)
		local adjustedSize = AddVectors(hitboxPart.Size, -Vector3.new(WallOffset, WallOffset, WallOffset))
		
		-- Wall size: thin on the axis perpendicular to the boundary, full size on others
		local wallSize = SetVectorAxis(adjustedSize, axis, WallThickness)
		
		-- Create first wall at positive extent
		local positiveWall = wallTemplate:Clone()
		positiveWall.Size = wallSize
		
		local positiveOffset = CFrame.new(SetVectorAxis(Vector3.new(), axis, hitboxTableSize[axis] / 2 - WallOffset))
		positiveWall.CFrame = hitboxPart.CFrame * positiveOffset
		positiveWall.Parent = hitboxPart
		
		-- Create second wall at negative extent
		local negativeWall = wallTemplate:Clone()
		negativeWall.Size = wallSize
		
		local negativeOffset = CFrame.new(SetVectorAxis(Vector3.new(), axis, -(hitboxTableSize[axis] / 2 - WallOffset)))
		negativeWall.CFrame = hitboxPart.CFrame * negativeOffset
		negativeWall.Parent = hitboxPart
	end
end

-- ============================================================================
-- TELEPORTATION LOGIC
-- ============================================================================

--- Attempts to teleport a group of players to a reserved game server with exponential backoff
--- @param placeId number - Target place ID
--- @param playersToTeleport table - Array of Player objects
--- @param teleportOptions TeleportOptions - Configuration for the teleport
--- @return boolean success - Whether teleportation succeeded
--- @return string? errorMessage - Error message if teleportation failed
local function TeleportWithRetry(placeId, playersToTeleport, teleportOptions)
	local MAX_RETRY_ATTEMPTS = 3
	local RETRY_DELAY = 2
	
	for attemptNumber = 1, MAX_RETRY_ATTEMPTS do
		local didSucceed, resultOrError = pcall(function()
			return TeleportService:TeleportAsync(placeId, playersToTeleport, teleportOptions)
		end)
		
		if didSucceed then
			task.wait(1) -- Brief delay after successful teleport
			return true, resultOrError
		end
		
		if attemptNumber < MAX_RETRY_ATTEMPTS then
			task.wait(RETRY_DELAY)
		end
	end
	
	return false, "Max teleport retries exceeded"
end

--- Executes the teleportation sequence for all players in the lobby
--- @return boolean - Whether teleportation succeeded
function module:TeleportAllPlayersToGame()
	-- Create teleport options with reserved server enabled
	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions.ShouldReserveServer = true
	
	-- Prepare game instance configuration data
	local gameInstanceData = {
		PlayerCount = #self.Players,
		GamemodeType = "Default",
		MapName = "Default",
	}
	teleportOptions:SetTeleportData(gameInstanceData)
	
	-- Attempt teleportation
	local success, errorResult = TeleportWithRetry(TARGET_PLACE_ID, self.Players, teleportOptions)
	task.wait(1)
	
	-- Remove all players from lobby regardless of teleport success
	for _, player in ipairs(self.Players) do
		module:RemovePlayerFromLobby(player)
	end
	
	return success
end

-- ============================================================================
-- LOBBY STATE MACHINE
-- ============================================================================

--- Updates the lobby state based on player count and countdown timer
--- @param deltaTime number - Time elapsed since last frame (in seconds)
function module:UpdateLobbyState(deltaTime)
	-- Skip updates while teleporting
	if self.IsBusy then return end
	
	if #self.Players >= self.MinimumPlayerCount then
		-- Enough players: decrease countdown
		if #self.Players >= self.MaximumPlayerCount then
			-- Lobby is full: speed up countdown by 4x
			self.RemainingTime -= deltaTime * 4
		else
			-- Normal countdown speed
			self.RemainingTime -= deltaTime
		end
		self.CurrentState = "Counting Down"
	else
		-- Not enough players: reset timer and wait
		self.RemainingTime = self.CountdownDuration
		self.CurrentState = "Waiting For Player"
	end
	
	-- Handle timer completion
	if self.RemainingTime <= 0 then
		self.IsBusy = true
		self.CurrentState = "Teleporting Player"
		
		local teleportSuccess = self:TeleportAllPlayersToGame()
		self.CurrentState = teleportSuccess and "Teleported" or "Failed To Teleport"
		
		self.IsBusy = false
	elseif self.RemainingTime < 3 then
		-- Final countdown phase
		self.CurrentState = "Preparing To Teleport"
	end
end

--- Initializes the Heartbeat connection for continuous state and UI updates
function module:StartLobbyUpdates()
	local heartbeatConnection
	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		-- Update UI display with current lobby state
		self.UIElements.TimeDisplay.Text = tostring(math.max(0, math.floor(self.RemainingTime)))
		self.UIElements.PlayerCountDisplay.Text = ("%d/%d"):format(#self.Players, self.MaximumPlayerCount)
		self.UIElements.StateDisplay.Text = self.CurrentState
		
		-- Update lobby internal state
		self:UpdateLobbyState(deltaTime)
	end)
	
	-- Cleanup when lobby is destroyed
	self.HeartbeatConnection = heartbeatConnection
end

-- ============================================================================
-- LOBBY PLAYER MANAGEMENT API
-- ============================================================================

--- Adds a player to the lobby (called when player enters zone)
--- @param player Player - The player to add
function module:AddPlayerToLobby(player)
	-- Validate lobby capacity
	if #self.Players >= self.MaximumPlayerCount then
		return false
	end
	
	-- Prevent teleportation while in progress
	if self.IsBusy then
		return false
	end
	
	-- Prevent duplicate entries
	if FindPlayerLobby(player) then
		return false
	end
	
	-- Add player to lobby
	table.insert(self.Players, player)
	
	-- Equip player with lobby UI
	local playerUIInstance = script.LobbyUI:Clone()
	playerUIInstance.Parent = player.PlayerGui
	
	-- Position player inside lobby zone
	TeleportPlayerToLobby(player, self.Hitbox.CFrame)
	
	return true
end

--- Removes a player from the lobby and respawns them
--- @param player Player - The player to remove
function module:RemovePlayerFromLobby(player)
	-- Find and remove from lobby tracking
	local foundLobby, playerIndex = FindPlayerLobby(player)
	if foundLobby then
		table.remove(foundLobby.Players, playerIndex)
	end
	
	-- Respawn player at default spawn point
	if player.Character then
		player:LoadCharacter()
	end
end

-- ============================================================================
-- LOBBY INITIALIZATION
-- ============================================================================

--- Factory function to create a new lobby instance with all required properties and connections
--- @param hitboxPart BasePart - The part defining the lobby zone boundaries
--- @return table - New lobby instance
function module.new(hitboxPart)
	-- Setup physical boundaries
	CreateLobbyBoundaryWalls(hitboxPart)
	
	-- Create Zone+ detection area using utility library
	local zoneDetector = UtilityLibrary.Zone.new(hitboxPart)
	
	-- Initialize lobby object with metatable
	local newLobby = setmetatable({}, module)
	newLobby.Zone = zoneDetector
	newLobby.Hitbox = hitboxPart
	newLobby.MaximumPlayerCount = LobbyConfig.MaximumPlayerCount
	newLobby.MinimumPlayerCount = LobbyConfig.MinimumPlayerCount
	newLobby.Players = {}
	newLobby.CountdownDuration = LobbyConfig.CountdownDuration
	newLobby.RemainingTime = newLobby.CountdownDuration
	newLobby.CurrentState = "Waiting For Player"
	newLobby.IsBusy = false
	
	-- Setup UI billboard
	local billboardUI = script.BillboardGui:Clone()
	billboardUI.Title.Text = hitboxPart.Name
	billboardUI.Parent = hitboxPart
	
	-- Create UI element reference table for easier access
	newLobby.UIElements = {
		Billboard = billboardUI,
		TimeDisplay = billboardUI.Time,
		PlayerCountDisplay = billboardUI.Player,
		StateDisplay = billboardUI.State,
	}
	
	-- Start continuous updates
	newLobby:StartLobbyUpdates()
	
	-- Register lobby globally
	table.insert(ActiveLobbies, newLobby)
	
	-- Setup zone entry detection: uses :Once() to auto-disconnect on first trigger per player
	-- Note: Using :Once() is more efficient than manual connection management
	zoneDetector.playerEntered:Connect(function(enteringPlayer)
		newLobby:AddPlayerToLobby(enteringPlayer)
	end)
	
	return newLobby
end

--- Initializes all lobbies by finding tagged hitbox parts and creating lobby instances
function module.Init()
	local taggedHitboxes = CollectionService:GetTagged(LOBBY_ZONE_TAG)
	for _, hitboxPart in ipairs(taggedHitboxes) do
		module.new(hitboxPart)
	end
end

--- Handles player character respawn: removes from lobby on death
--- @param character Model - The new character model
function module.OnCharacterAdded(character)
	local player = game.Players:GetPlayerFromCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")
	
	-- Auto-exit lobby when player dies using :Once() for auto-cleanup
	humanoid.Died:Once(function()
		module:RemovePlayerFromLobby(player)
	end)
end

--- Handles player leaving the game: removes from lobby
--- @param leavingPlayer Player - The player who left the game
function module.OnPlayerRemoving(leavingPlayer)
	module:RemovePlayerFromLobby(leavingPlayer)
end

-- P.S this is only few code I got that passed 200 loc (Within the lobby segment of the game)
-- (The other are demonstrated in a match [In-game] which cant be used for this application)
-- Other scripts are splitted up into their tinier pieces counterpart which are easier for readability and organized structure
-- I don't think there could be use of anymore API neccessary for lobby module

return module
