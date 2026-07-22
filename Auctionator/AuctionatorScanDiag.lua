
-- Scan diagnostics — logs to WTF SavedVariables (AUCTIONATOR_SCAN_DIAG)
-- Saves on /reload or logout to:
--   WTF/Account/<account>/SavedVariables/Auctionator.lua

local addonName, addonTable = ...;
local zc = addonTable.zc;

local function DiagPrint(msg)
	local z = zc or gAtrZC;
	if z and z.msg_atr then
		z.msg_atr(msg);
	elseif DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(msg);
	end
end

AUCTIONATOR_SCAN_DIAG = AUCTIONATOR_SCAN_DIAG or {};

local MAX_HISTORY = 40;
local MAX_FAIL_SAMPLES = 20;
local MAX_LOG_LINES = 500;
local MAX_EVENT_TRAIL = 100;
local MAX_SNAPSHOTS = 80;
local TICK_LOG_INTERVAL = 0.25;
local AILU_QUIET_BEFORE_PROBE = 3.0;

local gDiagSession = nil;
local gDiagVerbose = false;
local gDiagSkipAuctionAPI = false;
local gDiagLastPhaseLog = 0;
local PHASE_LOG_INTERVAL = 0.5;

local function DiagTimestamp()
	return date("%Y-%m-%d %H:%M:%S");
end

local function DiagRealmKey()
	return (GetRealmName() or "?") .. "_" .. (UnitFactionGroup("player") or "?");
end

local function DiagMemKB()
	local ok, mem = pcall(function()
		UpdateAddOnMemoryUsage();
		return GetAddOnMemoryUsage("Auctionator");
	end);
	if ok and mem and mem > 0 then
		return math.floor(mem + 0.5);
	end
	return 0;
end

local function DiagAuctionCounts()
	local ok, batch, total = pcall(GetNumAuctionItems, "list");
	if not ok then
		return nil, nil, batch;
	end
	return batch or 0, total or 0, nil;
end

local function DiagAuctionCountsSafe()
	if gDiagSkipAuctionAPI and gDiagSession then
		return gDiagSession.batch or 0, gDiagSession.total or 0, nil;
	end
	return DiagAuctionCounts();
end

local function DiagCanQuery()
	local canQuery, canGetAll = CanSendAuctionQuery();
	return canQuery and true or false, canGetAll and true or false;
end

local function DiagSessionElapsed()
	if not gDiagSession or not gDiagSession.startClockHi then
		return 0;
	end
	return GetTime() - gDiagSession.startClockHi;
end

local function DiagPushEventTrail(event, detail)
	if not gDiagSession then
		return;
	end
	gDiagSession.eventTrail = gDiagSession.eventTrail or {};
	local entry = {
		t = DiagSessionElapsed(),
		e = event,
		d = detail or "",
		mem = DiagMemKB(),
		ailu = gDiagSession.ailuCount or 0,
	};
	tinsert(gDiagSession.eventTrail, entry);
	while #gDiagSession.eventTrail > MAX_EVENT_TRAIL do
		tremove(gDiagSession.eventTrail, 1);
	end
	gDiagSession.lastEvent = event;
end

function AtrScanDiag_RecordError(errMsg)

	local d = AUCTIONATOR_SCAN_DIAG;
	d.logLines = d.logLines or {};
	d.lastError = tostring(errMsg);
	d.lastErrorTime = DiagTimestamp();

	local line = string.format("%s | %s | event=LUA_ERROR | t=%.2fs | %s",
		DiagTimestamp(), DiagRealmKey(), gDiagSession and DiagSessionElapsed() or 0, d.lastError);
	tinsert(d.logLines, line);
	while #d.logLines > MAX_LOG_LINES do
		tremove(d.logLines, 1);
	end
	d.lastLine = line;
	d.lastUpdate = time();

	if gDiagSession then
		DiagPushEventTrail("LUA_ERROR", d.lastError);
		AtrScanDiag_PersistInterrupt();
	end

	DiagPrint("|cffff0000[AtrScanDiag ERROR]|r " .. d.lastError);

end

-----------------------------------------

function AtrScanDiag_SetSkipAuctionAPI(skip)
	gDiagSkipAuctionAPI = skip and true or false;
end

-----------------------------------------

function AtrScanDiag_LogEvent(event, detail)

	if not gDiagSession then
		return;
	end

	local ok, err = pcall(function()
		DiagPushEventTrail(event, detail);

		local line = string.format("%s | %s | event=%s | t=%.2fs | ailu=%d | mem=%dKB | phase=%s%s",
			DiagTimestamp(), DiagRealmKey(), event, DiagSessionElapsed(),
			gDiagSession.ailuCount or 0, DiagMemKB(), gDiagSession.phase or "-",
			detail and (" | " .. detail) or "");

		local d = AUCTIONATOR_SCAN_DIAG;
		d.logLines = d.logLines or {};
		tinsert(d.logLines, line);
		while #d.logLines > MAX_LOG_LINES do
			tremove(d.logLines, 1);
		end
		d.lastLine = line;
		d.lastUpdate = time();

		if gDiagVerbose then
			DiagPrint("[AtrScanDiag] " .. line);
		end

		AtrScanDiag_PersistInterrupt();

		d.snapshots = d.snapshots or {};
		local snap = string.format("%s | t=%.2fs | %s | ailu=%d | phase=%s | skipAPI=%s%s",
			DiagTimestamp(), DiagSessionElapsed(), event,
			gDiagSession.ailuCount or 0, gDiagSession.phase or "-",
			tostring(gDiagSkipAuctionAPI),
			detail and (" | " .. detail) or "");
		tinsert(d.snapshots, snap);
		while #d.snapshots > MAX_SNAPSHOTS do
			tremove(d.snapshots, 1);
		end
	end);

	if not ok then
		AtrScanDiag_RecordError("LogEvent/" .. tostring(event) .. ": " .. tostring(err));
	end

end

-----------------------------------------

function AtrScanDiag_OnAuctionUpdate()

	if not gDiagSession or gDiagSession.mode ~= "getall" then
		return;
	end

	gDiagSession.ailuCount = (gDiagSession.ailuCount or 0) + 1;
	gDiagSession.lastAiluTime = GetTime();
	local n = gDiagSession.ailuCount;
	if n == 1 then
		AtrScanDiag_LogEvent("AILU_FIRST", "server signaled list update");
	else
		AtrScanDiag_LogEvent("AILU", "n=" .. n);
	end

end

-----------------------------------------

function AtrScanDiag_OnTick(note)

	if not gDiagSession or gDiagSession.mode ~= "getall" then
		return;
	end

	local now = GetTime();
	if (now - (gDiagSession.lastTickLog or 0)) < TICK_LOG_INTERVAL then
		return;
	end
	gDiagSession.lastTickLog = now;

	if (not note and gAtr_FullScanWaitFrame and (gDiagSession.ailuCount or 0) < 1) then
		note = string.format("waiting AILU %.1fs", gAtr_FullScanWaitFrame.noAiluElapsed or 0);
	elseif (not note and gAtr_FullScanWaitFrame and gAtr_FullScanWaitFrame.settleDelay and gAtr_FullScanWaitFrame.settleDelay > 0) then
		note = string.format("settle %.1fs ailu=%d", gAtr_FullScanWaitFrame.settleDelay, gDiagSession.ailuCount or 0);
	end

	AtrScanDiag_LogEvent("TICK", note or ("phase=" .. (gDiagSession.phase or "?")));

end

-----------------------------------------

function AtrScanDiag_ProbeCounts(label)

	local batch, total, err = DiagAuctionCounts();
	if err then
		AtrScanDiag_LogEvent("PROBE_ERR", (label or "probe") .. " err=" .. tostring(err));
		return nil, nil;
	end
	if gDiagSession then
		gDiagSession.batch = batch;
		gDiagSession.total = total;
		if batch > (gDiagSession.maxBatch or 0) then
			gDiagSession.maxBatch = batch;
		end
	end
	AtrScanDiag_LogEvent("PROBE", (label or "probe") .. string.format(" batch=%d total=%d", batch, total));
	return batch, total;

end

function AtrScanDiag_GetLastTotals()

	if (gDiagSession) then
		return gDiagSession.batch, gDiagSession.total;
	end

	return nil, nil;

end

function AtrScanDiag_AiluQuietSeconds()

	if not gDiagSession or not gDiagSession.lastAiluTime then
		return nil;
	end
	return GetTime() - gDiagSession.lastAiluTime;

end

-----------------------------------------

function AtrScanDiag_LogLine(event, detail)

	local d = AUCTIONATOR_SCAN_DIAG;
	d.logLines = d.logLines or {};

	local batch, total = DiagAuctionCountsSafe();
	local canQuery, canGetAll = DiagCanQuery();
	local mode = gDiagSession and gDiagSession.mode or "-";
	local phase = gDiagSession and gDiagSession.phase or "-";

	local line = string.format("%s | %s | event=%s | mode=%s | phase=%s | batch=%d | total=%d | mem=%dKB | canQuery=%s | canGetAll=%s%s",
		DiagTimestamp(), DiagRealmKey(), event, mode, phase,
		batch, total, DiagMemKB(), tostring(canQuery), tostring(canGetAll),
		detail and (" | " .. detail) or "");

	tinsert(d.logLines, line);
	while #d.logLines > MAX_LOG_LINES do
		tremove(d.logLines, 1);
	end

	d.lastLine = line;
	d.lastUpdate = time();

	if gDiagVerbose then
		DiagPrint("[AtrScanDiag] " .. line);
	end

end

-----------------------------------------

function AtrScanDiag_Init()

	local d = AUCTIONATOR_SCAN_DIAG;
	d.__version = 2;
	d.history = d.history or {};
	d.failSamples = d.failSamples or {};
	d.stats = d.stats or {};
	d.logLines = d.logLines or {};

	local key = DiagRealmKey();
	if not d.stats[key] then
		d.stats[key] = { getAllOk = 0, getAllFail = 0, classOk = 0, lastOkCount = 0, lastFailPhase = "" };
	end

	if d.interrupted then
		local i = d.interrupted;
		if d.lastError then
			DiagPrint("|cffff0000[AtrScanDiag last Lua error]|r " .. d.lastError);
		end
		local msg = string.format("INTERRUPTED phase=%s mode=%s batch=%d total=%d maxBatch=%s mem=%dKB ailu=%s elapsed=%.1fs lastEvent=%s at=%s %s",
			tostring(i.phase), tostring(i.mode), i.batch or 0, i.total or 0,
			tostring(i.maxBatch or "?"), i.mem or 0, tostring(i.ailuCount or "?"),
			i.elapsed or 0, tostring(i.lastEvent or "?"),
			tostring(i.time or "?"), tostring(i.note or ""));
		DiagPrint("|cffff9900[AtrScanDiag]|r " .. msg);
		if i.eventTrail and #i.eventTrail > 0 then
			DiagPrint("|cffff9900[AtrScanDiag]|r last events:");
			local startIdx = math.max(1, #i.eventTrail - 9);
			for idx = startIdx, #i.eventTrail do
				local ev = i.eventTrail[idx];
				DiagPrint(string.format("  %.2fs %s %s mem=%d ailu=%d",
					ev.t or 0, ev.e or "?", ev.d or "", ev.mem or 0, ev.ailu or 0));
			end
		end
		if d.snapshots and #d.snapshots > 0 then
			DiagPrint("|cffff9900[AtrScanDiag]|r snapshots (WTF):");
			local snapStart = math.max(1, #d.snapshots - 9);
			for idx = snapStart, #d.snapshots do
				DiagPrint("  " .. d.snapshots[idx]);
			end
		end
		if i.mode == "getall" then
			local stats = d.stats[key];
			stats.getAllFail = (stats.getAllFail or 0) + 1;
			stats.lastFailPhase = i.phase or "?";
			tinsert(d.failSamples, 1, {
				phase = i.phase,
				batch = i.batch,
				total = i.total,
				maxBatch = i.maxBatch,
				mem = i.mem,
				clock = i.time,
				hour = tonumber(date("%H")),
				note = "crash/disconnect",
			});
			while #d.failSamples > MAX_FAIL_SAMPLES do
				tremove(d.failSamples);
			end
		end
		AtrScanDiag_LogLine("CRASH_RECOVERY", msg);
		d.interrupted = nil;
	end

end

-----------------------------------------

function AtrScanDiag_SetVerbose(on)
	gDiagVerbose = on and true or false;
	AtrScanDiag_LogLine("VERBOSE", tostring(gDiagVerbose));
end

-----------------------------------------

function AtrScanDiag_PushHistory(entry)

	local d = AUCTIONATOR_SCAN_DIAG;
	tinsert(d.history, 1, entry);
	while #d.history > MAX_HISTORY do
		tremove(d.history);
	end

end

-----------------------------------------

function AtrScanDiag_PersistInterrupt()

	if not gDiagSession then
		return;
	end

	local batch, total;
	if gDiagSkipAuctionAPI then
		batch = gDiagSession.batch or 0;
		total = gDiagSession.total or 0;
	else
		local err;
		batch, total, err = DiagAuctionCounts();
		if err then
			batch = gDiagSession.batch or 0;
			total = gDiagSession.total or 0;
		else
			gDiagSession.batch = batch;
			gDiagSession.total = total;
			if batch > (gDiagSession.maxBatch or 0) then
				gDiagSession.maxBatch = batch;
			end
		end
	end

	AUCTIONATOR_SCAN_DIAG.interrupted = {
		mode = gDiagSession.mode,
		phase = gDiagSession.phase,
		batch = batch,
		total = total,
		maxBatch = gDiagSession.maxBatch,
		mem = DiagMemKB(),
		time = DiagTimestamp(),
		clock = time(),
		note = gDiagSession.note,
		ailuCount = gDiagSession.ailuCount or 0,
		lastAiluTime = gDiagSession.lastAiluTime,
		lastEvent = gDiagSession.lastEvent,
		elapsed = DiagSessionElapsed(),
		eventTrail = gDiagSession.eventTrail,
	};

end

-----------------------------------------

function AtrScanDiag_Phase(phase, note)

	if not gDiagSession then
		return;
	end

	local now = GetTime();
	local detail = phase .. (note and (" | " .. note) or "");
	if phase == gDiagSession.phase and detail == gDiagSession.lastPhaseDetail
		and (now - gDiagLastPhaseLog) < PHASE_LOG_INTERVAL then
		if note then
			gDiagSession.note = note;
		end
		AtrScanDiag_PersistInterrupt();
		return;
	end

	gDiagSession.phase = phase;
	gDiagSession.phaseTime = time();
	gDiagSession.mem = DiagMemKB();
	gDiagSession.lastPhaseDetail = detail;
	gDiagLastPhaseLog = now;
	if note then
		gDiagSession.note = note;
	end

	if not gDiagSkipAuctionAPI then
		AtrScanDiag_NoteBatchCount();
	end
	AtrScanDiag_PersistInterrupt();
	AtrScanDiag_LogLine("PHASE", detail);

end

-----------------------------------------

function AtrScanDiag_StartSession(mode)

	gDiagSession = {
		mode = mode,
		phase = "START",
		startTime = time(),
		startClock = DiagTimestamp(),
		startClockHi = GetTime(),
		mem = DiagMemKB(),
		ailuCount = 0,
		eventTrail = {},
	};

	AtrScanDiag_LogLine("SESSION_START", "mode=" .. mode);
	AtrScanDiag_Phase("START", "mode=" .. mode);

end

-----------------------------------------

function AtrScanDiag_EndSession(result, note)

	if not gDiagSession then
		return;
	end

	local duration = time() - (gDiagSession.startTime or time());
	local batch, total, err = DiagAuctionCounts();
	if err then
		batch = gDiagSession.batch or 0;
		total = gDiagSession.total or 0;
	end
	local key = DiagRealmKey();
	local stats = AUCTIONATOR_SCAN_DIAG.stats[key];

	local entry = {
		result = result,
		mode = gDiagSession.mode,
		lastPhase = gDiagSession.phase,
		duration = duration,
		batch = batch,
		total = total,
		maxBatch = gDiagSession.maxBatch or batch,
		mem = DiagMemKB(),
		startClock = gDiagSession.startClock,
		endClock = DiagTimestamp(),
		note = note or gDiagSession.note,
		hour = tonumber(date("%H")),
	};

	AtrScanDiag_PushHistory(entry);

	if result == "OK" then
		if gDiagSession.mode == "getall" then
			stats.getAllOk = (stats.getAllOk or 0) + 1;
			stats.lastOkCount = entry.maxBatch or batch;
		else
			stats.classOk = (stats.classOk or 0) + 1;
		end
		AUCTIONATOR_SCAN_DIAG.interrupted = nil;
	else
		if gDiagSession.mode == "getall" then
			stats.getAllFail = (stats.getAllFail or 0) + 1;
			stats.lastFailPhase = gDiagSession.phase or "?";
			tinsert(AUCTIONATOR_SCAN_DIAG.failSamples, 1, {
				phase = gDiagSession.phase,
				batch = batch,
				total = total,
				maxBatch = gDiagSession.maxBatch,
				mem = gDiagSession.mem,
				clock = DiagTimestamp(),
				hour = entry.hour,
				note = note,
			});
			while #AUCTIONATOR_SCAN_DIAG.failSamples > MAX_FAIL_SAMPLES do
				tremove(AUCTIONATOR_SCAN_DIAG.failSamples);
			end
		end
	end

	AtrScanDiag_LogLine("SESSION_END", string.format("result=%s duration=%ds maxBatch=%s %s",
		result, duration, tostring(gDiagSession.maxBatch or batch), note or ""));

	DiagPrint(string.format("|cff00ff00[AtrScanDiag]|r %s | phase=%s | maxBatch=%s | %ds",
		result, tostring(gDiagSession.phase), tostring(gDiagSession.maxBatch or batch), duration));

	gDiagSession = nil;

end

-----------------------------------------

function AtrScanDiag_NoteBatchCount()

	if not gDiagSession then
		return;
	end

	local batch, total, err = DiagAuctionCounts();
	if err then
		AtrScanDiag_LogEvent("PROBE_ERR", "NoteBatchCount err=" .. tostring(err));
		return;
	end
	if batch > (gDiagSession.maxBatch or 0) then
		gDiagSession.maxBatch = batch;
	end
	gDiagSession.batch = batch;
	gDiagSession.total = total;

end

-----------------------------------------

function AtrScanDiag_PreflightGetAll()

	local key = DiagRealmKey();
	local stats = AUCTIONATOR_SCAN_DIAG.stats[key] or {};
	local fails = stats.getAllFail or 0;
	local oks = stats.getAllOk or 0;
	local hour = tonumber(date("%H"));

	local msg = nil;
	local level = "ok";

	if fails >= 3 and oks == 0 then
		msg = ZT("GetAll preflight many fails");
		level = "warn";
	elseif fails > oks * 2 and fails >= 2 then
		msg = ZT("GetAll preflight risky");
		level = "warn";
	end

	if hour >= 18 or hour <= 1 then
		if not msg then
			msg = ZT("GetAll preflight peak hours");
		end
		level = "warn";
	end

	return level, msg, stats;

end

-----------------------------------------

function AtrScanDiag_ShouldBlockGetAll()
	return false, nil;
end

-----------------------------------------

function AtrScanDiag_PrintEventTrail()

	local d = AUCTIONATOR_SCAN_DIAG;
	local trail = (d.interrupted and d.interrupted.eventTrail) or (gDiagSession and gDiagSession.eventTrail);
	if not trail or #trail == 0 then
		DiagPrint("[AtrScanDiag] no event trail");
		return;
	end
	DiagPrint("|cff00ff00=== Event trail ===|r");
	for _, ev in ipairs(trail) do
		DiagPrint(string.format("  %.2fs %-12s %s mem=%d ailu=%d", ev.t or 0, ev.e or "?", ev.d or "", ev.mem or 0, ev.ailu or 0));
	end

end

-----------------------------------------

function AtrScanDiag_PrintReport()

	local d = AUCTIONATOR_SCAN_DIAG;
	local key = DiagRealmKey();
	local stats = d.stats[key] or {};

	DiagPrint("|cff00ff00=== AtrScanDiag (WTF) ===|r");
	DiagPrint("Saved to: WTF/Account/<account>/SavedVariables/Auctionator.lua");
	DiagPrint(string.format("GetAll OK/FAIL: %d / %d", stats.getAllOk or 0, stats.getAllFail or 0));

	for i = math.max(1, #(d.logLines or {}) - 7), #(d.logLines or {}) do
		DiagPrint(d.logLines[i]);
	end

end

-----------------------------------------

function AtrScanDiag_HandleCommand(param1, param2)

	if param1 == "verbose" then
		if param2 == "on" then
			AtrScanDiag_SetVerbose(true);
		elseif param2 == "off" then
			AtrScanDiag_SetVerbose(false);
		else
			AtrScanDiag_SetVerbose(not gDiagVerbose);
		end
		return true;

	elseif param1 == "clear" then
		AUCTIONATOR_SCAN_DIAG = {
			__version = 2, history = {}, failSamples = {}, stats = {}, logLines = {},
		};
		DiagPrint("[AtrScanDiag] WTF log cleared — /reload to save");
		return true;

	elseif param1 == "trail" then
		AtrScanDiag_PrintEventTrail();
		return true;

	elseif param1 == "snapshots" then
		local d = AUCTIONATOR_SCAN_DIAG;
		if not d.snapshots or #d.snapshots == 0 then
			DiagPrint("[AtrScanDiag] no snapshots");
		else
			DiagPrint("|cff00ff00=== Snapshots ===|r");
			for _, snap in ipairs(d.snapshots) do
				DiagPrint(snap);
			end
		end
		return true;

	elseif param1 == nil or param1 == "show" then
		AtrScanDiag_PrintReport();
		return true;
	end

	return false;

end
