local module = {}

--// Services
local ContentProvider = game:GetService("ContentProvider")

--// Types
type Item = {
	Name: string,
	ID: number?,
	ImageID: string | number?,
	Rarity: number?,
	Tier: string?,
	Category: {string}?,
	[string]: any
}

type Category = {
	[string]: Item | Category | number
}

--// Internal index
local IDIndex: {[number]: Item} = {}

--// State
local Database: {[string]: Category} = {}
local Loaded = false

--// Constants
local TierToRarity: {[string]: number} = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Secret = 7,
	Exclusive = 8,
}

local CategoryID: {[string]: number}} = {}

--// Validator
local REQUIRED_FIELDS = {
	"Name",
	"ID"
}
--// Internal Cache
local ImageCache: {[number]: string} = {}

--// Utility: Reverse lookup
local function RarityToTier(rarity: number): string?
	for tier, value in pairs(TierToRarity) do
		if value == rarity then
			return tier
		end
	end
	return nil
end


--// Utility: Deep copy
local function DeepCopy<T>(original: T): T
	local copy = {} :: any

	for k, v in pairs(original :: any) do
		copy[k] = (type(v) == "table") and DeepCopy(v) or v
	end

	return copy
end

--// Utility: Validate Item
local function ValidateItem(item: Item): boolean
	for _, field in ipairs(REQUIRED_FIELDS) do
		if item[field] == nil then
			warn(`Item missing field: {field}`)
			return false
		end
	end
	return true
end


--// Utility: Normalize image asset
local function NormalizeImage(assetId: number?): string
	if not assetId then
		return ""
	end

	if ImageCache[assetId] then
		return ImageCache[assetId]
	end

	local content = "rbxassetid://" .. assetId

	-- Preload for reliability (non-blocking)
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({content})
		end)
	end)

	ImageCache[assetId] = content
	return content
end

--// Processor: Normalize single item
local function ProcessItem(item: Item, path: {string}): Item
	-- Copy to avoid mutating source
	local newItem = DeepCopy(item)

	if newItem.Rarity then
		newItem.Tier = RarityToTier(newItem.Rarity)
	end

	if typeof(newItem.ImageID) == "number" then
		newItem.ImageID = NormalizeImage(newItem.ImageID)
	end

	newItem.Category = path

	return newItem
end

--// Processor: Recursive category processing
local function ProcessCategory(category: Category, path: {string}): Category
	local result: Category = {}

	for key, value in pairs(category) do
		
		-- Skip unsupported types
		local valueType = typeof(value)
		if valueType ~= "table" and valueType ~= "number" then
			continue
		end

		-- Handle raw image IDs
		if valueType == "number" then
			result[key] = NormalizeImage(value)
			continue
		end

		local item = value :: any

		-- Leaf item
		if item.Name then
			if not ValidateItem(item) then
				continue
			end
			local processed = ProcessItem(item, path)
			result[item.Name] = processed
			continue
		end

		-- Nested category
		local newPath = table.clone(path)
		table.insert(newPath, key)

		result[key] = ProcessCategory(item, newPath)
	end

	return result
end

local function BuildIndex()
	for categoryName, category in pairs(Database) do
		for itemIndex, item in pairs(category) do
			if type(item) == "table" and item.ID then
				IDIndex[CategoryID[categoryName].."_"..item.ID] = item
			end
		end
	end
end

--// Loader: Load all ModuleScripts safely
local function LoadModules(): {[string]: Category}
	local modules = {}

	for _, child in ipairs(script:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(modules, child)
		end
	end

	local results: {[string]: Category} = {}

	for _, moduleScript in ipairs(modules) do
		local success, data = pcall(require, moduleScript)

		if not success or type(data) ~= "table" then
			warn(`Failed to load module: {moduleScript.Name}`)
			continue
		end

		results[moduleScript.Name] = data
	end

	return results
end

--// Special Post-Processing (example logic)
local function ApplyLuggageColors(data: {[string]: Category})
	local luggage = data["Luggage"]
	if not luggage then return end

	for index, group in pairs(luggage) do
		local color = (index == 1 and "Red") or (index == 2 and "Green") or "Blue"

		for _, item in pairs(group) do
			if type(item) == "table" then
				item.Color = color
				item.HoldState = game.ReplicatedStorage.Shared.Item.Luggage
			end
		end
	end
end

--// Init
function module.Init()
	local rawModules = LoadModules()

	local index = 1
	for categoryName, categoryData in pairs(rawModules) do
		Database[categoryName] = ProcessCategory(categoryData, {categoryName})
		CategoryID[categoryName] = index
		index += 1
	end

	ApplyLuggageColors(Database)
	BuildIndex()

	print("Database Fully Loaded")
	_G["Database"] = module
	Loaded = true
	return module
end

--// API: Wait until loaded
local function WaitUntilLoaded()
	if Loaded then return end
	repeat task.wait() until Loaded
end

--// API: Get item
function module.GetItem(category: string, itemName: string): Item?
	WaitUntilLoaded()

	local cat = Database[category]
	if not cat then return nil end

	return cat[itemName] :: Item?
end

--// API: Path traversal
function module.GetPath(path: {string}): any
	WaitUntilLoaded()

	local current: any = Database

	for _, key in ipairs(path) do
		current = current[key]
		if not current then return nil end
	end

	return current
end

--// API: Find by ID
function module.GetByID(path: {string}, id: number): Item?
	local parent = module.GetPath(path)
	if not parent then return nil end

	for _, item in pairs(parent) do
		if type(item) == "table" and item.ID == id then
			return item
		end
	end

	return nil
end

--// API: Find by ID v2
function module.GetByIDFast(id1:number,id2: number): Item?
	return IDIndex[id1.."_"..id2]
end

return module
