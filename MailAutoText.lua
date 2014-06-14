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
	-- Store ref to Mail's attachment removed function and replace with own
	MailAutoText.fMailAttachmentRemoved = Apollo.GetAddon("Mail").luaComposeMail.OnClickAttachment
	Apollo.GetAddon("Mail").luaComposeMail.OnClickAttachment = MailAutoText.ItemAttachmentRemoved
	
	MailAutoText.fMailMoneyAttached = Apollo.GetAddon("Mail").luaComposeMail.OnCashAmountChanged
	Apollo.GetAddon("Mail").luaComposeMail.OnCashAmountChanged = MailAutoText.CashAmountChanged
	
	MailAutoText.fMailMoneyCODOn = Apollo.GetAddon("Mail").luaComposeMail.OnMoneyCODCheck
	Apollo.GetAddon("Mail").luaComposeMail.OnCashAmountChanged = MailAutoText.MoneyCODOn 
	
	MailAutoText.fMailMoneyCODOff = Apollo.GetAddon("Mail").luaComposeMail.OnMoneyCODUncheck
	Apollo.GetAddon("Mail").luaComposeMail.OnCashAmountChanged = MailAutoText.MoneyCODOff 
	
	MailAutoText.fMailMoneySendOnn = Apollo.GetAddon("Mail").luaComposeMail.OnMoneySendCheck
	Apollo.GetAddon("Mail").luaComposeMail.OnCashAmountChanged = MailAutoText.MoneySendOn 
	
	MailAutoText.fMailMoneySendOff = Apollo.GetAddon("Mail").luaComposeMail.OnMoneySendUncheck
	Apollo.GetAddon("Mail").luaComposeMail.OnCashAmountChanged = MailAutoText.MoneySendOff
end

function MailAutoText:ItemAttachmentAdded(nValue)
	-- Calculate new item-string and trigger body-update
	MailAutoText.strItemList = MailAutoText:GenerateItemListString(nValue)
	MailAutoText:UpdateMessage()
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
	
	-- Calculate new item-string and trigger body-update
	MailAutoText.strItemList = MailAutoText:GenerateItemListString()
	MailAutoText:UpdateMessage()
end

function MailAutoText:GenerateItemListString(newAttachmentId)
	
	-- Deep-copy "arAttachments" into local array
	local allAttachmentIds = {}
	for k,v in ipairs(Apollo.GetAddon("Mail").luaComposeMail.arAttachments) do
		allAttachmentIds[k] = v
	end
	
	-- Check if the newly-added item (if any) already exist in array
	local bExists = false
	for k,v in ipairs(allAttachmentIds) do
		if v == newAttachmentId then
			bExists = true
		end
	end
	
	-- Add new item to end of array if not present
	if bExists == false then
		allAttachmentIds[#allAttachmentIds+1] = newAttachmentId
	end
	
	-- Concatenate list of items
	local strItems = ""
	for _,attachmentId in ipairs(allAttachmentIds) do
		local itemId = MailSystemLib.GetItemFromInventoryId(attachmentId):GetItemId()
		local itemDetails = Item.GetDetailedInfo(itemId)
		strItems = strItems .. itemDetails.tPrimary.strName .. "\n"
	end
	
	return strItems
end

function MailAutoText:GenerateSubjectString()
	-- Update message subject if not already specified
	local currentSubject = Apollo.GetAddon("Mail").luaComposeMail.wndSubjectEntry:GetText()
	if currentSubject == nil or currentSubject == "" then
		-- TODO: different text depending on actual content
		return "Sending items" 
	end
	
	return currentSubject
end

function MailAutoText:UpdateMessage()
	local bCreditsText = MailAutoText.strCredits ~= nil and MailAutoText.strCredits ~= ""
	local bItemListText = MailAutoText.strItemList ~= nil and MailAutoText.strItemList ~= ""
	
	-- Update subject
	Apollo.GetAddon("Mail").luaComposeMail.wndSubjectEntry:SetText(MailAutoText:GenerateSubjectString())

	-- Update body
	local currentBody = Apollo.GetAddon("Mail").luaComposeMail.wndMessageEntryText:GetText()
	
	-- Cut off the bottom half (our auto-text) of the msg body
	local newBody = ""
	if currentBody ~= nil then
		local index = string.find(currentBody, "Attachments:")
		
		if index == nil then
			newBody = currentBody
		else
			local strFirst = string.sub(currentBody, 1, (index-1))
			newBody = strFirst
		end
	end
	
	-- Append "Attachments" header if any attachments are identified
	if bCreditsText == true or bItemListText == true then
		if newBody == "" then
			newBody = "Attachments:\n"
		else
			newBody = newBody .. "Attachments:\n"
		end
	end
	
	-- Append credits text if sending credits
	if bCreditsText == true then
		newBody = newBody .. "Credits: " .. " X dollahs"
	end
	
	if bItemListText == true then
		newBody = newBody .. MailAutoText.strItemList
	end	
	
	Apollo.GetAddon("Mail").luaComposeMail.wndMessageEntryText:SetText(newBody)
end

function MailAutoText:CashAmountChanged()
	MailAutoText:GoldPrettyPrint(Apollo.GetAddon("Mail").luaComposeMail.wndCashWindow:GetAmount())
	--Print(Apollo.GetAddon("Mail").luaComposeMail.wndCashWindow:GetAmount().. "added")
end

function MailAutoText:MoneyCODOn()
	-- Remove currency line and update body
end

function MailAutoText:MoneyCODOff()
	-- Remove COD line and update body
end

function MailAutoText:MoneySendOn()
	-- Remove COD line and update body
end

function MailAutoText:MoneySendOff()
	-- Remove currency line and update body
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