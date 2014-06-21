
require "Window"
require "GameLib"
require "Apollo"

local MailAutoText = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("MailAutoText", false, {"Mail"}, "Gemini:Hook-1.0")
MailAutoText.ADDON_VERSION = {2, 0, 0}

local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("MailAutoText")

-- GeminiLoging, initialized during OnEnable
local log

-- Reference to Mail addon, initialized during OnEnable
local M

function MailAutoText:OnEnable()
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	log = GeminiLogging:GetLogger({
		level = GeminiLogging.FATAL,
		pattern = "%d %n %c %l - %m",
		appender = "GeminiConsole"
	})
	MailAutoText.log = log -- store ref for GeminiConsole-access to loglevel
	log:info("Initializing addon 'MailAutoText'")

	-- Prepare address book
	self.names = {"Pilfinger", "Racki", "Zica",}	
	self.strPreviousEnter = ""
	self.strPreviousMatch = ""
	
	--[[
		Hooking into the mail composition GUI itself can only be done 
		once the "luaMailCompose" object is initialized inside Mail. 
		So posthook on the "compose mail" button-function, and set up 
		futher hooks once there.
	]]
	
	-- Get permanent ref to addon mail - stop addon if Mail cannot be found.
	M = Apollo.GetAddon("Mail")	
	if M == nil then
		log:fatal("Could not load addon 'Mail'")
		return
	end

	MailAutoText:RawHook(M, "ComposeMail", MailAutoText.HookMailModificationFunctions)
	
	log:debug("Addon loaded, ComposeMail hook in place")
end

-- Sets up hooks for client-side mail content modifications
function MailAutoText:HookMailModificationFunctions()
	-- First, call the original ComposeMail function
	MailAutoText.hooks[M]["ComposeMail"](M)
	
	log:debug("New Compose Mail window opened, hooking functions")
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
		log:debug("Compose Mail was already hooked, skipping")
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

	-- Recipient
	MailAutoText:RawHook(luaMail, "OnInfoChanged", MailAutoText.OnRecipientChanged)			-- Recipient field changed
	
	-- Mail closed
	MailAutoText:RawHook(luaMail, "OnClosed", MailAutoText.OnClosed) 						-- Mail is closed for whatever reason (cancelled/sent)
	
	log:debug("Compose Mail editing functions hooked")
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
	log:debug("Cash button stage change: %s", functionName)
	
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
	log:debug("Compose Mail window closed")
	
	-- Pass call on to original function
	local ret = MailAutoText.hooks[M.luaComposeMail]["OnClosed"](M.luaComposeMail, wndHandler)
	
	-- When mail is closed, clear the previously generated message body
	MailAutoText.strItemList = ""
	
	-- Also clear the last value fields for recipient field.
	MailAutoText.strPreviousEnter = ""
	MailAutoText.strPreviousMatch = ""
	
	return ret
end

function MailAutoText:ItemAttachmentAdded(nValue)
	log:debug("Attachment added: %d", nValue)
	
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
	log:debug("Attachment removed")
	
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
	
	log:debug("Attachment index identified: %d", iAttach)
		
	-- Calculate new item-string and trigger body-update
	MailAutoText.strItemList = MailAutoText:GenerateItemListString()
	MailAutoText:UpdateMessage()
	
	-- Trigger another controls-update on the Mail GUI (to enable Send if we just added text)
	M.luaComposeMail:UpdateControls()
	
	-- Return result from original function to original caller
	return ret
end

function MailAutoText:GoldPrettyPrint(monAmount)
	if monAmount == 0 then
		return ""
	end

	local strAmount = tostring(monAmount)
	local copper = string.sub(strAmount, -2, -1)
	local silver = string.sub(strAmount, -4, -3)
	local gold = string.sub(strAmount, -6, -5)
	local plat = string.sub(strAmount, -8, -7)

	local strResult = ""
	strResult = MailAutoText:AppendDenomination(strResult, MailAutoText:PrettyPrintDenomination(plat, "Platinum"))
	strResult = MailAutoText:AppendDenomination(strResult, MailAutoText:PrettyPrintDenomination(gold, "Gold"))
	strResult = MailAutoText:AppendDenomination(strResult, MailAutoText:PrettyPrintDenomination(silver, "Silver"))
	strResult = MailAutoText:AppendDenomination(strResult, MailAutoText:PrettyPrintDenomination(copper, "Copper"))

	return(strResult)
end

function MailAutoText:IsSendingCash()
	if M.luaComposeMail ~= nil then
		return M.luaComposeMail.wndCashSendBtn:IsChecked() and M.luaComposeMail.wndCashWindow:GetAmount() > 0
	else
		return false
	end	
end

function MailAutoText:IsRequestingCash()
	if M.luaComposeMail ~= nil then
		return M.luaComposeMail.wndCashCODBtn:IsChecked() and MailAutoText:HasAttachments() and M.luaComposeMail.wndCashWindow:GetAmount() > 0
	else
		return false
	end	
end

function MailAutoText:HasAttachments()
	return M.luaComposeMail ~= nil and M.luaComposeMail.arAttachments ~= nil and #M.luaComposeMail.arAttachments > 0
end

function MailAutoText:AppendDenomination(strFull, strAmount)
	local strResult = strFull

	-- If we're adding text to an existing string, insert a space
	if string.len(strResult) > 0 and string.len(strAmount) > 0 then
		strResult = strResult .. " "
	end

	-- Added current denom-string (if any) to the existing string
	if string.len(strAmount) > 0 then
		strResult = strResult .. strAmount
	end

	return strResult
end

function MailAutoText:PrettyPrintDenomination(strAmount, strDenomination)
	local strResult = ""
	if strAmount ~= nil and strAmount ~= "" and strAmount ~= "00" then
		if string.sub(strAmount, 1, 1) == "0" then
			-- Don't print "04 Silver", just "4 Silver"
			strResult = string.sub(strAmount, 2, 2) .. " " .. strDenomination
		else
			strResult = strAmount .. " " .. strDenomination
		end
	end
	return strResult
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
				log:debug("Generated subject identified")
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
	log:debug("Updating message")

	local strCredits = MailAutoText:GoldPrettyPrint(M.luaComposeMail.wndCashWindow:GetAmount())
	local bCreditsText = (MailAutoText:IsSendingCash() or MailAutoText:IsRequestingCash()) and strCredits ~= ""
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
		if MailAutoText:IsRequestingCash() == true then
			newBody = newBody .. Apollo.GetString("CRB_Request_COD") .. ": " .. strCredits .. "\n"
		end
		if MailAutoText:IsSendingCash() == true then
			newBody = newBody .. Apollo.GetString("CRB_Send_Money") .. ": " .. strCredits .. "\n"
		end
	end

	-- Append itemlist if sending items
	if bItemListText == true then
		newBody = newBody .. MailAutoText.strItemList
	end

	-- Update body
	M.luaComposeMail.wndMessageEntryText:SetText(newBody)
end


function MailAutoText:OnRecipientChanged(wndHandler, wndControl)
	log:debug("Recipient changed")

	local strEntered = M.luaComposeMail.wndNameEntry:GetText()
	local strPreviousEnter = MailAutoText.strPreviousEnter
	local strPreviousMatch = MailAutoText.strPreviousMatch
	
	log:debug("strEntered: '%s'", strEntered)
	log:debug("strPreviousEnter: '%s'", strPreviousEnter)
	log:debug("strPreviousMatch: '%s'", strPreviousMatch)	
	MailAutoText.wndHandler = wndHandler
	MailAutoText.wndControl = wndControl
	
	-- TODO: increase "backspace delete selection"
	
	-- Do not react if user is deleting chars from recipient field value
	if strPreviousEnter ~= "" -- Must have a previously entered value
	   --and string.len(strEntered)>=3 -- Current entered text must be at least 3 chars to ignore autocomplete (since min char name is 3)
	   and string.len(strEntered)<=string.len(strPreviousEnter) -- Current entered text must shorter than last entered
	   and string.find(string.lower(strPreviousEnter), string.lower(strEntered)) == 1 then -- Current entered text must be a starts-with match of last entered
		log:debug("Deleting chars, ignore")		
		MailAutoText.strPreviousEnter = strEntered
		MailAutoText.strPreviousMatch = strEntered
		return MailAutoText.hooks[M.luaComposeMail]["OnInfoChanged"](M.luaComposeMail, wndHandler, wndControl)
	end
	
	local strMatched = MailAutoText:GetNameMatch(strEntered)
	
	if strEntered ~= strMatched then
		log:debug("Updating partial input '%s' to matched input '%s'", strEntered, strMatched)
		M.luaComposeMail.wndNameEntry:SetText(strMatched)
		M.luaComposeMail.wndNameEntry:SetSel(string.len(strEntered), string.len(strMatched))
	end
	
	MailAutoText.strPreviousEnter = strEntered
	MailAutoText.strPreviousMatch = strMatched
	
	-- Pass update on to Mail for futher control
	return MailAutoText.hooks[M.luaComposeMail]["OnInfoChanged"](M.luaComposeMail, wndHandler, wndControl)
end

function MailAutoText:GetNameMatch(strEntered)
	-- Very ineffective matching algorithm. Optimize: lots of lower(), no reduction of possible match-sets per char entered etc.
	local len = string.len(strEntered)
	for _,strFullName in ipairs(MailAutoText.names) do
		local strPartialName = string.sub(strFullName, 1, len)
		if string.lower(strPartialName) == string.lower(strEntered) then
			log:debug("Input '%s' matches '%s'", strEntered, strFullName)
			return strFullName
		end
		log:debug("Input '%s' does not match '%s'", strEntered, strFullName) 
	end
	return strEntered
end