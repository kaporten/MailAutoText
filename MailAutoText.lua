require "Apollo"
require "Window"
require "GameLib"

local MailAutoText = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("MailAutoText", false, {"Mail"}, "Gemini:Hook-1.0")
MailAutoText.ADDON_VERSION = {3, 5, 1}

local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("MailAutoText")

-- Reference to Mail addon, initialized during OnEnable
local M

local tFilter = {
	{"[Pp]ine", "P!ne"} -- Pine is apparently a nasty word
}

function MailAutoText:OnEnable()
	--[[
		Hooking into the mail composition GUI itself can only be done 
		once the "luaMailCompose" object is initialized inside Mail. 
		So posthook on the "compose mail" button-function, and set up 
		futher hooks once there.
	]]
	-- Get permanent ref to addon mail - stop addon initializationif Mail cannot be found.
	M = Apollo.GetAddon("Mail")	
	if M ~= nil then
		MailAutoText:RawHook(M, "ComposeMail", MailAutoText.HookMailModificationFunctions)
	end
	
	Event_FireGenericEvent("OneVersion_ReportAddonInfo", "MailAutoText", self.ADDON_VERSION[1], self.ADDON_VERSION[2], self.ADDON_VERSION[3])
end

-- Sets up hooks for client-side mail content modifications
function MailAutoText:HookMailModificationFunctions()
	-- First, call the original ComposeMail function
	MailAutoText.hooks[M]["ComposeMail"](M)
	
	local luaMail = M.luaComposeMail
	
	--[[
		Only hook luaComposeMail functions if they are not already hooked.
		If user clicks "Begin New Mail" multiple times, it will just re-show the active luaComposeMail
		In that case, don't re-hook since that causes errors.
		
		Check if luaComposeMail functions are already hooked by checking the OnClickAttachment function
		for existing hooks.
	]]	
	local bAlreadyHooked = MailAutoText:IsHooked(luaMail, "OnClickAttachment")
	if bAlreadyHooked then 
		return 
	end	
	
	-- Attachment added/removed
	MailAutoText:RawHook(luaMail, "AppendAttachment", MailAutoText.ItemAttachmentAdded) 	-- Attachment added
	MailAutoText:RawHook(luaMail, "OnClickAttachment", MailAutoText.ItemAttachmentRemoved) 	-- Attachment removed
	
	-- Cash state changes
	MailAutoText:RawHook(luaMail, "OnCashAmountChanged", MailAutoText.OnCashAmountChanged)	-- Cash amount changed
	MailAutoText:RawHook(luaMail, "OnMoneyCODCheck", MailAutoText.OnMoneyCODCheck) 			-- "Request" checked
	MailAutoText:RawHook(luaMail, "OnMoneyCODUncheck", MailAutoText.OnMoneyCODUncheck) 		-- "Request" unchecked
	MailAutoText:RawHook(luaMail, "OnMoneySendCheck", MailAutoText.OnMoneySendCheck) 		-- "Send" checked
	MailAutoText:RawHook(luaMail, "OnMoneySendUncheck", MailAutoText.OnMoneySendUncheck) 	-- "Send" unchecked	
	
	-- Mail closed
	MailAutoText:RawHook(luaMail, "OnClosed", MailAutoText.OnClosed) 						-- Mail is closed for whatever reason (cancelled/sent)
end

--[[ 
	Cash state-change hook functions.
]]
function MailAutoText:OnCashAmountChanged()
	MailAutoText:CashStateChanged("OnCashAmountChanged")
end

function MailAutoText:OnMoneyCODCheck(wndHandler, wndControl)
	MailAutoText:CashStateChanged("OnMoneyCODCheck", wndHandler, wndControl)
end

function MailAutoText:OnMoneyCODUncheck(wndHandler, wndControl)
	MailAutoText:CashStateChanged("OnMoneyCODUncheck", wndHandler, wndControl)
end

function MailAutoText:OnMoneySendCheck(wndHandler, wndControl)
	MailAutoText:CashStateChanged("OnMoneySendCheck", wndHandler, wndControl)
end

function MailAutoText:OnMoneySendUncheck(wndHandler, wndControl)
	MailAutoText:CashStateChanged("OnMoneySendUncheck", wndHandler, wndControl)
end

function MailAutoText:CashStateChanged(functionName, wndHandler, wndControl)
	-- Pass call to original function
	local ret = MailAutoText.hooks[M.luaComposeMail][functionName](M.luaComposeMail, wndHandler, wndControl)
	
	-- Update the auto-generated message subject and body texts
	MailAutoText:UpdateMessage() 
	
	-- Force an update of the mail composition controls. 
	-- This ensures controls such as Send button is correctly activated if we add auto-text.
	M.luaComposeMail:UpdateControls()
	return ret	
end

function MailAutoText:OnClosed(wndHandler)
	-- Pass call on to original function
	local ret = MailAutoText.hooks[M.luaComposeMail]["OnClosed"](M.luaComposeMail, wndHandler)
	
	-- When mail is closed, clear the previously generated message body
	MailAutoText.strItemList = ""
	
	-- Also clear the last value fields for recipient field.
	MailAutoText.strPreviouslyEntered = ""
	
	return ret
end

function MailAutoText:ItemAttachmentAdded(nValue)
	-- Pass call on to original function so Mail state is fully updated
	local ret = MailAutoText.hooks[M.luaComposeMail]["AppendAttachment"](M.luaComposeMail, nValue)
	
	-- Generate new item-string and trigger message update
	MailAutoText.strItemList = MailAutoText:GenerateItemListString(nValue, nil)
	MailAutoText:UpdateMessage()
	
	-- Trigger another controls-update on the Mail GUI (to enable Send if we just added text)
	M.luaComposeMail:UpdateControls()
	
	-- Return result from original function to original caller
	return ret
end

-- Called when an attachment is removed. Triggered by the "Mail" Addons GUI interactions.
-- Extracted parameter "iAttach" is the index of the attachment being removed.
function MailAutoText:ItemAttachmentRemoved(wndHandler, wndControl)
	-- Pass call on to original function so Mail state is fully updated
	local ret = MailAutoText.hooks[M.luaComposeMail]["OnClickAttachment"](M.luaComposeMail, wndHandler, wndControl)
		
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
	
	-- Trigger another controls-update on the Mail GUI (to enable Send if we just added text)
	M.luaComposeMail:UpdateControls()
	
	-- Return result from original function to original caller
	return ret
end


function MailAutoText:IsSendingCash()
	if M.luaComposeMail ~= nil then
		return M.luaComposeMail.wndCashSendBtn:IsChecked() and M.luaComposeMail.wndCashWindow:GetAmount():GetAmount(Money.CodeEnumCurrencyType.Credits) > 0
	else
		return false
	end	
end

function MailAutoText:IsRequestingCash()
	if M.luaComposeMail ~= nil then
		return M.luaComposeMail.wndCashCODBtn:IsChecked() and MailAutoText:HasAttachments() and M.luaComposeMail.wndCashWindow:GetAmount():GetAmount(Money.CodeEnumCurrencyType.Credits) > 0
	else
		return false
	end	
end

function MailAutoText:HasAttachments()
	return M.luaComposeMail ~= nil and M.luaComposeMail.arAttachments ~= nil and #M.luaComposeMail.arAttachments > 0
end

-- Called whenever an attachment is added or removed. Produces a string describing all attachments.
function MailAutoText:GenerateItemListString(addedAttachmentId)

	-- Deep-copy "arAttachments" (except removed index) into local array
	local allAttachmentIds = {}
	for k,v in ipairs(M.luaComposeMail.arAttachments) do
		allAttachmentIds[#allAttachmentIds+1] = v
	end

	-- Check if the newly-attached item (if any) already exist in array, since we do not control the event call-order
	local bExists = false
	for k,v in ipairs(allAttachmentIds) do
		if v == addedAttachmentId then
			bExists = true
		end
	end

	-- Add new item to end of array if not present
	if bExists == false then
		allAttachmentIds[#allAttachmentIds+1] = addedAttachmentId
	end

	-- Concatenate list of items
	local strItems = ""
	for _,attachmentId in ipairs(allAttachmentIds) do
		local itemData = MailSystemLib.GetItemFromInventoryId(attachmentId)
		local itemId = itemData:GetItemId()
		local stackCount = itemData:GetStackCount()
		local itemDetails = Item.GetDetailedInfo(itemId)
		
		strItems = strItems .. itemDetails.tPrimary.strName		
		if stackCount > 1 then
			strItems = strItems .. " (x" .. stackCount .. ")"
		end
		strItems = strItems .. "\n"
	end

	return strItems
end

-- Generates the subject-line based on current subject, and mail contents.
function MailAutoText:GenerateSubjectString()
	-- Get current subject string from GUI
	local currentSubject = M.luaComposeMail.wndSubjectEntry:GetText()
	
	-- Check if current subject is an auto-generated one (or empty). If so, replace with updated auto-generated one
	local bGenerated = false
	if currentSubject == "" then 
		bGenerated = true
	else
		for k,v in pairs(L) do
			if v == currentSubject then 
				bGenerated = true
				break
			end
		end
	end
	
	-- Not an auto-generated subject? just return current subject then
	if bGenerated == false then
		return currentSubject
	end
	
	-- Sending items COD?
	if MailAutoText:IsRequestingCash() then
		return L["Subject_COD"]
	end
	
	-- Sending items and cash?
	if MailAutoText:IsSendingCash() == true and MailAutoText.strItemList ~= nil and MailAutoText.strItemList ~= "" then
		return L["Subject_Both"]
	end
	
	-- Sending items only?
	if MailAutoText.strItemList ~= nil and MailAutoText.strItemList ~= "" then
		return L["Subject_Items"]
	end

	-- Sending cash only?
	if MailAutoText:IsSendingCash() == true then
		return L["Subject_Cash"]
	end
	
	-- Not sending anything, clear generated subject
	return ""
end

function MailAutoText:UpdateMessage()
	local amtCash = M.luaComposeMail.wndCashWindow:GetAmount():GetAmount(Money.CodeEnumCurrencyType.Credits) 
	local bCreditsText = (MailAutoText:IsSendingCash() or MailAutoText:IsRequestingCash()) and amtCash ~= nil
	local bItemListText = MailAutoText.strItemList ~= nil and MailAutoText.strItemList ~= ""

	-- Update subject
	M.luaComposeMail.wndSubjectEntry:SetText(MailAutoText:GenerateSubjectString())

	-- Update body
	local currentBody = M.luaComposeMail.wndMessageEntryText:GetText()

	-- Cut off the bottom half (our auto-text) of the msg body
	local strAttachments = Apollo.GetString("CRB_Attachments") .. ":\n"
	local newBody = ""
	if currentBody ~= nil then
		local index = string.find(currentBody, strAttachments)

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
			newBody = strAttachments
		else
			newBody = newBody .. strAttachments
		end
	end

	-- Append credits text if sending credits
	if bCreditsText == true then
		local m = Money.new(Money.CodeEnumCurrencyType.Credits)
		m:SetAmount(amtCash)
		
		if MailAutoText:IsRequestingCash() == true then
			newBody = newBody .. Apollo.GetString("CRB_Request_COD") .. ": " .. m:GetMoneyString() .. "\n"
		end
		if MailAutoText:IsSendingCash() == true then
			newBody = newBody .. Apollo.GetString("CRB_Send_Money") .. ": " .. m:GetMoneyString() .. "\n"
		end
	end

	-- Append itemlist if sending items
	if bItemListText == true then
		newBody = newBody .. MailAutoText.strItemList
	end

	-- Run the censorship filter to remove words that prevents mail-sending
	for _,s in ipairs(tFilter) do
		newBody = string.gsub(newBody, s[1], s[2])
	end
	
	-- Update body
	M.luaComposeMail.wndMessageEntryText:SetText(newBody)
end