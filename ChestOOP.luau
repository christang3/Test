-- ChestOOP Module
-- Handles chest interactions, inventory management, puzzles, and animations
-- Uses client-server communication through RemoteEvents and RemoteFunctions

local module = {}
module.__index = module

-- Services
local RS = game:GetService("RunService")

-- External Dependencies
local Util = _G["Utility"]
local GetRandom = Util.GetRandomFromTable

-- Folder References
local UIFolder = script.UI
local PuzzleFolder = script.Puzzle
local AnimFolder = script.Animation

-- Client Message Types - Maps string identifiers to function names
local ClientMessageCallTypes = {
	TakeItem = "TakeItem",
	Disconnect = "Disconnect",
}

--[[==========================================================
	Client Methods - Called from client via RemoteEvent/RemoteFunction
============================================================]]

-- Handles item taking from chest inventory
-- Called when player clicks an item in the chest UI
-- @param plr: The player taking the item
-- @param arg: Array containing [itemNumber, selectedKey]
function module:TakeItem(plr,arg)
	local num = arg[1]
	local selectedkey = arg[2]
	local Inv = self.Inventory
	local Item = Inv[num]
	-- _G["self"] -> The main game handler that contain most in-game codes
	if Item then
		_G["self"]:TakeItem(plr,Inv,num)
	elseif #Inv<self.ItemLimit then
		_G["self"]:TakeItem(Inv,plr,selectedkey)
	end
	self:UpdateClient()
end

--[[==========================================================
	Inventory Management Methods
============================================================]]

-- Shows the chest inventory to connected clients
-- Only shows if chest is not locked (no active puzzles/other type of locks)
function module:ShowInventory()
	if #self.Lock <= 0 then
		self.Client.Inventory = self.Inventory
		self:UpdateClient()
	end
end

-- Sets up the inventory UI with items
-- Uses the inventory module to display items in the UI
function module:SetInventory()
	if not self.InvMod then return end
	for i,v in pairs(self.Inventory) do
		self.InvMod:SetInventory(i,v)
	end
end

-- Progresses the chest state after puzzle completion
-- Shows inventory when all locks are removed
function module:Progress()
	if #self.Lock > 0 then return end
	-- Tween the Puzzle Out
	local PU = self.PuzzleUI

	self:ShowInventory()
end

--[[==========================================================
	Client Update Methods
============================================================]]

-- Updates all connected clients with current chest state
-- Creates a client-safe table and sends it via RemoteEvent
-- @return ClientTab: The table sent to clients
function module:UpdateClient()
	local OldTab = self.Client or self
	local ClientTab = {}
	for i,v in pairs(OldTab) do
		ClientTab[i] = self[i]
	end
	self.Client = ClientTab
	if self.Connected then
		for plr in pairs(self.Connected) do
			self.Event:FireClient(plr,"Update",ClientTab)
		end
	end
	return ClientTab
end

--[[==========================================================
	Connection Management Methods
============================================================]]

-- Main heartbeat loop that runs while players are connected
-- Handles distance checking and automatic disconnection
-- Plays open/close animations based on connection state
function module:run()
	if self.running then return end
	if self.OpenAnim then self.OpenAnim() end
	self.running = RS.Heartbeat:Connect(function(dt)
		--print(self.ConnectedCount,self.Connected)
		-- Close chest if no players are connected
		if self.ConnectedCount<=0 then
			if self.CloseAnim then self.CloseAnim() end
			self.running:Disconnect()
			self.running = nil
		end
		
		-- Check distance of all connected players
		local ChestPos = self.Model.PrimaryPart.Position
		local MaxRange = self.Prompt.MaxActivationDistance
		for plr in pairs(self.Connected) do
			local chr = plr.Character
			local root = chr and chr:FindFirstChild("HumanoidRootPart")
			local mag = root and (root.Position-ChestPos).Magnitude
			-- Disconnect player if they're too far away
			if (not mag) or (mag > MaxRange) then
				task.spawn(function()self:Disconnect(plr)end)
			end
		end
	end)
end

-- Connects a player to the chest
-- Sets player focus and starts the heartbeat loop
-- @param plr: The player to connect
function module:Connect(plr)
	if not self.Connected[plr] then
		_G["self"]:SetFocus(plr,self.Controller,self.Client)
		self.Connected[plr] = true
		self.ConnectedCount =  (self.ConnectedCount or 0)+1
		self:run()
	end
end

-- Disconnects a player from the chest
-- Removes player focus and decrements connection count
-- @param plr: The player to disconnect
function module:Disconnect(plr)
	if self.Connected[plr] then
		self.Connected[plr] = nil
		self.ConnectedCount = (self.ConnectedCount or 1)-1
		_G["self"]:SetFocus(plr)
	end
end

--[[==========================================================
	Module Loading Methods
============================================================]]

-- Loads the UI for the chest
-- Finds appropriate UI template based on prompt name or uses default
-- Creates and attaches UI module to the prompt
function module:LoadUI()
	--local ModelName = self.Model.Name
	local Prompt = self.Prompt
	
	local UI = UIFolder:FindFirstChild(Prompt.Name) or UIFolder:FindFirstChild("Chest")
	if UI then
		local Clon = UI:Clone()
		Clon.Name = "ChestUI"
		local UIMod = Clon:FindFirstChildOfClass("ModuleScript") or UIFolder.Default:Clone()
		UIMod.Name = "UIModule"
		UIMod.Parent = Clon


		Clon.Parent = Prompt

		self.UI = Clon
		self.UIMod = UIMod
		return self.UIMod
	end
end

-- Loads a random puzzle for the chest
-- Selects puzzle type from database and initializes it
-- Adds lock to chest that must be solved to access inventory
function module:LoadPuzzle()
	local Puzzle,PuzNam = GetRandom(_G["Database"].Puzzle)
	self.Puzzle = PuzNam
	self.PuzzleTab = GetRandom(Puzzle)
	local PuzzleUI = PuzzleFolder:FindFirstChild(PuzNam)
	if PuzzleUI then
		local Clon = PuzzleUI:Clone()
		Clon.Name = "Puzzle"
		Clon.Parent = self.UI.Frame
		local PuzzleModule = require(Clon:FindFirstChildOfClass("ModuleScript"))
		local Lock1 = PuzzleModule.Init(self.PuzzleTab)
		table.insert(self.Lock,Lock1)
		return PuzzleModule
	end
end

-- Loads animations for the chest
-- Finds animation module based on model name and initializes it
-- Sets up open and close animation functions
function module:LoadAnimation()
	local ModelName = self.Model.Name
	local Prompt = self.Prompt
	
	local AnimMod = AnimFolder:FindFirstChild(ModelName)
	if AnimMod then
		local Clon = AnimMod:Clone()
		Clon.Name = "PromptAnim"
		Clon.Parent = Prompt
		local AnimMod = require(Clon)
		AnimMod.Init(Prompt)

		self.AnimMod = AnimMod
		self.OpenAnim = AnimMod.Open
		self.CloseAnim = AnimMod.Close
		return AnimMod
	end
end

--[[==========================================================
	Inventory Setup Methods
============================================================]]

-- Creates a new inventory module for the chest
-- Sets up inventory UI and item selection callback
function module:NewInventory()
	local Inv = require(game.ReplicatedStorage.Shared.InventoryModule)
	local arg = {}
	arg.InvLimit = self.ItemLimit
	-- Find anything that remotely name inv and set up inventory there
	arg.Parent = self.UI and (self.UI:FindFirstChild("Inventory",true) or self.UI:FindFirstChild("Inv",true))
	arg.SelectFunction = nil
	self.InvMod = Inv.newInventory(arg)
end

-- Loads all chest modules and sets up lock completion handlers
-- Waits for database to be available before loading
-- Connects puzzle completion events to progress function
function module:LoadChestModule()
	
	repeat task.wait(.5) until _G["Database"]
	self.AllModules = {}
	local ModuleToLoad = {
		self.LoadUI,
		--self.LoadPuzzle, -- For next update
		self.LoadAnimation,
	}
	
	for i,v in pairs(ModuleToLoad) do
		table.insert(self.AllModules,v(self))
	end
	
	-- Connect lock completion events
	for i,v in pairs(self.Lock) do
		v.Event:Connect(function()
			self.Lock[i] = nil
			self:Progress()
		end)
	end
end

--[[==========================================================
	Remote Communication Methods
============================================================]]

-- Handles remote invocations from clients
-- Routes calls to appropriate methods based on message type
-- @param plr: The player making the request
-- @param Type: The type of message (from ClientMessageCallTypes)
-- @param arg: Arguments passed with the message
function module:RemoteInvoke(plr,Type,arg)
	if not self.Connected[plr] then return end
	local func = ClientMessageCallTypes[Type]
	if func then return self[func](self,plr,arg,arg) end
end

--[[==========================================================
	Chest Constructor
============================================================]]

-- Creates a new chest instance
-- @param Prompt: The ProximityPrompt that triggers chest interaction
-- @param Inv: Table of items to place in the chest
-- @return: New chest instance
function module.newChest(arg{Prompt:ProximityPrompt,Inv:{},ItemLimit:number})
	local Prompt = arg.Prompt
	-- Create chest instance with metatable
	local self = setmetatable({},module)
	self.Model = Prompt.Parent
	self.Prompt = Prompt
	
	-- Create remote communication objects
	self.Function = Instance.new("RemoteFunction")
	self.Event = Instance.new("RemoteEvent")
	self.Function.Parent = Prompt
	self.Event.Parent = Prompt
	
	-- Initialize chest state
	self.Lock = {}
	self.ItemLimit = arg.ItemLimit or 4
	
	-- Load modules and update client
	self:LoadChestModule()
	self:UpdateClient()
	-- All the variables passed this point are hidden from clients
	--self:NewInventory()
	
	-- Set up remote event handlers
	self.Function.OnServerInvoke = function(plr,Type,arg)
		return self:RemoteInvoke(plr,Type,arg)
	end
	self.Event.OnServerEvent:Connect(function(plr,Type,arg)
		self:RemoteInvoke(plr,Type,arg)
	end)
	
	-- Process inventory items - convert names to database items
	local Inv = {}
	for i,v in pairs(arg.Inv) do
		Inv[i] = _G["Database"].Item[v] or v
	end
	
	-- Set up inventory and connection tracking
	self.Inventory = Inv
	self.Controller = script.ChestController
	self.Connected = {}
	self.ConnectedCount = 0
	self:ShowInventory()
	
	return self
end

return module
