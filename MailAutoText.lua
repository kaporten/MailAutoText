require "Window"
require "GameLib"
require "Apollo"
 
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

	-- Get id of item just added to message, and get detailed item info
	local itemId = MailSystemLib.GetItemFromInventoryId(nValue):GetItemId()
	local itemDetails = Item.GetDetailedInfo(itemId)
	
	-- Update message subject if not already specified
	local currentSubject = mail.luaComposeMail.wndSubjectEntry:GetText()
	if currentSubject == nil or currentSubject == "" then
		mail.luaComposeMail.wndSubjectEntry:SetText("Sending items")
	end
	
	-- Add a line of text to the message body
	local currentMailBody = mail.luaComposeMail.wndMessageEntryText:GetText()
	if currentMailBody == nil or currentMailBody == "" then
		-- Replace entire contents (to avoid blank lines)
		mail.luaComposeMail.wndMessageEntryText:SetText(itemDetails.tPrimary.strName)
	else
		-- Append line
		mail.luaComposeMail.wndMessageEntryText:SetText(currentMailBody .. "\n" .. itemDetails.tPrimary.strName)
	end
end

local MailAutoTextInst = MailAutoText:new()
MailAutoTextInst:Init()
