require "Window"
require "GameLib"
require "Apollo"
 
local MailAutoText = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("MailAutoText", false, {"Mail"}, "Gemini:Hook-1.0")

function MailAutoText:OnEnable()
	-- TODO: Check if "Mail" is installed (or have been replaced)
	Apollo.RegisterEventHandler("MailAddAttachment", "ItemAttachementAdded", self)
	
	-- Hooking can only be done once the "luaMailCompose" object is initialized inside Mail
	self:PostHook(Apollo.GetAddon("Mail"), "ComposeMail", self.HookMailModificationFunctions)
end

function MailAutoText:HookMailModificationFunctions() 
	Print("Hooking mail functions")
	
	-- Store ref to Mail's attachment removed function and replace with own
	MailAutoText.fMailAttachmentRemoved = Apollo.GetAddon("Mail").luaComposeMail.OnClickAttachment
	Apollo.GetAddon("Mail").luaComposeMail.OnClickAttachment = MailAutoText.ItemAttachementRemoved
end

function MailAutoText:ItemAttachementAdded(nValue)
	Print("Item attachment added")
	
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

function MailAutoText:ItemAttachementRemoved(wndHandler, wndControl)
	-- Direct call to original Mail "attachment removed" function
	MailAutoText.fMailAttachmentRemoved(Apollo.GetAddon("Mail").luaComposeMail, wndHandler, wndControl)
	
	-- Then add custom handling
	Print("Item attachment removed")
end