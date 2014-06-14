require "Window"
require "GameLib"
require "Apollo"
 
--local MailAutoText = Apollo.GetPackage("Gemini:Addon-1.0").tPackage:NewAddon("MailAutoText", false, {})

local MailAutoText = {}

function MailAutoText:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

function MailAutoText:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {}
	
	Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end

function MailAutoText:OnLoad()
	-- TODO: Check if "Mail" is installed (or have been replaced)
	--Apollo.GetAddon("Mail").luaComposeMail:FindChild("HeaderTitle"):SetText("Nyt og moderne!")
	Apollo.RegisterEventHandler("MailAddAttachment", "OnMailAddAttachment", self)
end

function MailAutoText:OnMailAddAttachment(nValue)
	local mail = Apollo.GetAddon("Mail")

	Print("Yarr: " .. nValue)
	
	-- Get id of item just added to message, and get detailed item info
	local itemId = MailSystemLib.GetItemFromInventoryId(nValue):GetItemId()
	local itemDetails = Item.GetDetailedInfo(itemId)
	
	Print("item id: " .. itemId)
	
	-- Update message subject if not already specified
	local currentSubject = mail.luaComposeMail.wndSubjectEntry:GetText()
	if currentSubject == nil or currentSubject == "" then
		mail.luaComposeMail.wndSubjectEntry:SetText("Sending items")
	end
	
	local currentMailBody = mail.luaComposeMail.wndMessageEntryText:GetText()
	mail.luaComposeMail.wndMessageEntryText:SetText(currentMailBody .. "\n" .. itemDetails.tPrimary.strName)
	
end


local MailAutoTextInst = MailAutoText:new()
MailAutoTextInst:Init()
