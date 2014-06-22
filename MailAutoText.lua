
require "Apollo"
require "Window"
require "GameLib"
require "GuildLib"
require "FriendshipLib"

local MailAutoText = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("MailAutoText", false, {"Mail", "GeminiConsole"}, "Gemini:Hook-1.0")
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

	-- Prepare empty address book	
	self.addressBook = {}
	self.addressBook.friends = {}
	self.addressBook.guild = {}
	self.addressBook.circles = {}

	-- Register for guild/circle changes, so address book can be updated
	Apollo.RegisterEventHandler("GuildRoster", "OnGuildRoster", self)
	Apollo.RegisterEventHandler("GuildMemberChange", "OnGuildMemberChange", self)
	
	-- Trigger guild address book population
	for _,guild in ipairs(GuildLib.GetGuilds()) do
		guild:RequestMembers()
	end
	
	log:debug("Address book initialized")
	
	-- Used during name autocompletion to detect when you're deleting stuff from the To-field.
	self.strPreviouslyEntered = ""

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
	
	-- HACK: Request friend list per mail opened. Figure out which events to react (a la guild) to instead	
	MailAutoText:AddFriends(MailAutoText.addressBook.friends)	
	log:debug("Friends address book updated")
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
	MailAutoText.strPreviouslyEntered = ""
	
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

-- Called when the text in the "To" recipient field is altered. Handles name auto-completion.
function MailAutoText:OnRecipientChanged(wndHandler, wndControl)
	local strEntered = M.luaComposeMail.wndNameEntry:GetText()
	local strPreviouslyEntered = MailAutoText.strPreviouslyEntered
	
	log:debug("Recipient changed. strEntered='%s', strPreviouslyEntered=", strEntered, strPreviouslyEntered)
		
	-- Do not react if user is deleting chars from recipient field value
	if strPreviouslyEntered ~= "" -- Must have a previously entered value
			and string.len(strEntered)<=string.len(strPreviouslyEntered) -- Current entered text must shorter than last entered
			and string.find(string.lower(strPreviouslyEntered), string.lower(strEntered)) == 1 then -- Current entered text must be a starts-with match of last entered
   
		-- Update previously entered value and pass update along to Mail GUI
		log:debug("Deleting characters, skipping auto-completion")
		MailAutoText.strPreviouslyEntered = strEntered
		return MailAutoText.hooks[M.luaComposeMail]["OnInfoChanged"](M.luaComposeMail, wndHandler, wndControl)
	end
	
	-- Check if current value has an addressBook entry in any address book. Priority is Friend > Guild > Circle.
	local strMatched
	strMatched = strMatched or MailAutoText:GetNameMatch(MailAutoText.addressBook.friends, strEntered)
	strMatched = strMatched or MailAutoText:GetNameMatch(MailAutoText.addressBook.guild, strEntered)
	for _,circle in ipairs(MailAutoText.addressBook.circles) do
		strMatched = strMatched or MailAutoText:GetNameMatch(circle, strEntered)
	end
		
	if strMatched ~= nil then
		-- Match found, set To-field text to the full name, and select the auto-completed part
		log:debug("Updating entered input '%s' to matched input '%s'", strEntered, strMatched)
		M.luaComposeMail.wndNameEntry:SetText(strMatched)
		M.luaComposeMail.wndNameEntry:SetSel(string.len(strEntered), string.len(strMatched))
	end
	
	-- Update previously entered value and pass update along to Mail GUI
	MailAutoText.strPreviouslyEntered = strEntered
	return MailAutoText.hooks[M.luaComposeMail]["OnInfoChanged"](M.luaComposeMail, wndHandler, wndControl)
end


--[[
	ADDRESS BOOK CODE BELOW
	-----------------------
	
	The address book is series of nested tables resembling a tree. The name "Brofessional"
	would be added to the address book tree like this (notice all lower case keys):
	
		addressBook["b"]["r"]["o"]["f"]["e"]["s"]["s"]["i"]["o"]["n"]["a"]["l"]
	
	Each node in this tree also contains a match property. So:
	
		addressBook["b"].match = "Brofessional"
		addressBook["b"]["r"]["o"]["f"].match = "Brofessional"

	The match property always contains the first (alphabetically) complete matched
	name for this node. F.ex. adding the names "Bro" and "Brock" produce these results:

		addressBook["b"].match = "Bro"
		addressBook["b"]["r"]["o"].match = "Bro"
		addressBook["b"]["r"]["o"]["c"].match = "Brock"
		addressBook["b"]["r"]["o"]["f"].match = "Brofessional"		
	
	
	This structure should provide these desired speed properties. Obviously I have, like, 
	at least 20 pages of super-math to prove this, I just choose to keep them secret :P
	
		* Searching for a match: Very fast
		* Adding a name: Fast
		* Removing a name: Slow (total rebuild of the addressBook)
		
	The user should only notice the search-time, since adding/removing names is done in
	the background during addon load and guild/friend list update events.
]]

function MailAutoText:AddName(book, strName)
	log:debug(string.format("Adding '%s' to the address book", strName))
	
	-- TODO: Add "skip myself" check
	
	-- First hit, set index to 1 and current node to addressBook tree root
	MailAutoText:_addName(book, strName, 1, book)	
end

function MailAutoText:_addName(book, strName, i, node)
	-- First hit, set index to 1 and current node to addressBook tree root
	i = i or 1
	node = node or book
	
	-- Char at index i in the full name, lowered
	local char = strName:sub(i, i):lower()
	
	-- Check if a child node exist for this char
	local childNode = node[char]
	
	if childNode == nil then
		-- No child node found, create one and set match for this node to input name
		childNode = {match = strName}
		node[char] = childNode		
	else		
		-- Node already exist. Update matched name if the current name is alphabetically "lower".
		if strName < childNode.match then
			childNode.match = strName
		end
	end
	
	-- Proceed with next char in the input name
	if i == strName:len() then 		
		return -- recursion base
	end
	
	-- Tail-call recursion, avoids stack buildup as addressBook is being constructed.
	MailAutoText:_addName(book, strName, i+1, childNode)
end

-- Gets the best name match from the address book dictionary
function MailAutoText:GetNameMatch(book, part)
	local lower = part:lower()
	local node = book
	
	-- Find the deepest node in the tree, matching the entered text char-by-char
	for i=1, #lower do
		local c = lower:sub(i,i)		
		local childNode = node[c]
		if childNode == nil then
			-- Text entered does not match any addressbook name, return nil
			return nil
		else
			-- Char matches a node, go deeper
			node = childNode
		end		
	end
	
	local result
	if node == nil then 
		result = part 
	else
		result = node.match or part
	end	
	
	log:debug("Matched input '%s' to '%s'", part, result)
	return result
end


function MailAutoText:OnGuildMemberChange(guild)
	log:debug("Guild or circle changed, requesting roster")
	guild:RequestMembers()
end

function MailAutoText:OnGuildRoster(guild, roster)
	-- Fresh address book, populate with guild/circle data
	local book = {}
	for _,member in ipairs(roster) do
		MailAutoText:AddName(book, member.strName)
	end

	-- Replace current book
	if guild:GetType() == GuildLib.GuildType_Guild then
		log:info("Updating address book for guild '%s'", guild:GetName())
		self.addressBook.guild = book
	end
	if guild:GetType() == GuildLib.GuildType_Circle then
		log:info("Updating address book for circle '%s'", guild:GetName())
		self.addressBook.circles[guild:GetName()] = book
	end
end

function MailAutoText:AddFriends(book)
	log:info("Adding friends to address book")	
	local friends = FriendshipLib:GetList()
	for _,friend in ipairs(friends) do
		-- Same-realm friends only... can't send mail to other realms can we?
		if friend.bFriend == true and friend.strRealmName == GameLib.GetRealmName() then
			MailAutoText:AddName(book, friend.strCharacterName)
		end
	end
end
