-- Address book test lua script
-- NOT to be part of the final addon, just a standalone lua test script

--[[
	The address book is series of nested tables resembling a tree. The name "Brofessional"
	would be added to the address book tree like this (notice all lower case keys):
	
		addressBook["b"]["r"]["o"]["f"]["e"]["s"]["s"]["i"]["o"]["n"]["a"]["l"]
	
	Each node in this tree also contains a matchedName property. So:
	
		addressBook["b"].matchedName = "Brofessional"
		addressBook["b"]["r"]["o"]["f"].matchedName = "Brofessional"

	The matchedName property always contains the first (alphabetically) complete matched
	name for this node. F.ex. adding the names "Bro" and "Brock" produce these results:

		addressBook["b"].matchedName = "Bro"
		addressBook["b"]["r"]["o"].matchedName = "Bro"
		addressBook["b"]["r"]["o"]["c"].matchedName = "Brock"
		addressBook["b"]["r"]["o"]["f"].matchedName = "Brofessional"		
	
	
	This structure should provide these desired speed properties. Obviously I have, like, 
	at least 20 pages of super-math to prove this, I just choose to keep them secret :P
	
		* Searching for a match: Very fast
		* Adding a name: Fast
		* Removing a name: Slow (total rebuild of the addressBook)
		
	The user should only notice the search-time, since adding/removing names is done in
	the background during addon load and guild/friend list update events.
]]
	
	
addressBook = {}

-- Static list of test names to add to book. Unsorted. In case of doubles, random entry "wins".
names = {"Pilfinger", "Zica", "Racki", "Dalwhinnie", "Sayiem", "PilFinger", "pILfinger", "Pil", "P", "pil"}

function GetMatch(part)
	local lower = part:lower()
	local page = addressBook
	
	for i=1, #lower do
		local c = lower:sub(i,i)		
		local childPage = page[c]
		if childPage == nil then
			break
		else
			page = childPage
		end		
	end
	
	if page == nil then 
		return part 
	else
		return page.matchedName or part
	end	
end

function AddName(strName, i, parentPage)
	-- First hit, set index to 1 and parentPage to addressBook tree root
	i = i or 1
	parentPage = parentPage or addressBook
	
	-- Char at index i in the full name, lowered
	local char = strName:sub(i, i):lower()
	
	print(string.format("strName=%s, i=%d, char=%s", strName, i, char))
	
	-- Check if a child tree node ("page") exist for this char
	local childPage = parentPage[char]
	
	if childPage == nil then
		-- No child node found, create one and set matchedName for this node to input name
		childPage = {matchedName = strName}
		parentPage[char] = childPage		
	else		
		-- Node already exist. Update matched name if the current name is alphabetically "lower".
		if strName < childPage.matchedName then
			childPage.matchedName = strName
		end
	end
	
	-- Proceed with next char in the input name
	if i == strName:len() then 		
		return -- recursion base
	end
	
	-- Tail-call recursion, avoids stack buildup as addressBook is being constructed.
	AddName(strName, i+1, childPage)
end

for _,n in pairs(names) do
	AddName(n)
end

print("Manual lookup   : " .. addressBook["p"]["i"]["l"].matchedName) -- Pil
print("Function lookup : " .. GetMatch("pil")) -- Pil
print("Function lookup : " .. GetMatch("P")) -- Pil
print("Function lookup : " .. GetMatch("Pilf")) -- PilFinger
print("Function lookup : " .. GetMatch("e")) -- e

