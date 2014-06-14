require "Window"
require "GameLib"
require "Apollo"
 
local MailAutoText = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("MailAutoText", false, {"Mail"}, "Gemini:Hook-1.0")

function MailAutoText:OnEnable()
	-- TODO: Check if "Mail" is installed (or have been replaced)
	Apollo.RegisterEventHandler("MailAddAttachment", "ItemAttachmentAdded", self)
	
	-- Hooking can only be done once the "luaMailCompose" object is initialized inside Mail
	self:PostHook(Apollo.GetAddon("Mail"), "ComposeMail", self.HookMailModificationFunctions)
end

function MailAutoText:HookMailModificationFunctions() 
	Print("Hooking mail functions")
	
	-- Store ref to Mail's attachment removed function and replace with own
	MailAutoText.fMailAttachmentRemoved = Apollo.GetAddon("Mail").luaComposeMail.OnClickAttachment
	Apollo.GetAddon("Mail").luaComposeMail.OnClickAttachment = MailAutoText.ItemAttachmentRemoved
	
	MailAutoText.fMainMoneyAttached = Apollo.GetAddon("Mail").luaComposeMail.OnCashAmountChanged
	Apollo.GetAddon("Mail").luaComposeMail.OnCashAmountChanged = MailAutoText.CashAmountChanged

end

function MailAutoText:ItemAttachmentAdded(nValue)
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

function MailAutoText:ItemAttachmentRemoved(wndHandler, wndControl)
	-- Direct call to original Mail "attachment removed" function
	MailAutoText.fMailAttachmentRemoved(Apollo.GetAddon("Mail").luaComposeMail, wndHandler, wndControl)
	
	-- Function is called twice by Mail addon - these filters (copied from Mail.lua) filters out one of them
	if wndHandler ~= wndControl then
		return
	end
	local iAttach = wndHandler:GetData()
	if iAttach == nil then
		return
	end
	
	-- Then add custom handling
	Print("Item attachment removed")
end

function MailAutoText:CashAmountChanged()
	MailAutoText:GoldPrettyPrint(Apollo.GetAddon("Mail").luaComposeMail.wndCashWindow:GetAmount())
	--Print(Apollo.GetAddon("Mail").luaComposeMail.wndCashWindow:GetAmount().. "added")
end

function MailAutoText:GoldPrettyPrint(amount)
	local amount_string = tostring(amount)
	local return_string = ""
	copper = string.sub(amount_string, -2, -1)
	silver = string.sub(amount_string, -4, -3)
	gold = string.sub(amount_string, -6, -5)
	plat = string.sub(amount_string, -8, -7)
	
	if plat ~= nil and plat ~= "" then
		return_string = return_string .. plat .. " platinum "
	end
	if gold ~= nil and gold ~= "" then
		return_string = return_string .. gold .. " gold "
	end
	if silver ~= nil and silver ~= "" then 
		return_string = return_string .. silver .. " silver "
	end
	if copper ~= nil and copper ~= "" then
		return_string = return_string .. copper .. " copper"
	end
	
	-- return(return_string)
	Print(return_string)
	
end