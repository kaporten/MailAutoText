
require "Window"
require "GameLib"
require "Apollo"

local MailAutoText = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("MailAutoText", false, {"Mail"}, "Gemini:Hook-1.0")
MailAutoText.ADDON_VERSION = {1, 4, 3}

local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("MailAutoText")

-- GeminiLoging, initialized during OnEnable
local log

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
	
		-- Server-side event fired when an attachment has been added to an open mail
	Apollo.RegisterEventHandler("MailAddAttachment", "ItemAttachmentAdded", self) -- Attachment added
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
	
	
	MailAutoText:RawHook(luaMail, "OnClickAttachment", MailAutoText.ItemAttachmentRemoved) -- Attachment removed (intentionally non-Post! PostHook breaks stuff here)
	MailAutoText:RawHook(luaMail, "OnCashAmountChanged", MailAutoText.OnCashAmountChanged) -- Cash amount changed
	MailAutoText:RawHook(luaMail, "OnMoneyCODCheck", MailAutoText.OnMoneyCODCheck) -- "Request" checked
	MailAutoText:RawHook(luaMail, "OnMoneyCODUncheck", MailAutoText.OnMoneyCODUncheck) -- "Request" unchecked
	MailAutoText:RawHook(luaMail, "OnMoneySendCheck", MailAutoText.OnMoneySendCheck) -- "Send" checked
	MailAutoText:RawHook(luaMail, "OnMoneySendUncheck", MailAutoText.OnMoneySendUncheck) -- "Send unchecked	
	MailAutoText:RawHook(luaMail, "OnClosed", MailAutoText.OnClosed) -- Mail is closed for whatever reason (cancelled/sent)
	
	log:debug("Compose Mail editing functions hooked")
end

--[[ 
	Hook functions.
	Allows the addon to react to changes in the mail GUI, such as 
	attachments added/removed or credits-area changes.
]]

function MailAutoText:OnCashAmountChanged()
	log:debug("Cash amount changed")
	MailAutoText:UpdateMessage() -- Trigger message subject/body update
	MailAutoText.hooks[M.luaComposeMail]["OnCashAmountChanged"](M.luaComposeMail)	
end

-- "Check" intercepts should be pre-hook so we add text before Mail knows about it
function MailAutoText:OnMoneyCODCheck(wndHandler, wndControl)
	log:debug("Request Money checked")
	
	-- When checking CashCOD, preemptively uncheck the CashSend button, so that our own logic correctly calcs message state
	M.luaComposeMail.wndCashSendBtn:SetCheck(false)

	MailAutoText:UpdateMessage() -- Trigger message subject/body update
	MailAutoText.hooks[M.luaComposeMail]["OnMoneyCODCheck"](M.luaComposeMail, wndHandler, wndControl)
end

-- "Uncheck" intercepts should be post-hook so we update text after Mail has taken care of the cleanup
function MailAutoText:OnMoneyCODUncheck(wndHandler, wndControl)
	log:debug("Request Money unchecked")
	MailAutoText.hooks[M.luaComposeMail]["OnMoneyCODUncheck"](M.luaComposeMail, wndHandler, wndControl)
	MailAutoText:UpdateMessage() -- Trigger message subject/body update
end

-- "Check" intercepts should be pre-hook so we add text before Mail knows about it
function MailAutoText:OnMoneySendCheck(wndHandler, wndControl)
	log:debug("Send Money checked")	
	
	-- When checking CashSend, preemptively uncheck the CashCOD button, so that our own logic correctly calcs message state
	M.luaComposeMail.wndCashCODBtn:SetCheck(false)
	
	MailAutoText:UpdateMessage() -- Trigger message subject/body update
	MailAutoText.hooks[M.luaComposeMail]["OnMoneySendCheck"](M.luaComposeMail, wndHandler, wndControl)
end

-- "Uncheck" intercepts should be post-hook so we update text after Mail has taken care of the cleanup
function MailAutoText:OnMoneySendUncheck(wndHandler, wndControl)
	log:debug("Send Money unchecked")
	MailAutoText.hooks[M.luaComposeMail]["OnMoneySendUncheck"](M.luaComposeMail, wndHandler, wndControl)
	MailAutoText:UpdateMessage() -- Trigger message subject/body update
end

function MailAutoText:OnClosed(wndHandler)
	log:debug("Compose Mail window closed")
	MailAutoText.hooks[M.luaComposeMail]["OnClosed"](M.luaComposeMail, wndHandler)
	
	-- When mail is closed, clear the previously generated message body
	MailAutoText.strItemList = ""
end


-- Called when an attachment is added. Triggered by the "MailAddAttachment" server event.
-- Parameter attachmentId is not an item-id, but an id that is only usable in
-- the context of this particular message.
function MailAutoText:ItemAttachmentAdded(nValue)
	log:debug("'MailAddAttachment' event fired for ID %d", nValue)

	-- Event fired at times we're not actually composing mail, 
	-- such as right-clicking to equip items
	if M.luaComposeMail == nil then
		log:debug("'MailAddAttachment' ignored, not currently composing mail")
		return
	end

	-- Generate new item-string and trigger message update
	MailAutoText.strItemList = MailAutoText:GenerateItemListString(nValue, nil)
	MailAutoText:UpdateMessage()
end

-- Called when an attachment is removed. Triggered by the "Mail" Addons GUI interactions.
-- Extracted parameter "iAttach" is the index of the attachment being removed.
function MailAutoText:ItemAttachmentRemoved(wndHandler, wndControl)
	MailAutoText.hooks[M.luaComposeMail]["OnClickAttachment"](M.luaComposeMail, wndHandler, wndControl)
		
	-- Function is called twice by Mail addon - these filters (copied from Mail.lua) filters out one of them
	if wndHandler ~= wndControl then
		return
	end
	local iAttach = wndHandler:GetData()
	if iAttach == nil then
		return
	end
	
	log:debug("Attachment index removed: %d", iAttach)
		
	-- Calculate new item-string and trigger body-update
	MailAutoText.strItemList = MailAutoText:GenerateItemListString()
	MailAutoText:UpdateMessage()
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
		return M.luaComposeMail.wndCashSendBtn:IsChecked()
	else
		return false
	end	
end

function MailAutoText:IsRequestingCash()
	if M.luaComposeMail ~= nil then
		return M.luaComposeMail.wndCashCODBtn:IsChecked() and MailAutoText:HasAttachments()
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
