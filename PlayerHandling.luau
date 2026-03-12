local module = {}
module.__index = module

local imgplaceholderid = 17411801160
local CardTemplate

local ColorDict = {
	Cost = Color3.fromRGB(0, 125, 255),
	Speed = Color3.fromRGB(255, 255, 0),
	Range = Color3.fromRGB(255, 0, 0),
	Target = Color3.fromRGB(0, 255, 0),
	Default = Color3.fromRGB(255,255,255)
}

local EffectColor = {
	Target = Color3.fromRGB(255, 66, 66),
	Effect = Color3.fromRGB(118, 164, 255),
}

local function GetColor(nam)
	return ColorDict[nam] or ColorDict["Default"]
end

local ModeDict = {
	primary = "Target",
	auto = "All",
	random = "Random",
}

------------------------- Other Module

local function PluralCheck(str,num)
	if num and num == 1 and string.sub(str,#str-2) == "ies" then
		str = string.sub(str,0,#str-3).."y"
	end
	return str
end

local function UpperCase(str)
	return string.upper(string.sub(str, 1, 1))..string.sub(str, 2, -1)
end

local function ColorFont(str,Color:Color3)
	if typeof(Color) == "Color3" then
		Color = string.format('rgb(%s,%s,%s)',math.ceil(Color.R*255),math.ceil(Color.G*255),math.ceil(Color.B*255))
	end
	return string.format('<font color="%s">%s</font>',Color,str)
end

local function CheckValidImg(id)
	local valid
	if type(id)=="number" then
		local info = game:GetService('MarketplaceService'):GetProductInfo(id, Enum.InfoType.Asset)
		if info and info.AssetTypeId == 13 then
			valid = true
		end
	end
	if not valid then
		id = imgplaceholderid
	end
	return "rbxassetid://"..id
end

local function TableToString(tab,num)
	if type(tab)=="string" then return tab end
	if (not tab) then return "" end
	local T = ""
	for i,v in pairs (tab) do
		if num==2 then -- Shorten "TT"
			T = string.upper(T..string.sub(v,1,1))
		else -- "Text,Text"
			local str = (type(v)=="string" and v) or i
			str = UpperCase(str)
			T= (T=="" and str) or T..","..str
		end
	end
	return T
end

------------------ Main Module

function module.Init(UI)
	CardTemplate = UI.CardTemplate
	local InfoTemp = CardTemplate.Left.Template
	local EffectTemp = CardTemplate.Right.Template
	local ETypeTemp = EffectTemp.Template
	local SEffectTemp = ETypeTemp.Template
	local AllTemp = {CardTemplate,InfoTemp,EffectTemp,ETypeTemp,SEffectTemp}

	--[[
	for i,v in pairs(AllTemp) do
		v.Visible = false
	end
	--]]
	CardTemplate.Visible = false
end

function module.FormatInfo(Inf,Card)
	--- Middle Part Info ---

	local suffix = Inf.suffix and " ".."Strike" or ""
	Inf.Name = Inf.move_name .. suffix
	Inf.Desc = Inf.description
	Inf.Img = Inf.image or ""

	--- Left Side Info ---

	local cost = Inf.cost
	local cost2 = "TP"
	local speed = Inf.speed
	local range = Inf.min_range.."-"..Inf.range

	local T = Inf.primary_targeting
	local T1 = T.mode == "auto" and "all" or T.amount -- "select"
	if T.mode == "random" then T1 = T1.." Random" end
	local T2 = {}
	for i,v in pairs(T.valid_targets) do
		table.insert(T2,i)
	end
	Inf.T1 = T1
	Inf.T2 = T2

	Inf.Cost = {"Cost",cost,cost2}
	Inf.Speed = {"Speed",speed}
	Inf.Range = {"Range",range}
	Inf.Target = {"Target",T1,T2}
	Inf.Meta = {Inf.Cost,Inf.Speed,Inf.Range,Inf.Target}

	--- Right Side Info ---

	Inf.Effect = Inf.moves

	return Inf
end

function module.NewInfo(Info,Card) -- Left Side
	local Template1 = Card.Left.Template
	for order,tab in pairs(Info.Meta) do
		local NewInf = Template1:Clone()
		NewInf.Name = order
		NewInf.LayoutOrder = order

		local T3 = TableToString(tab[3])
		local T4 = TableToString(tab[3],2)

		T3 = PluralCheck(T3,tab[2])

		local SFormat = string.format("%s %s %s",tab[1],tab[2],T3)
		NewInf.Text = SFormat

		NewInf.ImageLabel.ImageColor3 = GetColor(tab[1])
		--local numbers = string.gsub(tab[1][2], "%D", "")
		NewInf.ImageLabel.TextLabel.Text = tab[2] .. T4

		NewInf.Parent = Template1.Parent
	end
	--Template1:Destroy()
end

function module.NewEffectInf(Info,Card) -- Right Side
	local Template1 = Card.Right.Template
	for movenum,move in pairs(Info.Effect) do
		local NewInf = Template1:Clone()
		NewInf.Name = "Move "..movenum
		NewInf.Title.Text = "Effect "..movenum

		for _,tab in (move) do
			local NewDesc = NewInf.Template:Clone()
			NewDesc.Name = tab.trigger
			NewDesc.Effect.Text = tab.trigger or ""

			for i,v in pairs(tab.effects) do
				local NewEff = NewDesc.Template:Clone()
				NewEff.Name = v.type.." "..i
				NewEff.LayoutOrder = i

				local Apply = (v.type=="DMG"and"Deal")or"Apply"
				local T = v.targeting
				local T1 = ModeDict[T.mode]
				local T2 = TableToString(T.valid_targets)
				local T3 = T.amount
				T2 = PluralCheck(T2,T3)
				T3 = T3 and T3.." " or ""
				if T2 == "Self" then T1 = "" end -- No "All Self"
				local Effect = ColorFont(v.potency.." "..v.type,EffectColor.Effect)
				local Target = ColorFont(T3..T1.." "..T2,EffectColor.Target)

				local Format = "%s %s To %s"
				NewEff.Text = string.format(Format,Apply,Effect,Target)
				NewEff.Parent = NewDesc
				--NewEff.Text = "Deal 40 Damage to Target"
				--NewEff.Text = "Apply Fear To All Enemies"
				--NewEff.Text = "Apply Morale Boost To All Allies"
			end
			NewDesc.Parent = NewInf
			NewInf.Parent = Template1.Parent
		end
	end
end

function module.NewMidPart(Info,Clon)
	Clon.Mid.Title.Text = Info.Name
	Clon.Mid.Desc.Text = Info.Desc
	Clon.Mid.Pic.Pic.Image = CheckValidImg(Info.Img)
	for _,tab in pairs(Info.Effect) do
		for a,b in pairs(tab) do
			local NewTag = Clon.Mid.Pic.Tag.Template:Clone()
		end
	end
end

function module.NewCard(CardInfo)
	local Info = module.FormatInfo(CardInfo)
	setmetatable(Info,module)
	local Clon = CardTemplate:Clone()
	Clon.Name = CardInfo.move_name
	Clon.Visible = true

	Info:NewInfo(Clon)
	Info:NewEffectInf(Clon)
	Info:NewMidPart(Clon)

	for i,v in pairs(Clon:GetDescendants()) do
		if v.Name == "Template" then
			v:Destroy()
		end
	end

	Clon.Parent = CardTemplate.Parent
	return Clon
end

return module
