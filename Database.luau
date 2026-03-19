local module = {}
local InsertService = game:GetService("InsertService")

--[[---------------------
	Variables
--]]---------------------

local AllItems = {}
local ChangeToName = true
module.AllItems = {}
module.Loaded = false

local TierToRarity = {
	Common 		= 1,
	Uncommon 	= 2,
	Rare 		= 3,
	Epic 		= 4,
	Legendary 	= 5,
	Mythic 		= 6,
	Secret 		= 7,
	Exclusive 	= 8,
}

--[[---------------------
	Function
--]]---------------------

-- Parallel processing utility - processes multiple items concurrently
-- @param items: table - Array of items to process
-- @param processor: function - Function to process each item (receives item, index)
-- @param maxConcurrent: number? - Optional: Maximum concurrent tasks (default: unlimited)
-- @return: table - Array of results in same order as input
local function ProcessParallel(items, processor, maxConcurrent)
	if type(items) ~= "table" or type(processor) ~= "function" then
		warn("ProcessParallel: Invalid arguments")
		return {}
	end

	local results = {}
	local completedCount = 0
	local totalCount = #items
	local currentIndex = 1

	-- If no items, return empty table
	if totalCount == 0 then
		return results
	end

	-- If maxConcurrent is set, process in batches
	if maxConcurrent and maxConcurrent > 0 then
		local function processBatch()
			while currentIndex <= totalCount do
				local index = currentIndex
				currentIndex = currentIndex + 1

				task.spawn(function()
					local success, result = pcall(processor, items[index], index)
					results[index] = success and result or nil
					completedCount = completedCount + 1
				end)

				-- If we've started maxConcurrent tasks, wait for one to finish
				if currentIndex - completedCount >= maxConcurrent then
					task.wait(0.01)
				end
			end
		end

		-- Start initial batch
		processBatch()

		-- Wait for all to complete
		repeat
			task.wait(0.01)
		until completedCount == totalCount
	else
		-- Process all concurrently (unlimited)
		for i, item in ipairs(items) do
			task.spawn(function()
				local success, result = pcall(processor, item, i)
				results[i] = success and result or nil
				completedCount = completedCount + 1
			end)
		end

		-- Wait for all to complete
		repeat
			task.wait(0.01)
		until completedCount == totalCount
	end

	return results
end

module.ProcessParallel = ProcessParallel

-- Copy The Entire Table 
local function deepCopy(original)
	local copy = {}
	for k, v in pairs(original) do
		if type(v) == "table" then
			v = module.deepCopy(v)
		end
		copy[k] = v
	end
	return copy
end

-- Turn unusable imageid to usable one
local function ProcessImage(decalid)
	if decalid then
		--print(decalid)
		local succ,err = pcall(function()
			local model = InsertService:LoadAsset(decalid)
			decalid = model.Decal.Texture
			model:Destroy()
		end)
		if typeof(decalid)=="number" then decalid = "rbxassetid://"..decalid end -- warn(err,item.Name,decalid) end
		--print("New"..decalid)
	else
		decalid = 0
	end
	return decalid
end

-- from num to tier
local function RarityToTier(Rarity)
	for i,v in pairs(TierToRarity) do
		if v == Rarity then return i end
	end
end

--[[---------------------
	Main Function
--]]---------------------

-- Convert the item stats
local function ProcessItem(item)
	---------------------------------------------------
	-- Convert Decal Id into ImageLabel id
	if item.Rarity then
		item.Tier = RarityToTier(item.Rarity)
	end
	if item.ImageID then
		local decalid = ProcessImage(item.ImageID)
		item.ImageID = decalid
	end
		
	return item
end

-- Process the entire category of each stuff
local function ProcessCategory(tab,CatName)
	local CatPath = type(CatName)=="table" and CatName or {CatName}
	local newTab = {}
	
	-- Convert table to array for parallel processing
	local itemsArray = {}
	for i, item in pairs(tab) do
		table.insert(itemsArray, {key = i, value = item})
	end
	
	-- Process items in parallel with concurrency limit (max 10 at a time)
	ProcessParallel(itemsArray, function(itemData)
		local i = itemData.key
		local item = itemData.value
		
		if type(item)=="table" then
			if item.Name then
				ProcessItem(item)
				item.Category = CatPath
				if ChangeToName then
					newTab[item.Name] = item
				else
					newTab[i] = item
				end
			else
				-- Recursive call for nested categories (also parallel)
				local NewPath = deepCopy(CatPath)
				table.insert(NewPath,i)
				local newitem = ProcessCategory(item,NewPath)
				newTab[i] = newitem
			end
		elseif type(item)=="number" then
			newTab[i] = ProcessImage(item)
			--print(newTab[i])
		end
	end, 10) -- Limit to 10 concurrent items per category
	
	return newTab
end

--  get the item in category
function module.GetItem(category,item)
	if not module.Loaded then repeat task.wait() until module.Loaded end
	local category = module.AllItems[category]
	if not category then return end
	return category[item]
end

-- Get Path From Parent + Key
function module.Path(Parent,key)
	local path = Parent
	if key then
		if type(key) == "table" then
			for i,v in pairs(key) do
				path = path[v]
			end
		else
			path = path[key]
		end
	end
	return path
end

-- finditemfromid
function module.GetID(path,id)
	local parent = module.Path(module.AllItems,path)
	if not parent then return end
	for i,v in pairs(parent) do
		if v.ID == id then return v end
	end
end

-- main function to process all children
local function CollectAllChildrenStat()
	local moduleScripts = {}
	for _, moduleScript in ipairs(script:GetChildren()) do
		if moduleScript:IsA("ModuleScript") then
			table.insert(moduleScripts, moduleScript)
		end
	end

	-- Use ProcessParallel to load all categories concurrently (max 5 at a time)
	ProcessParallel(moduleScripts, function(moduleScript)
		local success, items = pcall(function()
			return require(moduleScript)
		end)
		
		if success and items then
			local categoryName = moduleScript.Name
			local newitem = ProcessCategory(items, categoryName)
			AllItems[categoryName] = newitem
		end
	end, 5) -- Limit to 5 concurrent categories
	
	for i,v in pairs(AllItems.Luggage) do -- Give Luggage Color
		local Color = (i==1 and "Red") or (i==2 and "Green") or "Blue"
		for a,b in pairs(v) do
			b.Color = Color
			b.HoldState = game.ReplicatedStorage.Shared.Item.Luggage
		end
	end
	
	print(AllItems)
	
	module.AllItems = AllItems
	module.AllItems["GetID"] = module.GetID
	_G["Database"] = module.AllItems
	
	module.Loaded = true
	print("Database Fully Loaded")
end

function module.Init()
	CollectAllChildrenStat()
	return module
end

return module
