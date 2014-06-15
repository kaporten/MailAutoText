
require "Window"
require "GameLib"
require "Apollo"

local MailAutoText = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("MailAutoText", false, {"Mail"}, "Gemini:Hook-1.0")
MailAutoText.ADDON_VERSION = {1, 1, 0}

function MailAutoText:OnEnable()
    -- TODO: Check if "Mail" is installed (or have been replaced)
    Apollo.RegisterEventHandler("MailAddAttachment", "ItemAttachmentAdded", self)

    -- Hooking can only be done once the "luaMailCompose" object is initialized inside Mail
    MailAutoText:PostHook(Apollo.GetAddon("Mail"), "ComposeMail", MailAutoText.HookMailModificationFunctions)
end

function MailAutoText:HookMailModificationFunctions()	
    -- Now that Mail.luaComposeMail exist, hook into editing functions
	local luaMail = Apollo.GetAddon("Mail").luaComposeMail
    MailAutoText:Hook(luaMail, "OnClickAttachment", MailAutoText.ItemAttachmentRemoved)
    MailAutoText:Hook(luaMail, "OnCashAmountChanged", MailAutoText.CashAmountChanged)
    MailAutoText:Hook(luaMail, "OnMoneyCODCheck", MailAutoText.MoneyCODOn)
    MailAutoText:Hook(luaMail, "OnMoneyCODUncheck", MailAutoText.MoneyCODOff)
    MailAutoText:Hook(luaMail, "OnMoneySendCheck", MailAutoText.MoneySendOn)
    MailAutoText:Hook(luaMail, "OnMoneySendUncheck", MailAutoText.MoneySendOff)
end

function MailAutoText:ItemAttachmentAdded(nValue)
    -- Calculate new item-string and trigger body-update
    MailAutoText.strItemList = MailAutoText:GenerateItemListString(nValue)
    MailAutoText:UpdateMessage()
end

function MailAutoText:ItemAttachmentRemoved(wndHandler, wndControl)
    -- Function is called twice by Mail addon - these filters (copied from Mail.lua) filters out one of them
    if wndHandler ~= wndControl then
        return
    end
    local iAttach = wndHandler:GetData()
    if iAttach == nil then
        return
    end

    -- Calculate new item-string and trigger body-update
    MailAutoText.strItemList = MailAutoText:GenerateItemListString(nil, iAttach)
    MailAutoText:UpdateMessage()
end

function MailAutoText:GenerateItemListString(addedAttachmentId, removedAttachmentId)

    -- Deep-copy "arAttachments" (except removed one) into local array
    local allAttachmentIds = {}
    for k,v in ipairs(Apollo.GetAddon("Mail").luaComposeMail.arAttachments) do
		if v ~= removedAttachmentId then
			allAttachmentIds[#allAttachmentIds] = v
		end
    end

    -- Check if the newly-added item (if any) already exist in array
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
    local bCreditsText = MailAutoText.GetCreditAcount() ~= nil
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
        if MailAutoText.CreditsCOD == true then
            newBody = newBody .. "Cost: " .. MailAutoText.GetCreditAcount() .. "\n"
        end
        if MailAutoText.CreditsSend == true then
            newBody = newBody .. "Credits: " .. MailAutoText.GetCreditAcount() .. "\n"
        end
    end

    if bItemListText == true then
        newBody = newBody .. MailAutoText.strItemList
    end

 Apollo.GetAddon("Mail").luaComposeMail.wndMessageEntryText:SetText(newBody)
end

function MailAutoText:CashAmountChanged()
 --MailAutoText:GoldPrettyPrint(Apollo.GetAddon("Mail").luaComposeMail.wndCashWindow:GetAmount())
    MailAutoText:UpdateMessage()
end

function MailAutoText:GetCreditAcount()
    return MailAutoText:GoldPrettyPrint(Apollo.GetAddon("Mail").luaComposeMail.wndCashWindow:GetAmount())
end

function MailAutoText:MoneyCODOn()
    MailAutoText.CreditsSend = false
    MailAutoText.CreditsCOD = true
    MailAutoText:UpdateMessage()
end

function MailAutoText:MoneyCODOff()
    MailAutoText.CreditsSend = false
    MailAutoText.CreditsCOD = false
    MailAutoText:UpdateMessage()
end

function MailAutoText:MoneySendOn()
    MailAutoText.CreditsSend = true
    MailAutoText.CreditsCOD = false
    MailAutoText:UpdateMessage()
end

function MailAutoText:MoneySendOff()
    MailAutoText.CreditsSend = false
    MailAutoText.CreditsSend = false
    MailAutoText:UpdateMessage()
end

function MailAutoText:GoldPrettyPrint(amount)
    if amount == 0 then
        return nil
    end

    local amount_string = tostring(amount)
    local return_string = ""
    local copper = string.sub(amount_string, -2, -1)
    local silver = string.sub(amount_string, -4, -3)
    local gold = string.sub(amount_string, -6, -5)
    local plat = string.sub(amount_string, -8, -7)

    local strResult = ""
    strResult = MailAutoText:AppendDenomination(strResult, MailAutoText:PrettyPrintDenomination(plat, "Platinum"))
    strResult = MailAutoText:AppendDenomination(strResult, MailAutoText:PrettyPrintDenomination(gold, "Gold"))
    strResult = MailAutoText:AppendDenomination(strResult, MailAutoText:PrettyPrintDenomination(silver, "Silver"))
    strResult = MailAutoText:AppendDenomination(strResult, MailAutoText:PrettyPrintDenomination(copper, "Copper"))

    return(strResult)
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
