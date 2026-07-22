
local addonName, addonTable = ...; 
local zc = addonTable.zc;

KM_NULL_STATE	= 0;
KM_PREQUERY		= 1;
KM_INQUERY		= 2;
KM_POSTQUERY	= 3;
KM_ANALYZING	= 4;
KM_SETTINGSORT	= 5;

local AUCTION_CLASS_WEAPON = 1;
local AUCTION_CLASS_ARMOR  = 2;

local gAllScans = {};

local BIGNUM = 999999999999;

local ATR_SORTBY_NAME_ASC = 0;
local ATR_SORTBY_NAME_DES = 1;
local ATR_SORTBY_PRICE_ASC = 2;
local ATR_SORTBY_PRICE_DES = 3;

-----------------------------------------

AtrScan = {};
AtrScan.__index = AtrScan;

-----------------------------------------

AtrSearch = {};
AtrSearch.__index = AtrSearch;

-----------------------------------------

function Atr_NewSearch (itemName, exact, rescanThreshold, callback)

	local srch = {};
	setmetatable (srch, AtrSearch);
	srch:Init (itemName, exact, rescanThreshold, callback);

	return srch;
end

-----------------------------------------

function AtrSearch:Init (searchText, exact, rescanThreshold, callback)

	if (searchText == nil) then
		searchText = "";
	end

	self.origSearchText = searchText;
	
	if (not exact) then
		if (zc.StringStartsWith (searchText, "\"") and zc.StringEndsWith (searchText, "\"")) then
			searchText = string.sub (searchText, 2, searchText:len()-1);
			exact = true;
		end
	end		

	self.searchText			= searchText;
	self.exact				= exact;
	self.processing_state	= KM_NULL_STATE
	self.current_page		= -1
	self.items				= {};
	self.query				= Atr_NewQuery();
	self.sortedScans		= nil;
	self.sortHow			= ATR_SORTBY_PRICE_ASC;
	self.callback			= callback;
	
	if (exact) then	

		if (rescanThreshold and rescanThreshold > 0) then
			local scan = Atr_FindScan (searchText);
			if (scan and (time() - scan.whenScanned) <= rescanThreshold) then
				self.items[searchText] = scan;
			end
		end
		
		if (not self.items[searchText]) then		
			self.items[searchText] = Atr_FindScanAndInit (searchText);
		end
		
	end
	
end

-----------------------------------------

function Atr_FindScanAndInit (itemName)

	return Atr_FindScan (itemName, true);
end

-----------------------------------------

function Atr_FindScan (itemName, init)

	if (itemName == nil or itemName == "") then
		itemName = "nil";
	end

	local itemNameLC = string.lower (itemName);

	if (gAllScans[itemNameLC] == nil) then

		local scn = {};
		setmetatable (scn, AtrScan);
		scn:Init (itemName);

		gAllScans[itemNameLC] = scn;
	elseif (init) then
		gAllScans[itemNameLC]:Init (itemName);
	end
	
	return gAllScans[itemNameLC];
end

-----------------------------------------

function Atr_ClearScanCache ()

--	zc.msg_red ("Clearing Scan Cache");

	for a,v in pairs (gAllScans) do
		if (a ~= "nil") then
			gAllScans[a] = nil;
		end
	end

end

-----------------------------------------

function AtrScan:Init (itemName)
	self.itemName			= itemName;
	self.itemLink			= nil;
	self.texture            = nil;
	self.scanData			= {};
	self.sortedData			= {};
	self.whenScanned		= 0;
	self.lowprices			= {BIGNUM, BIGNUM, BIGNUM};
	self.absoluteBest		= nil;
	self.itemClass			= 0;
	self.itemSubclass		= 0;
	self.yourBestPrice		= nil;
	self.yourWorstPrice		= nil;
	self.numYourSingletons	= 0;
	self.itemTextColor 		= { 1.0, 1.0, 1.0 };
	self.searchText			= nil;
	
	self:UpdateItemLink (Atr_GetItemLink (itemName));
end

-----------------------------------------

function AtrScan:UpdateItemLink (itemLink)

	self.itemLink = itemLink;
	
	if (itemLink) then
	
		Atr_AddToItemLinkCache (self.itemName, itemLink);

		local _, _, quality, _, _, sType, sSubType = GetItemInfo(itemLink);

		self.itemQuality	= quality;
		self.itemClass		= Atr_ItemType2AuctionClass (sType);
		self.itemSubclass	= Atr_SubType2AuctionSubclass (self.itemClass, sSubType);	

		self.itemTextColor = { 1.0, 1.0, 1.0 };

		if (quality == 0)	then	self.itemTextColor = { 0.6, 0.6, 0.6 };	end
		if (quality == 2)	then	self.itemTextColor = { 0.2, 1.0, 0.0 };	end
		if (quality == 3)	then	self.itemTextColor = { 0.0, 0.5, 1.0 };	end
		if (quality == 4)	then	self.itemTextColor = { 0.7, 0.3, 1.0 };	end
	end

end


-----------------------------------------

function AtrSearch:NumScans()

	if (self.sortedScans) then
		return #self.sortedScans;
	end

	local count = 0;
	for name,scn in pairs (self.items) do
		count = count + 1;
	end

	return count;
end

-----------------------------------------

function AtrSearch:NumSortedScans()

	if (self.sortedScans) then
		return #self.sortedScans;
	end

	return 0;
end

-----------------------------------------

function AtrSearch:GetFirstScan()

	if (self.sortedScans) then
		return self.sortedScans[1];
	end

	for name,scn in pairs (self.items) do
		return scn;
	end
	
	return nil;

end


-----------------------------------------

function AtrSearch:Start ()

	if (self.searchText == "") then
		return;
	end
	
	if (Atr_IsCompoundSearch (self.searchText)) then
			
		local _, itemClass = Atr_ParseCompoundSearch (self.searchText);
	
		if (itemClass == 0) then
			Atr_Error_Display (ZT("The first part of this compound\n\nsearch is not a valid category."));
			return;
		end

		self.sortHow = ATR_SORTBY_PRICE_DES;

	end
	
	self.processing_state = KM_SETTINGSORT;
	
	SortAuctionClearSort ("list");

	BrowseName:SetText (self.searchText);		-- not necessary but nice when user switches to Browse tab

	self.current_page		= 0;
	self.processing_state	= KM_PREQUERY;

	self:Continue();
	
end

-----------------------------------------

function AtrSearch:Abort ()

	if (self.processing_state == KM_NULL_STATE) then
		return;
	end

	self.processing_state = KM_NULL_STATE;
	self:Init();
end

-----------------------------------------

function AtrSearch:CheckForDuplicatePage ()

	local isDup = self.query:CheckForDuplicatePage(self.current_page);

	if (isDup) then
--		zc.msg_red ("DUPLICATE PAGE FOUND: ", "  current_page: ", self.current_page, "  numDupPages: ", self.query.numDupPages);

		self.current_page	= self.current_page - 1;   -- requery the page
		
		self.processing_state = KM_PREQUERY;
	end
		
	return isDup;
end


-----------------------------------------

function AtrSearch:AnalyzeResultsPage()

	self.processing_state = KM_ANALYZING;

	if (self.query.numDupPages > 10) then 	 -- hopefully this will never happen but need check to avoid looping
		return true;						 -- done
	end


	local numBatchAuctions, totalAuctions = GetNumAuctionItems("list");

	if (self.current_page == 1 and totalAuctions > 3000) then -- give Blizz servers a break
		Atr_Error_Display (ZT("Too many results\n\nPlease narrow your search"));
		return true;  -- done
	end

	if (totalAuctions >= 50) then
		Atr_SetMessage (string.format (ZT("Scanning auctions: page %d"), self.current_page));
	end

	-- analyze

	local numNilOwners = 0;

	if (numBatchAuctions > 0) then

		local x;

		for x = 1, numBatchAuctions do

			local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner = GetAuctionItemInfo("list", x);

			if (owner == nil) then
				numNilOwners = numNilOwners + 1;
			end
			
			local exactMatch = zc.StringSame (name, self.searchText);

			if (exactMatch or not self.exact) then

				if (self.items[name] == nil) then
					self.items[name] = Atr_FindScanAndInit (name);
                    self.items[name].texture = texture
				end
                if self.items[name].texture and texture ~= self.items[name].texture then
                    name = name .. " "
                    if (self.items[name] == nil) then
                        self.items[name] = Atr_FindScanAndInit (name);
                        self.items[name].texture = texture
                    end
                end
                
				local curpage = (tonumber(self.current_page)-1);

				local scn = self.items[name];

				scn:AddScanItem (name, count, buyoutPrice, owner, 1, curpage);
				
				if (scn.itemLink == nil or self.itemClass == nil) then
					scn:UpdateItemLink (GetAuctionItemLink("list", x));
				end

				if (self.callback) then
					self.callback (x, numBatchAuctions, count, buyoutPrice, owner);
				end
				
			end
		end
	end
	
	local done = (numBatchAuctions < 50);

	if (not done) then
		self.processing_state = KM_PREQUERY;
	end
	
	return done;
end

-----------------------------------------

function AtrScan:AddScanItem (name, stackSize, buyoutPrice, owner, numAuctions, curpage)

	local sd = {};
	local i;

	if (numAuctions == nil) then
		numAuctions = 1;
	end

	for i = 1, numAuctions do
		sd["stackSize"]		= stackSize;
		sd["buyoutPrice"]	= buyoutPrice;
		sd["owner"]			= owner;
		sd["pagenum"]		= curpage;

		tinsert (self.scanData, sd);
		
		if (buyoutPrice) then
			local itemPrice = math.floor (buyoutPrice / stackSize);

			Atr_AddToLowPrices (self.lowprices, itemPrice);
		end
	end

end


-----------------------------------------

function AtrScan:AddSDXToScan (price, owner, volume)	-- helper function for AddExternalDataToScan

	local sd = {};

	if (price and price > 0) then
		sd["stackSize"]		= 1;
		sd["buyoutPrice"]	= price;
		sd["owner"]			= owner;

		if (volume) then
			sd["volume"] = volume;
		end

		tinsert (self.scanData, sd);
	end
	
end

-----------------------------------------

function AtrScan:AddExternalDataToScan ()

	if (self.itemLink == nil) then
		return;
	end

	-- Wowecon

	if (Wowecon and Wowecon.API) then
	
		local priceG, volG = Wowecon.API.GetAuctionPrice_ByLink (self.itemLink, Wowecon.API.GLOBAL_PRICE)
		local priceS, volS = Wowecon.API.GetAuctionPrice_ByLink (self.itemLink, Wowecon.API.SERVER_PRICE)

		self:AddSDXToScan (priceG, "__wowEconG", volG);
		self:AddSDXToScan (priceS, "__wowEconS", volS);
		
	end
	
	-- GoingPrice Wowhead
	
	local id = zc.ItemIDfromLink (self.itemLink);
	
	id = tonumber(id);

	if (GoingPrice_Wowhead_Data and GoingPrice_Wowhead_Data[id] and GoingPrice_Wowhead_SV._index) then
		local index = GoingPrice_Wowhead_SV._index["Buyout price"];

		if (index ~= nil) then
			local price = GoingPrice_Wowhead_Data[id][index];
		
			self:AddSDXToScan (price, "__wowHead");
		end
	end

	-- GoingPrice Allakhazam
	
	if (GoingPrice_Allakhazam_Data and GoingPrice_Allakhazam_Data[id] and GoingPrice_Allakhazam_SV._index) then
		local index = GoingPrice_Allakhazam_SV._index["Median"];

		if (index ~= nil) then
			local price = GoingPrice_Allakhazam_Data[id][index];
		
			self:AddSDXToScan (price, "__allakhazam");
		end
	end

	-- most recent historical price
	
	local price = Atr_Process_Historydata();
	if (price ~= nil) then
		self:AddSDXToScan (price, "__atrLast");
	end

end

-----------------------------------------

function AtrScan:SubtractScanItem (name, stackSize, buyoutPrice)

	local sd;
	local i;

	for i,sd in ipairs (self.scanData) do
		
		if (sd.stackSize == stackSize and sd.buyoutPrice == buyoutPrice) then
			
			tremove (self.scanData, i);
			return;
		end
	end

end

-----------------------------------------

function Atr_IsCompoundSearch (searchString)
	
	return zc.StringContains (searchString, ">") or zc.StringContains (searchString, "/");
end

-----------------------------------------

function Atr_ParseCompoundSearch (searchString)

	local delim = "/";

	if (zc.StringContains (searchString, ">")) then
		delim = ">";
	end

	local tbl	= { strsplit (delim, searchString) };
	
	local queryString	= "";
	local itemClass		= 0;
	local itemSubclass	= 0;
	local minLevel		= nil;
	local maxLevel		= nil;
	local prevWasItemClass;
	local n;
	
	for n = 1,#tbl do
		local s = tbl[n];

		local handled = false;

		if (not handled and tonumber(s)) then
			if (minLevel == nil) then
				minLevel = tonumber(s);
			elseif (maxLevel == nil) then
				maxLevel = tonumber(s);
			end
			
			handled = true;
			prevWasItemClass = false;
		end
		
		if (not handled and prevWasItemClass and itemSubclass == 0) then
			itemSubclass = Atr_SubType2AuctionSubclass (itemClass, s);
			if (itemSubclass > 0) then
				handled = true;
				prevWasItemClass = false;
			end
		end
		
		if (not handled and itemClass == 0) then

			itemClass = Atr_ItemType2AuctionClass (s);

			if (itemClass > 0) then
				prevWasItemClass = true;
				handled = true;
			end
		end
		
		if (not handled) then
			queryString = s;
			handled = true;
		end
	end	

	return queryString, itemClass, itemSubclass, minLevel, maxLevel;
end

-----------------------------------------

function AtrSearch:Continue()

	if (CanSendAuctionQuery()) then

		self.processing_state = KM_IN_QUERY;

		local queryString = self.searchText;

--	zc.md (queryString.."  page:"..self.current_page);
		
		local itemClass		= 0;
		local itemSubclass	= 0;
		local minLevel		= nil;
		local maxLevel		= nil;
		
		if (self.exact) then
			local scn = self:GetFirstScan();
			itemClass		= scn.itemClass;
			itemSubclass	= scn.itemSubclass;
		end

		if (Atr_IsCompoundSearch(queryString)) then
		
			queryString, itemClass, itemSubclass, minLevel, maxLevel = Atr_ParseCompoundSearch (queryString);
		
		end

		queryString = zc.UTF8_Truncate (queryString,63);	-- attempting to reduce number of disconnects

		QueryAuctionItems (queryString, minLevel, maxLevel, nil, itemClass, itemSubclass, self.current_page, nil, nil);

		self.query_sent_when	= gAtr_ptime;
		self.processing_state	= KM_POSTQUERY;
		self.current_page		= self.current_page + 1;
	end

end

-----------------------------------------

local gSortScansBy;

-----------------------------------------

local function Atr_SortScans (x, y)

	if (gSortScansBy == ATR_SORTBY_NAME_ASC) then		return string.lower (x.itemName) < string.lower (y.itemName);	end
	if (gSortScansBy == ATR_SORTBY_NAME_DES) then		return string.lower (x.itemName) > string.lower (y.itemName);	end

	local xprice = 0;
	local yprice = 0;
	
	if (x.absoluteBest) then	xprice = zc.round(x.absoluteBest.buyoutPrice/x.absoluteBest.stackSize);		end;
	if (y.absoluteBest) then	yprice = zc.round(y.absoluteBest.buyoutPrice/y.absoluteBest.stackSize);		end;
	
	if (gSortScansBy == ATR_SORTBY_PRICE_ASC) then		return xprice < yprice;		end
	if (gSortScansBy == ATR_SORTBY_PRICE_DES) then		return xprice > yprice;		end

end

-----------------------------------------

function AtrSearch:Finish()

	local finishTime = time();
	
	self.processing_state	= KM_NULL_STATE;
	self.current_page		= -1;
	self.query_sent_when	= nil;
	
	self.sortedScans = nil;
	
	local wasExactSearch = (self:NumScans() == 1);		-- search returned only 1 item
	
	local x = 1;
	self.sortedScans = {};
	
	for name,scn in pairs (self.items) do
	
		self.sortedScans[x] = scn;
		x = x + 1;
		
		scn.whenScanned		= finishTime;
		scn.searchText		= self.searchText;

		scn:CondenseAndSort ();

		-- update the fullscan DB
		
		local newprice = Atr_CalcNewDBprice (scn.itemName, scn.lowprices);
		
		if (newprice > 0) then
			if (scn.itemQuality + 1 >= AUCTIONATOR_SCAN_MINLEVEL) then
				gAtr_ScanDB[scn.itemName] = newprice;
			end
		end
	end
	
	Atr_ClearBrowseListings();
	
	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);
	
end

-----------------------------------------

function AtrSearch:ClickPriceCol()

	if (self.sortHow == ATR_SORTBY_PRICE_ASC) then
		self.sortHow = ATR_SORTBY_PRICE_DES;
	else
		self.sortHow = ATR_SORTBY_PRICE_ASC;
	end

	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);

end

-----------------------------------------

function AtrSearch:ClickNameCol()

	if (self.sortHow == ATR_SORTBY_NAME_ASC) then
		self.sortHow = ATR_SORTBY_NAME_DES;
	else
		self.sortHow = ATR_SORTBY_NAME_ASC;
	end

	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);
end

-----------------------------------------

function AtrSearch:UpdateArrows()

	Atr_Col1_Heading_ButtonArrow:Hide();
	Atr_Col3_Heading_ButtonArrow:Hide();
	
	if (self.sortHow == ATR_SORTBY_PRICE_ASC) then
		Atr_Col1_Heading_ButtonArrow:Show();
		Atr_Col1_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 0, 1.0);
	elseif (self.sortHow == ATR_SORTBY_PRICE_DES) then
		Atr_Col1_Heading_ButtonArrow:Show();
		Atr_Col1_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 1.0, 0);
	elseif (self.sortHow == ATR_SORTBY_NAME_ASC) then
		Atr_Col3_Heading_ButtonArrow:Show();
		Atr_Col3_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 0, 1.0);
	elseif (self.sortHow == ATR_SORTBY_NAME_DES) then
		Atr_Col3_Heading_ButtonArrow:Show();
		Atr_Col3_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 1.0, 0);
	end
end

-----------------------------------------

function Atr_ClearBrowseListings()
	
	local start = time();

	while (time() - start < 5) do
	
		if (CanSendAuctionQuery()) then
			QueryAuctionItems("xyzzy", 43, 43, 0, 7, 0);
			break;
		end
	end

end

-----------------------------------------

function Atr_SortAuctionData (x, y)

	return x.itemPrice < y.itemPrice;

end

-----------------------------------------

function AtrScan:CondenseAndSort ()

	----- Condense the scan data into a table that has only a single entry per stacksize/price combo

	self.sortedData	= {};

	local i,sd;
	local conddata = {};

	for i,sd in ipairs (self.scanData) do

		local ownerCode = "x";
		local dataType  = "n";		-- normal
		
		if (sd.owner == UnitName("player")) then
			ownerCode = "y";
--		elseif (Atr_IsMyToon (sd.owner)) then
--			ownerCode = sd.owner;
		elseif (sd.owner == "__wowEconG") then
			dataType = "eg";
		elseif (sd.owner == "__wowEconS") then
			dataType = "es";
		elseif (sd.owner == "__wowHead") then
			dataType = "h";
		elseif (sd.owner == "__allakhazam") then
			dataType = "k";
		elseif (sd.owner == "__atrLast") then
			dataType = "a";
		end

		local key = "_"..sd.stackSize.."_"..sd.buyoutPrice.."_"..ownerCode..dataType;

		if (conddata[key]) then
			conddata[key].count		= conddata[key].count + 1;
			conddata[key].minpage 	= zc.Min (conddata[key].minpage, sd.pagenum);
			conddata[key].maxpage 	= zc.Max (conddata[key].maxpage, sd.pagenum);
		else
			local data = {};

			data.stackSize 		= sd.stackSize;
			data.buyoutPrice	= sd.buyoutPrice;
			data.itemPrice		= sd.buyoutPrice / sd.stackSize;
			data.minpage		= sd.pagenum;
			data.maxpage		= sd.pagenum;
			data.count			= 1;
			data.type			= dataType;
			data.yours			= (ownerCode == "y");
			
			if (ownerCode ~= "x" and ownerCode ~= "y") then
				data.altname = ownerCode;
			end
			
			if (sd.volume) then
				data.volume = sd.volume;
			end
			
			conddata[key] = data;
		end

	end

	----- create a table of these entries

	local n = 1;

	local i, v;

	for i,v in pairs (conddata) do
		self.sortedData[n] = v;
		n = n + 1;
	end

	-- sort the table by itemPrice

	table.sort (self.sortedData, Atr_SortAuctionData);

	-- analyze and store some info about the data

	self:AnalyzeSortData ();

end

-----------------------------------------

function AtrScan:AnalyzeSortData ()

	self.absoluteBest			= nil;
	self.bestPrices				= {};		-- a table with one entry per stacksize that is the cheapest auction for that particular stacksize
	self.numMatches				= 0;
	self.numMatchesWithBuyout	= 0;
	self.hasStack				= false;
	self.yourBestPrice			= nil;
	self.yourWorstPrice			= nil;
	self.numYourSingletons		= 0;

	local j, sd;

	----- find the best price per stacksize and overall -----

	for j,sd in ipairs(self.sortedData) do

		if (sd.type == "n") then

			self.numMatches = self.numMatches + 1;

			if (sd.itemPrice > 0) then

				self.numMatchesWithBuyout = self.numMatchesWithBuyout + 1;

				if (self.bestPrices[sd.stackSize] == nil or self.bestPrices[sd.stackSize].itemPrice >= sd.itemPrice) then
					self.bestPrices[sd.stackSize] = sd;
				end

				if (self.absoluteBest == nil or self.absoluteBest.itemPrice > sd.itemPrice) then
					self.absoluteBest = sd;
				end
				
				if (sd.yours) then
					if (self.yourBestPrice == nil or self.yourBestPrice > sd.itemPrice) then
						self.yourBestPrice = sd.itemPrice;
					end
					
					if (self.yourWorstPrice == nil or self.yourWorstPrice < sd.itemPrice) then
						self.yourWorstPrice = sd.itemPrice;
					end
					
					if (sd.stackSize == 1) then
						self.numYourSingletons = self.numYourSingletons + sd.count;
					end
				end
			end

			if (sd.stackSize > 1) then
				self.hasStack = true;
			end
		end
	end
end

-----------------------------------------

function AtrScan:FindInSortedData (stackSize, buyoutPrice)
	local j = 1;
	for j = 1,#self.sortedData do
		sd = self.sortedData[j];
		if (sd.stackSize == stackSize and sd.buyoutPrice == buyoutPrice and sd.yours) then
			return j;
		end
	end
	
	return 0;
end


-----------------------------------------

function AtrScan:FindMatchByStackSize (stackSize)

	local index = nil;

	local basedata = self.absoluteBest;

	if (self.bestPrices[stackSize]) then
		basedata = self.bestPrices[stackSize];
	end

	local numrows = #self.sortedData;

	local n;

	for n = 1,numrows do

		local data = self.sortedData[n];

		if (basedata and data.itemPrice == basedata.itemPrice and data.stackSize == basedata.stackSize and data.yours == basedata.yours) then
			index = n;
			break;
		end
	end

	return index;
	
end

-----------------------------------------

function AtrScan:FindMatchByYours ()

	local index = nil;

	local j;
	for j = 1,#self.sortedData do
		sd = self.sortedData[j];
		if (sd.yours) then
			index = j;
			break;
		end
	end

	return index;

end

-----------------------------------------

function AtrScan:FindCheapest ()

	local index = nil;

	local j;
	for j = 1,#self.sortedData do
		sd = self.sortedData[j];
		if (sd.itemPrice > 0) then
			index = j;
			break;
		end
	end

	return index;

end


-----------------------------------------

function AtrScan:GetNumAvailable ()

	local num = 0;

	local j, data;
	for j = 1,#self.sortedData do

		data = self.sortedData[j];
		num = num + (data.count * data.stackSize);
	end
	
	return num;
end

-----------------------------------------

function AtrScan:IsNil ()

	if (self.itemName == nil or self.itemName == "" or self.itemName == "nil") then
		return true;
	end
	
	return false;
end

-----------------------------------------

ATR_FS_NULL			= 0;
ATR_FS_STARTED		= 1;
ATR_FS_ANALYZING	= 2;
ATR_FS_CLEANING_UP	= 3;
ATR_FS_WAIT_COOLDOWN	= 6;
ATR_FS_SLOW_SCAN	= 5;
ATR_FS_GETALL_RETRY	= 7;

ATR_FSS_NULL		= 0;

gAtr_FullScanState		= ATR_FS_NULL;
gAtr_FullScanSubState	= ATR_FSS_NULL;

gAtr_FullScanUseGetAll	= false;
local gAtr_FullScanAHTotal = nil;
local gAtr_FullScanGetAllBatch = 0;
local gAtr_FullScanRetryIndices = nil;
local gAtr_FullScanNullNames = 0;
local gAtr_FullScanRecoveredNames = 0;

local gAtr_SlowScanClass = nil;
local gAtr_SlowScanSubClass = 1;
local gAtr_SlowScanPage = 0;
local gAtr_SlowScanClassMax = 0;
local gAtr_FullScanSlowAwaitingQuery = false;
local gAtr_FullScanSlowTotalScanned = 0;

local gAtr_FullScanStart;
local gAtr_FullScanDur;

-----------------------------------------

function Atr_GetDBsize()

	local n = 0;
	local a,v;

	for a,v in pairs (gAtr_ScanDB) do
		n = n + 1;
	end
	
	return n;
end


-----------------------------------------

local gNumAdded, gNumUpdated;

local ATR_FULLSCAN_CHUNK_SIZE = 200;
local ATR_FULLSCAN_RETRY_CHUNK_SIZE = 100;
local ATR_FULLSCAN_WAIT_INTERVAL = 0.5;
local ATR_FULLSCAN_WAIT_MAX_ATTEMPTS = 80;
local ATR_FULLSCAN_GETALL_SETTLE_DELAY = 5.0;
local ATR_FULLSCAN_GETALL_NO_AILU_TIMEOUT = 30;
local ATR_FULLSCAN_GETALL_MIN_ITEMS = 50;
local ATR_FULLSCAN_GETALL_AILU_QUIET = 3.0;

local gAtr_FullScanWaitFrame;
local gAtr_FullScanProcessFrame;
local gAtr_FullScanCooldownFrame;
local gAtr_FullScanProcessIndex;
local gAtr_FullScanProcessTotal;
local gAtr_FullScanLowPrices;
local gAtr_FullScanQualities;
local gAtr_FullScanAILUCount = 0;

-----------------------------------------

local function Atr_FullScanIsActive()

	return gAtr_FullScanState == ATR_FS_STARTED
		or gAtr_FullScanState == ATR_FS_ANALYZING
		or gAtr_FullScanState == ATR_FS_SLOW_SCAN
		or gAtr_FullScanState == ATR_FS_WAIT_COOLDOWN
		or gAtr_FullScanState == ATR_FS_GETALL_RETRY;

end

local function Atr_FullScanBeginGetAllQuery()

	AtrScanDiag_StartSession ("getall");
	gAtr_FullScanState = ATR_FS_STARTED;
	AUCTIONATOR_LAST_GETALL_QUERY = time();
	Atr_FullScanBeginGetAllWait();
	QueryAuctionItems ("", nil, nil, 0, 0, 0, 0, 0, 0, true);
	AtrScanDiag_LogEvent ("QUERY_SENT", "GetAll params=0,0,true");
	AtrScanDiag_Phase ("QUERY_SENT", "getAll=true");

end

local function Atr_FullScanPrepareScanVars()

	gNumAdded = 0;
	gNumUpdated = 0;
	gAtr_FullScanLowPrices = {};
	gAtr_FullScanQualities = {};
	gAtr_FullScanSlowTotalScanned = 0;
	gAtr_FullScanSlowAwaitingQuery = false;
	gAtr_FullScanAHTotal = nil;
	gAtr_FullScanGetAllBatch = 0;

end

local function Atr_FullScanEnterActiveUI(statusText)

	Atr_FullScanSetProgressMode (true);
	Atr_FullScanStatus:SetText (statusText or (ZT("Scanning").."..."));
	Atr_FullScanStartButton:Enable();
	Atr_FullScanStartButton:SetText (ZT("Cancel scan"));
	Atr_FullScanDone:Disable();
	gAtr_FullScanStart = time();
	gAtr_FullScanDur   = nil;

end

local function Atr_FullScanEnsureCooldownFrame()

	if (not gAtr_FullScanCooldownFrame) then
		gAtr_FullScanCooldownFrame = CreateFrame ("Frame");
		gAtr_FullScanCooldownFrame:Hide();
		gAtr_FullScanCooldownFrame:SetScript ("OnUpdate", function (self, elapsed)

			if (gAtr_FullScanState ~= ATR_FS_WAIT_COOLDOWN) then
				self:Hide();
				return;
			end

			self.elapsed = (self.elapsed or 0) + elapsed;
			if (self.elapsed < 0.25) then
				return;
			end
			self.elapsed = 0;

			gAtr_FullScanDur = time() - gAtr_FullScanStart;

			local canQuery, canQueryAll = CanSendAuctionQuery();
			if (canQueryAll) then
				self:Hide();
				Atr_FullScanPrepareScanVars();
				Atr_FullScanStatus:SetText (ZT("Scanning").."...");
				zc.msg_atr (ZT("GetAll cooldown ready"));
				local level, pmsg = AtrScanDiag_PreflightGetAll();
				if pmsg then
					zc.msg_atr ("|cffff9900[AtrScanDiag]|r " .. pmsg);
				end
				Atr_FullScanBeginGetAllQuery();
				return;
			end

			Atr_FullScanStatus:SetText (ZT("GetAll cooldown status") .. " — " .. Atr_FullScan_GetCooldownText());

		end);
	end

end

function Atr_FullScanBeginCooldownWait()

	Atr_FullScanEnsureCooldownFrame();
	gAtr_FullScanCooldownFrame.elapsed = 0;
	gAtr_FullScanCooldownFrame:Show();

end

-----------------------------------------

function Atr_FullScanSetProgressMode (on)

	if (not Atr_FullScanStatus) then
		return;
	end

	if (on) then
		if (Atr_FullScanHTML) then
			Atr_FullScanHTML:Hide();
		end
		Atr_FullScanStatus:ClearAllPoints();
		Atr_FullScanStatus:SetPoint ("TOPLEFT", Atr_FullScanFrame, "TOPLEFT", 27, -188);
		Atr_FullScanStatus:SetPoint ("TOPRIGHT", Atr_FullScanFrame, "TOPRIGHT", -27, -188);
	else
		Atr_FullScanStatus:ClearAllPoints();
		Atr_FullScanStatus:SetPoint ("TOPLEFT", Atr_FullScanFrame, "TOPLEFT", 27, -128);
		Atr_FullScanStatus:SetPoint ("TOPRIGHT", Atr_FullScanFrame, "TOPRIGHT", -27, -128);
		if (Atr_FullScanHTML and Atr_FullScanResults and not Atr_FullScanResults:IsShown()) then
			Atr_FullScanHTML:Show();
		end
	end

end

local function Atr_FullScanFail (statusText, chatMsg, diagNote)

	gAtr_FullScanState = ATR_FS_NULL;
	gAtr_FullScanUseGetAll = false;

	if (gAtr_FullScanWaitFrame) then
		gAtr_FullScanWaitFrame:Hide();
	end
	if (gAtr_FullScanProcessFrame) then
		gAtr_FullScanProcessFrame:Hide();
	end
	if (gAtr_FullScanCooldownFrame) then
		gAtr_FullScanCooldownFrame:Hide();
	end

	Atr_FullScanSetProgressMode (false);
	Atr_FullScanStatus:SetText (statusText or ZT("Scan failed"));
	Atr_FullScanStartButton:Enable();
	Atr_FullScanStartButton:SetText (ZT("Start Scanning"));
	Atr_FullScanDone:Enable();

	if (diagNote) then
		AtrScanDiag_EndSession ("FAIL", diagNote);
	end
	if (chatMsg) then
		zc.msg_atr (chatMsg);
	end

	Atr_UpdateFullScanFrame();

end

-----------------------------------------

local function Atr_FullScanEnsureFrames()

	if (not gAtr_FullScanWaitFrame) then
		gAtr_FullScanWaitFrame = CreateFrame ("Frame");
		gAtr_FullScanWaitFrame:Hide();
		gAtr_FullScanWaitFrame.elapsed = 0;
		gAtr_FullScanWaitFrame.attempts = 0;
		gAtr_FullScanWaitFrame.lastNum = nil;
		gAtr_FullScanWaitFrame:SetScript ("OnUpdate", function (self, elapsed)

			AtrScanDiag_OnTick();

			if (gAtr_FullScanState ~= ATR_FS_STARTED or not gAtr_FullScanUseGetAll) then
				return;
			end

			if (self.settleDelay and self.settleDelay > 0) then
				self.settleDelay = self.settleDelay - elapsed;
				Atr_FullScanStatus:SetText (ZT("Waiting for auction data").."...");
				AtrScanDiag_SetSkipAuctionAPI (true);
				if (self.diagElapsed or 0) >= ATR_FULLSCAN_WAIT_INTERVAL then
					self.diagElapsed = 0;
					AtrScanDiag_Phase ("WAIT_SETTLE", string.format ("delay=%.1f ailu=%d", self.settleDelay, gAtr_FullScanAILUCount or 0));
				else
					self.diagElapsed = (self.diagElapsed or 0) + elapsed;
				end
				return;
			end

			if ((gAtr_FullScanAILUCount or 0) < 1) then
				self.noAiluElapsed = (self.noAiluElapsed or 0) + elapsed;
				Atr_FullScanStatus:SetText (ZT("Waiting for auction data").."...");
				AtrScanDiag_SetSkipAuctionAPI (true);
				if (self.noAiluElapsed >= ATR_FULLSCAN_GETALL_NO_AILU_TIMEOUT) then
					self:Hide();
					Atr_FullScanFail (ZT("GetAll no server data"), ZT("GetAll no server data chat"), "no AILU within " .. ATR_FULLSCAN_GETALL_NO_AILU_TIMEOUT .. "s");
				end
				return;
			end

			AtrScanDiag_SetSkipAuctionAPI (false);

			local ailuQuiet = AtrScanDiag_AiluQuietSeconds();
			if (ailuQuiet == nil or ailuQuiet < ATR_FULLSCAN_GETALL_AILU_QUIET) then
				AtrScanDiag_SetSkipAuctionAPI (true);
				AtrScanDiag_OnTick (string.format ("wait ailu quiet %.1fs", ailuQuiet or 0));
				return;
			end

			self.elapsed = self.elapsed + elapsed;
			if (self.elapsed < ATR_FULLSCAN_WAIT_INTERVAL) then
				return;
			end
			self.elapsed = 0;
			self.attempts = self.attempts + 1;

			local numBatchAuctions = AtrScanDiag_ProbeCounts ("poll #" .. self.attempts);

			if (numBatchAuctions == nil) then
				AtrScanDiag_Phase ("WAIT_POLL", "probe failed, retry");
				return;
			end

			if (numBatchAuctions >= ATR_FULLSCAN_GETALL_MIN_ITEMS) then
				if (self.lastNum == numBatchAuctions) then
					self.stableCount = (self.stableCount or 0) + 1;
				else
					self.lastNum = numBatchAuctions;
					self.stableCount = 0;
				end

				local stableNeeded = 2;
				if (numBatchAuctions >= 50000) then
					stableNeeded = 10;
				elseif (numBatchAuctions >= 10000) then
					stableNeeded = 4;
				end

				if (self.stableCount >= stableNeeded) then
					self:Hide();
					AtrScanDiag_Phase ("DATA_STABLE", "count=" .. numBatchAuctions);
					Atr_FullScanStartAnalyze (numBatchAuctions);
					return;
				end

				Atr_FullScanStatus:SetText (string.format ("%s (%d)", ZT("Receiving data"), numBatchAuctions));
				AtrScanDiag_Phase ("WAIT_POLL", "stable=" .. tostring(self.stableCount or 0) .. "/" .. stableNeeded);
			elseif (numBatchAuctions > 0) then
				Atr_FullScanStatus:SetText (string.format ("%s (%d)", ZT("Receiving data"), numBatchAuctions));
				self.lastNum = numBatchAuctions;
				AtrScanDiag_Phase ("WAIT_POLL", "partial=" .. numBatchAuctions);
			else
				AtrScanDiag_Phase ("WAIT_POLL", "batch=0 waiting");
			end

			if (self.attempts >= ATR_FULLSCAN_WAIT_MAX_ATTEMPTS) then
				self:Hide();
				Atr_FullScanFail (ZT("GetAll no server data"), ZT("GetAll no server data chat"), "timeout waiting for data");
			end
		end);
	end

	if (not gAtr_FullScanProcessFrame) then
		gAtr_FullScanProcessFrame = CreateFrame ("Frame");
		gAtr_FullScanProcessFrame:Hide();
		gAtr_FullScanProcessFrame:SetScript ("OnUpdate", function (self)
			if (gAtr_FullScanState ~= ATR_FS_ANALYZING and gAtr_FullScanState ~= ATR_FS_GETALL_RETRY) then
				self:Hide();
				return;
			end
			Atr_FullScanAnalyzeChunk();
		end);
	end

end

-----------------------------------------

function Atr_FullScanOnGetAllAuctionUpdate()

	if (gAtr_FullScanState ~= ATR_FS_STARTED or not gAtr_FullScanUseGetAll) then
		return;
	end

	local ok, err = pcall(function ()
		gAtr_FullScanAILUCount = (gAtr_FullScanAILUCount or 0) + 1;
		AtrScanDiag_OnAuctionUpdate();

		if (gAtr_FullScanAILUCount == 1 and gAtr_FullScanWaitFrame) then
			gAtr_FullScanWaitFrame.settleDelay = ATR_FULLSCAN_GETALL_SETTLE_DELAY;
			AtrScanDiag_Phase ("WAIT_SETTLE", "after AILU settle=" .. ATR_FULLSCAN_GETALL_SETTLE_DELAY);
		end
	end);

	if (not ok) then
		AtrScanDiag_RecordError ("OnGetAllAuctionUpdate: " .. tostring(err));
	end

end

-----------------------------------------

function Atr_FullScanBeginGetAllWait()

	Atr_FullScanEnsureFrames();

	gAtr_FullScanAILUCount = 0;
	gAtr_FullScanWaitFrame.elapsed = 0;
	gAtr_FullScanWaitFrame.attempts = 0;
	gAtr_FullScanWaitFrame.lastNum = nil;
	gAtr_FullScanWaitFrame.stableCount = 0;
	gAtr_FullScanWaitFrame.diagElapsed = 0;
	gAtr_FullScanWaitFrame.noAiluElapsed = 0;
	gAtr_FullScanWaitFrame.settleDelay = nil;
	AtrScanDiag_SetSkipAuctionAPI (true);
	gAtr_FullScanWaitFrame:Show();

	Atr_FullScanStatus:SetText (ZT("Waiting for auction data").."...");
	AtrScanDiag_LogEvent ("QUERY_WAIT", "waiting for AILU from server");

end

-----------------------------------------

function Atr_FullScanStartAnalyze (numBatchAuctions)

	gAtr_FullScanState = ATR_FS_ANALYZING;
	Atr_FullScanStatus:SetText (ZT("Processing"));
	AtrScanDiag_Phase ("PROCESS_START", "total=" .. numBatchAuctions);

	local _, ahTotal = AtrScanDiag_GetLastTotals();
	if (ahTotal) then
		gAtr_FullScanAHTotal = ahTotal;
	end

	gAtr_FullScanProcessIndex = 0;
	gAtr_FullScanProcessTotal = numBatchAuctions;
	gAtr_FullScanGetAllBatch = numBatchAuctions;
	gAtr_FullScanLowPrices = {};
	gAtr_FullScanQualities = {};
	gAtr_FullScanRetryIndices = nil;
	gAtr_FullScanNullNames = 0;
	gAtr_FullScanRecoveredNames = 0;

	zc.md ("FULL SCAN:"..numBatchAuctions.." AH total:"..tostring(gAtr_FullScanAHTotal));

	collectgarbage ("collect");
	Atr_FullScanEnsureFrames();
	gAtr_FullScanProcessFrame:Show();

end

-----------------------------------------

local function Atr_FullScanNameFromLink (link)

	if (link == nil) then
		return nil;
	end

	local name = GetItemInfo (link);
	if (name ~= nil and name ~= "") then
		return name;
	end

	local itemID = link:match ("item:(%d+)");
	if (itemID) then
		name = GetItemInfo (tonumber (itemID));
		if (name ~= nil and name ~= "") then
			return name;
		end
	end

	local fromLink = link:match ("%[(.-)%]");
	if (fromLink ~= nil and fromLink ~= "") then
		return fromLink;
	end

	return nil;

end

local function Atr_FullScanProcessYield (index)

	if (AUCTIONATOR_DC_PAUSE == nil) then
		AUCTIONATOR_DC_PAUSE = 40;
	end

	if (AUCTIONATOR_DC_PAUSE > 0 and (index % 25) == 0) then
		local k = 3;
		for i = 1, AUCTIONATOR_DC_PAUSE do
			k = 3;
		end
	end

end

local function Atr_FullScanUnitPrice (count, buyoutPrice)

	count = tonumber (count) or 1;
	if (count < 1) then
		count = 1;
	end

	-- Only buyout counts (same as original Auctionator). Bid-only lots must not pollute the DB.
	if (buyoutPrice == nil or buyoutPrice <= 0) then
		return nil;
	end

	return math.floor (buyoutPrice / count);

end

local function Atr_FullScanReadAuctionIndex (index)

	local link = GetAuctionItemLink ("list", index);
	if (link) then
		GetItemInfo (link);
	end

	local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount = GetAuctionItemInfo ("list", index);

	if (name == nil or name == "") then
		name = Atr_FullScanNameFromLink (link);
	end

	if (name == nil or name == "") then
		return nil;
	end

	if ((quality == nil or quality == 0) and link) then
		local _, _, _, q = GetItemInfo (link);
		if (q) then
			quality = q;
		end
	end

	return name, count, quality, buyoutPrice, minBid, bidAmount;

end

local function Atr_FullScanQualityIndex (quality)

	local q = tonumber (quality) or 0;
	if (q < 0) then
		q = 0;
	end

	local qx = q + 1;
	if (qx < 1) then
		qx = 1;
	elseif (qx > 9) then
		qx = 9;
	end

	return qx;

end

local function Atr_FullScanRecordAuction (lowprices, qualities, name, count, quality, buyoutPrice, minBid, bidAmount)

	if (name == nil) then
		return;
	end

	if (gAtr_MeanDB[name] == nil) then
		gAtr_MeanDB[name] = {};
	end

	quality = tonumber (quality) or 0;

	local itemPrice = Atr_FullScanUnitPrice (count, buyoutPrice);
	if (not itemPrice or itemPrice <= 0) then
		return;
	end

	if (qualities[name] == nil or quality > (tonumber (qualities[name]) or 0)) then
		qualities[name] = quality;
	end

	if (not lowprices[name]) then
		lowprices[name] = {BIGNUM,BIGNUM,BIGNUM};
	end

	Atr_AddToLowPrices (lowprices[name], itemPrice);

end

-----------------------------------------

function Atr_FullScanAnalyzeChunk()

	local numBatchAuctions = gAtr_FullScanProcessTotal;
	local lowprices = gAtr_FullScanLowPrices;
	local qualities = gAtr_FullScanQualities;

	if (gAtr_FullScanState == ATR_FS_GETALL_RETRY) then
		Atr_FullScanAnalyzeRetryChunk (lowprices, qualities);
		return;
	end

	local x = gAtr_FullScanProcessIndex + 1;
	local xEnd = math.min (x + ATR_FULLSCAN_CHUNK_SIZE - 1, numBatchAuctions);

	while (x <= xEnd) do

		Atr_FullScanProcessYield (x);

		local ok, name, count, quality, buyoutPrice, minBid, bidAmount = pcall (function ()
			return Atr_FullScanReadAuctionIndex (x);
		end);

		if (ok and name ~= nil) then
			Atr_FullScanRecordAuction (lowprices, qualities, name, count, quality, buyoutPrice, minBid, bidAmount);
		elseif (ok) then
			gAtr_FullScanNullNames = gAtr_FullScanNullNames + 1;
			if (not gAtr_FullScanRetryIndices) then
				gAtr_FullScanRetryIndices = {};
			end
			tinsert (gAtr_FullScanRetryIndices, x);
		end

		if (x % 500 == 0) then
			Atr_FullScanStatus:SetText (ZT("Processing").." ("..x.."/"..numBatchAuctions..")");
			AtrScanDiag_Phase ("PROCESS", tostring (x) .. "/" .. numBatchAuctions);
		end

		x = x + 1;
	end

	gAtr_FullScanProcessIndex = xEnd;

	if (xEnd >= numBatchAuctions) then
		if (gAtr_FullScanRetryIndices and #gAtr_FullScanRetryIndices > 0) then
			gAtr_FullScanState = ATR_FS_GETALL_RETRY;
			gAtr_FullScanProcessIndex = 0;
			gAtr_FullScanProcessTotal = #gAtr_FullScanRetryIndices;
			AtrScanDiag_Phase ("PROCESS_RETRY", "count=" .. #gAtr_FullScanRetryIndices);
			Atr_FullScanStatus:SetText (ZT("Processing retry").." (0/"..#gAtr_FullScanRetryIndices..")");
		else
			gAtr_FullScanProcessFrame:Hide();
			Atr_FullScanAnalyzeFinish (numBatchAuctions, lowprices, qualities);
		end
	else
		Atr_FullScanStatus:SetText (ZT("Processing").." ("..xEnd.."/"..numBatchAuctions..")");
	end

end

-----------------------------------------

function Atr_FullScanAnalyzeRetryChunk (lowprices, qualities)

	local retryTotal = gAtr_FullScanProcessTotal;
	local ri = gAtr_FullScanProcessIndex + 1;
	local riEnd = math.min (ri + ATR_FULLSCAN_RETRY_CHUNK_SIZE - 1, retryTotal);

	while (ri <= riEnd) do

		local auctionIndex = gAtr_FullScanRetryIndices[ri];
		Atr_FullScanProcessYield (auctionIndex or ri);

		local ok, name, count, quality, buyoutPrice, minBid, bidAmount = pcall (function ()
			return Atr_FullScanReadAuctionIndex (auctionIndex);
		end);

		if (ok and name ~= nil) then
			gAtr_FullScanRecoveredNames = gAtr_FullScanRecoveredNames + 1;
			Atr_FullScanRecordAuction (lowprices, qualities, name, count, quality, buyoutPrice, minBid, bidAmount);
		end

		if (ri % 200 == 0) then
			Atr_FullScanStatus:SetText (ZT("Processing retry").." ("..ri.."/"..retryTotal..")");
		end

		ri = ri + 1;
	end

	gAtr_FullScanProcessIndex = riEnd;

	if (riEnd >= retryTotal) then
		gAtr_FullScanProcessFrame:Hide();
		AtrScanDiag_Phase ("PROCESS_RETRY_DONE", "recovered=" .. gAtr_FullScanRecoveredNames .. " null=" .. gAtr_FullScanNullNames);
		Atr_FullScanAnalyzeFinish (gAtr_FullScanGetAllBatch, lowprices, qualities);
	else
		Atr_FullScanStatus:SetText (ZT("Processing retry").." ("..riEnd.."/"..retryTotal..")");
	end

end

-----------------------------------------

function Atr_FullScanSlowScanSendQuery()

	if (not CanSendAuctionQuery()) then
		gAtr_FullScanSlowAwaitingQuery = true;
		return;
	end

	gAtr_FullScanSlowAwaitingQuery = false;

	local class = gAtr_SlowScanClass;
	local page = gAtr_SlowScanPage;
	local classes = Atr_GetAuctionClasses();
	local className = classes[class] or "?";
	local subclasses = Atr_GetAuctionSubclasses (class);
	local subClass = 0;
	local subName = className;

	if (#subclasses > 0) then
		subClass = gAtr_SlowScanSubClass;
		subName = subclasses[subClass] or "?";
	end

	QueryAuctionItems ("", nil, nil, 0, class, subClass, page, 0, 0, false);

	Atr_FullScanStatus:SetText (string.format (ZT("Scanning %s / %s (%d/%d) p.%d"), className, subName, class, gAtr_SlowScanClassMax, page + 1));

end

-----------------------------------------

local function Atr_FullScanSlowScanAdvanceFilter()

	local subclasses = Atr_GetAuctionSubclasses (gAtr_SlowScanClass);

	gAtr_SlowScanPage = 0;

	if (#subclasses > 0 and gAtr_SlowScanSubClass < #subclasses) then
		gAtr_SlowScanSubClass = gAtr_SlowScanSubClass + 1;
		return false;
	end

	gAtr_SlowScanSubClass = 1;
	gAtr_SlowScanClass = gAtr_SlowScanClass + 1;

	if (gAtr_SlowScanClass > gAtr_SlowScanClassMax) then
		return true;
	end

	return false;

end

-----------------------------------------

function Atr_FullScanSlowScanProcessPage()

	local numBatchAuctions = GetNumAuctionItems ("list");
	local lowprices = gAtr_FullScanLowPrices;
	local qualities = gAtr_FullScanQualities;
	local x;

	for x = 1, numBatchAuctions do

		local name, count, quality, buyoutPrice, minBid, bidAmount = Atr_FullScanReadAuctionIndex (x);

		if (name ~= nil) then
			Atr_FullScanRecordAuction (lowprices, qualities, name, count, quality, buyoutPrice, minBid, bidAmount);
		end
	end

	gAtr_FullScanSlowTotalScanned = gAtr_FullScanSlowTotalScanned + numBatchAuctions;
	gAtr_FullScanDur = time() - gAtr_FullScanStart;

	if (numBatchAuctions >= 50) then
		gAtr_SlowScanPage = gAtr_SlowScanPage + 1;
		Atr_FullScanSlowScanSendQuery();
		return;
	end

	if (Atr_FullScanSlowScanAdvanceFilter()) then
		AtrScanDiag_EndSession ("OK", "class scan complete");
		Atr_FullScanAnalyzeFinish (gAtr_FullScanSlowTotalScanned, lowprices, qualities);
		return;
	end

	Atr_FullScanSlowScanSendQuery();

end

-----------------------------------------

function Atr_FullScanRefreshHelp()

	if (not Atr_FullScanHTML) then
		return;
	end

	local modeHelp = ZT("SCAN_HELP_GETALL");
	if (Atr_FullScan_GetAll and not Atr_FullScan_GetAll:GetChecked()) then
		modeHelp = ZT("SCAN_HELP_FULL");
	end

	local expText = "<html><body><p>"
					..ZT("SCAN_INTRO")
					.."<br/><br/>"
					..modeHelp
					.."</p></body></html>";

	Atr_FullScanHTML:SetText (expText);
	Atr_FullScanHTML:SetSpacing (3);

end

-----------------------------------------

function Atr_FullScan_GetCooldownRemainingSec()

	local t = AUCTIONATOR_LAST_GETALL_QUERY or AUCTIONATOR_LAST_SCAN_TIME;
	if (not t) then
		return nil;
	end

	return math.max (0, 15 * 60 - (time() - t));

end

function Atr_FullScan_GetCooldownText()

	local sec = Atr_FullScan_GetCooldownRemainingSec();

	if (sec == nil) then
		return ZT("waiting for server");
	end

	if (sec <= 0) then
		return ZT("checking server");
	end

	if (sec < 60) then
		return string.format (ZT("in %d sec"), sec);
	end

	local when = math.floor (sec / 60);
	if (when == 1) then
		return ZT("in about one minute");
	end

	return string.format (ZT("in about %d minutes"), when);

end

-----------------------------------------

function Atr_FullScanCancel()

	if (gAtr_FullScanState == ATR_FS_NULL) then
		return;
	end

	if (gAtr_FullScanWaitFrame) then
		gAtr_FullScanWaitFrame:Hide();
	end
	if (gAtr_FullScanProcessFrame) then
		gAtr_FullScanProcessFrame:Hide();
	end
	if (gAtr_FullScanCooldownFrame) then
		gAtr_FullScanCooldownFrame:Hide();
	end

	AtrScanDiag_EndSession ("CANCEL", "user cancelled");

	gAtr_FullScanState = ATR_FS_NULL;
	gAtr_FullScanUseGetAll = false;

	Atr_FullScanSetProgressMode (false);
	Atr_FullScanStartButton:Enable();
	Atr_FullScanStartButton:SetText (ZT("Start Scanning"));
	Atr_FullScanDone:Enable();

	Atr_FullScanHTML:Show();
	Atr_FullScanResults:Hide();
	Atr_FullScanStatus:SetText (ZT("Scan cancelled"));

	Atr_ClearBrowseListings();
	collectgarbage ("collect");
	Atr_UpdateFullScanFrame();

end

-----------------------------------------

function Atr_FullScanStart()

	if (gAtr_FullScanState ~= ATR_FS_NULL) then
		Atr_FullScanCancel();
		return;
	end

	gAtr_FullScanUseGetAll = false;
	if (Atr_FullScan_GetAll and Atr_FullScan_GetAll:GetChecked()) then
		gAtr_FullScanUseGetAll = true;
		zc.msg_atr (ZT("GetAll warning"));
	end

	local canQuery, canQueryAll = CanSendAuctionQuery();

	if (gAtr_FullScanUseGetAll and not canQueryAll) then
		Atr_FullScanEnterActiveUI (ZT("GetAll cooldown status") .. " — " .. Atr_FullScan_GetCooldownText());
		gAtr_FullScanState = ATR_FS_WAIT_COOLDOWN;
		Atr_FullScanBeginCooldownWait();
		zc.msg_atr (ZT("GetAll waiting cooldown"));
		return;
	end

	if (not gAtr_FullScanUseGetAll and not canQuery) then
		Atr_FullScanStatus:SetText (ZT("Scan wait server"));
		zc.msg_atr (ZT("Scan wait server"));
		return;
	end

	Atr_FullScanEnterActiveUI (ZT("Scanning").."...");
	Atr_FullScanPrepareScanVars();

	if (not gAtr_FullScanUseGetAll) then
		SortAuctionClearSort ("list");
	end

	if (gAtr_FullScanUseGetAll) then
		local level, pmsg = AtrScanDiag_PreflightGetAll();
		if pmsg then
			zc.msg_atr ("|cffff9900[AtrScanDiag]|r " .. pmsg);
		end
		Atr_FullScanBeginGetAllQuery();
	else
		SortAuctionClearSort ("list");
		collectgarbage ("collect");
		AtrScanDiag_StartSession ("class");
		AtrScanDiag_Phase ("QUERY_SENT", "class scan");
		gAtr_SlowScanClass = 1;
		gAtr_SlowScanSubClass = 1;
		gAtr_SlowScanPage = 0;
		gAtr_SlowScanClassMax = #Atr_GetAuctionClasses();
		gAtr_FullScanState = ATR_FS_SLOW_SCAN;
		Atr_FullScanSlowScanSendQuery();
	end

end

-----------------------------------------

function Atr_CalcNewDBprice (name, prices)
		
	if (prices[1] ~= BIGNUM) then
		return prices[1];
	end

	return 0;
	
end

-----------------------------------------

function Atr_AddToLowPrices (lowprices, itemPrice)
	
	if (itemPrice > 0) then
		if (itemPrice < lowprices[1]) then
			if (lowprices[1] < lowprices[2]) then
				lowprices[2] = lowprices[1];
			end
			lowprices[1] = itemPrice;
			return true;
		elseif (itemPrice < lowprices[2]) then
			lowprices[2] = itemPrice;
			return true;
		end
	end

	return false;
end




-----------------------------------------

local gScanDetails = {}

-----------------------------------------

function Atr_FullScanMoreDetails ()

	local minutes = math.floor (gAtr_FullScanDur/60);
	local seconds = gAtr_FullScanDur - (minutes * 60);

	zc.msg (" ");
	zc.msg_atr (string.format ("Scan complete (%d:%02d)", minutes, seconds));
	zc.msg_atr (ZT("Auctions scanned")..": |cffffffff", gScanDetails.numBatchAuctions, " |r("..gScanDetails.totalItems, ZT("unique items")..")");
	zc.msg_atr ("|cffa335ee   "..ZT("Epic items")..": |r",		gScanDetails.numEachQual[5]);
	zc.msg_atr ("|cff0070dd   "..ZT("Rare items")..": |r",		gScanDetails.numEachQual[4]);
	zc.msg_atr ("|cff1eff00   "..ZT("Uncommon items")..": |r",	gScanDetails.numEachQual[3]);
	zc.msg_atr ("|cffffffff   "..ZT("Common items")..": |r",		gScanDetails.numEachQual[2]);
	zc.msg_atr ("|cff9d9d9d   "..ZT("Poor items")..": |r",		gScanDetails.numEachQual[1]);
	
	
	if (gScanDetails.numRemoved[4] > 0) then		zc.msg_atr (ZT("Rare items").." "..ZT("removed from database")..": |cffffffff",		gScanDetails.numRemoved[4]);		end
	if (gScanDetails.numRemoved[3] > 0) then		zc.msg_atr (ZT("Uncommon items").." "..ZT("removed from database")..": |cffffffff",	gScanDetails.numRemoved[3]);		end
	if (gScanDetails.numRemoved[2] > 0) then		zc.msg_atr (ZT("Common items").." "..ZT("removed from database")..": |cffffffff",	gScanDetails.numRemoved[2]);		end
	if (gScanDetails.numRemoved[1] > 0) then		zc.msg_atr (ZT("Poor items").." "..ZT("removed from database")..": |cffffffff",		gScanDetails.numRemoved[1]);		end
	
	zc.msg_atr (ZT("Items added to database")..": |cffffffff", gScanDetails.gNumAdded);
	zc.msg_atr (ZT("Items updated in database")..": |cffffffff", gScanDetails.gNumUpdated);
	zc.msg_atr (ZT("Items ignored")..": |cffffffff", gScanDetails.totalItems - (gScanDetails.gNumAdded + gScanDetails.gNumUpdated));

	if (gScanDetails.ahTotal and gScanDetails.numBatchAuctions and gScanDetails.ahTotal > gScanDetails.numBatchAuctions) then
		zc.msg_atr ("|cffff9900"..ZT("GetAll AH total")..": |r", gScanDetails.ahTotal, " |cffff9900"..ZT("GetAll batch cap")..": |r", gScanDetails.numBatchAuctions);
	end
	if ((gScanDetails.recoveredNames or 0) > 0) then
		zc.msg_atr (ZT("GetAll names recovered")..": |cffffffff", gScanDetails.recoveredNames);
	end
	local stillMissing = (gScanDetails.nullNames or 0) - (gScanDetails.recoveredNames or 0);
	if (stillMissing > 0) then
		zc.msg_atr (ZT("GetAll names missing")..": |cffffffff", stillMissing);
	end
	zc.msg (" ");
end

-----------------------------------------

function Atr_FullScanAnalyzeFinish (numBatchAuctions, lowprices, qualities)

	local numEachQual = {0, 0, 0, 0, 0, 0, 0, 0, 0};
	local totalItems = 0;
	local numRemoved = { 0, 0, 0, 0, 0, 0, 0, 0 };
	
	for name,prices in pairs (lowprices) do
		
		local newprice = Atr_CalcNewDBprice (name, prices);
		
		if (newprice > 0) then
		
			local qx = Atr_FullScanQualityIndex (qualities[name]);
			
			numEachQual[qx]	= numEachQual[qx] + 1;
			totalItems		= totalItems + 1;
			
			if (qx < AUCTIONATOR_SCAN_MINLEVEL and gAtr_ScanDB[name]) then
				numRemoved[qx] = (numRemoved[qx] or 0) + 1;
				gAtr_ScanDB[name] = nil;
				zc.md ("removed: |cffbbbbbb", name, "   ("..qx..")");
			end
			
			if (qx >= AUCTIONATOR_SCAN_MINLEVEL) then

				if (gAtr_ScanDB[name] == nil) then
					gNumAdded = gNumAdded + 1;
				else
					gNumUpdated = gNumUpdated + 1;
				end

				gAtr_ScanDB[name] = newprice;
				if (gAtr_MeanDB[name] == nil) then
					gAtr_MeanDB[name] = {};
				end
                if #gAtr_MeanDB[name] < 15 then
                    table.insert(gAtr_MeanDB[name], newprice)
                else
                    table.remove(gAtr_MeanDB[name], math.random(1, #gAtr_MeanDB[name]))
                    table.insert(gAtr_MeanDB[name], newprice)
                end
			end
		end
	end
    
    for name in pairs(gAtr_MeanDB) do
        table.sort(gAtr_MeanDB[name])
    end

	gScanDetails.numBatchAuctions		= numBatchAuctions;
	gScanDetails.totalItems				= totalItems;
	gScanDetails.numEachQual			= numEachQual;
	gScanDetails.numRemoved				= numRemoved;
	gScanDetails.gNumAdded				= gNumAdded;
	gScanDetails.gNumUpdated			= gNumUpdated;
	gScanDetails.ahTotal				= gAtr_FullScanAHTotal;
	gScanDetails.nullNames				= gAtr_FullScanNullNames or 0;
	gScanDetails.recoveredNames			= gAtr_FullScanRecoveredNames or 0;


	if (Atr_PrintBargains and Atr_CheckForBargain and numBatchAuctions > 0 and numBatchAuctions <= 10000) then

		for bx = 1, numBatchAuctions do
			Atr_CheckForBargain (bx);
		end
		
		Atr_PrintBargains();
	end
	
	gAtr_FullScanState = ATR_FS_CLEANING_UP;

	Atr_FullScanMoreDetails();

	Atr_FullScanDone:Enable();
	Atr_FullScanStartButton:Enable();
	Atr_FullScanStartButton:SetText (ZT("Start Scanning"));
	Atr_FullScanSetProgressMode (false);

	Atr_FullScanStatus:SetText (string.format (ZT("Scan complete status"), Atr_FullScan_GetDurString()));
	
	Atr_FSR_scanned_count:SetText	(numBatchAuctions);
	Atr_FSR_added_count:SetText		(gNumAdded);
	Atr_FSR_updated_count:SetText	(gNumUpdated);
	Atr_FSR_ignored_count:SetText	(totalItems - (gNumAdded + gNumUpdated));
	
	Atr_FullScanHTML:Hide();
	Atr_FullScanResults:Show();
	
	AUCTIONATOR_LAST_SCAN_TIME = time();

	if (gAtr_FullScanUseGetAll) then
		AtrScanDiag_EndSession ("OK", "getall auctions=" .. numBatchAuctions .. " unique=" .. totalItems .. " db=" .. Atr_GetDBsize());
	end

	gAtr_FullScanAHTotal = nil;
	
	Atr_UpdateFullScanFrame ();

	Atr_ClearBrowseListings();
	
	lowprices = {};
	collectgarbage ("collect");
end

-----------------------------------------

function Atr_ShowFullScanFrame()

	Atr_FullScanHTML:Show();
	Atr_FullScanResults:Hide();

	if (Atr_FullScan_GetAll) then
		Atr_FullScan_GetAll:Show();
	end

	Atr_FullScanFrame:Show();
	Atr_FullScanFrame:SetBackdropColor(0,0,0,100);

	if (Atr_FullScan_GetAll) then
		Atr_FullScan_GetAll:SetChecked (true);
		gAtr_FullScanUseGetAll = true;
	end
	if (Atr_FullScan_GetAllLabel) then
		Atr_FullScan_GetAllLabel:SetText (ZT("GetAll fast scan"));
	end
	if (Atr_FullScan_GetAllLabel2) then
		Atr_FullScan_GetAllLabel2:SetText (ZT("GetAll cooldown hint"));
	end
	
	Atr_FullScanSetProgressMode (false);
	Atr_UpdateFullScanFrame();
	Atr_FullScanRefreshHelp();
	Atr_FullScanStatus:SetText ("");
end

-----------------------------------------

function Atr_UpdateFullScanFrame()

	Atr_FullScanDBsize:SetText (Atr_GetDBsize());
	
	if (AUCTIONATOR_LAST_SCAN_TIME) then
		Atr_FullScanDBwhen:SetText (date ("%A, %B %d at %I:%M %p", AUCTIONATOR_LAST_SCAN_TIME));
	else
		Atr_FullScanDBwhen:SetText (ZT("Never"));
	end

	if (Atr_FullScan_GetAll) then
		gAtr_FullScanUseGetAll = Atr_FullScan_GetAll:GetChecked();
	end

	local canQuery, canQueryAll = CanSendAuctionQuery();

	if (Atr_FullScanIsActive()) then
		Atr_FullScanStartButton:Enable();
		Atr_FullScanStartButton:SetText (ZT("Cancel scan"));
		Atr_FullScanDone:Disable();
		return;
	end

	Atr_FullScanStartButton:SetText (ZT("Start Scanning"));
	Atr_FullScanDone:Enable();
	Atr_FullScanStartButton:Enable();

	if (gAtr_FullScanUseGetAll) then
		if (canQueryAll) then
			Atr_FullScanNext:SetText (ZT("Now"));
		else
			Atr_FullScanNext:SetText (Atr_FullScan_GetCooldownText());
		end
	else
		if (canQuery) then
			Atr_FullScanNext:SetText (ZT("Full scan (no cooldown)"));
		else
			Atr_FullScanNext:SetText (ZT("Scan wait server"));
		end
	end

end

-----------------------------------------

function Atr_FullScan_GetDurString()

	local minutes = math.floor (gAtr_FullScanDur/60);
	local seconds = gAtr_FullScanDur - (minutes * 60);

	return string.format ("%d:%02d", minutes, seconds);
end

-----------------------------------------

function Atr_FullScanRefreshUIIfNeeded (elapsed)

	if (not Atr_FullScanFrame or not Atr_FullScanFrame:IsShown()) then
		return;
	end
	if (Atr_FullScanIsActive()) then
		return;
	end

	gAtr_FullScanUIRefresh = (gAtr_FullScanUIRefresh or 0) + elapsed;
	if (gAtr_FullScanUIRefresh >= 2) then
		gAtr_FullScanUIRefresh = 0;
		Atr_UpdateFullScanFrame();
	end

end

-----------------------------------------

function Atr_FullScanFrameIdle()

	if (gAtr_FullScanState == ATR_FS_SLOW_SCAN) then

		if (gAtr_FullScanSlowAwaitingQuery) then
			Atr_FullScanSlowScanSendQuery();
		end

		gAtr_FullScanDur = time() - gAtr_FullScanStart;
		return;
	end

	if (gAtr_FullScanState == ATR_FS_STARTED) then
		gAtr_FullScanDur = time() - gAtr_FullScanStart;
		return;
	end


	if (gAtr_FullScanState == ATR_FS_CLEANING_UP) then
	
		if (GetNumAuctionItems("list") < 100) then
			PlaySound("AuctionWindowClose");
			gAtr_FullScanState = ATR_FS_NULL;
			Atr_UpdateFullScanFrame();
		end
	end
	
end







