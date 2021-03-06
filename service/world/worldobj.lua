--import module

local global = require "global"
local skynet = require "skynet"
local interactive = require "base.interactive"
local res = require "base.res"
local net = require "base.net"

local gamedefines = import(lualib_path("public.gamedefines"))
local playerobj = import(service_path("playerobj"))
local connectionobj = import(service_path("connectionobj"))
local offline = import(service_path("offline.init"))
local timeop = import(lualib_path("base.timeop"))
local tableop = import(lualib_path("base.tableop"))
local datactrl = import(lualib_path("public.datactrl"))

function NewWorldMgr(...)
    local o = CWorldMgr:New(...)
    return o
end

CWorldMgr = {}
CWorldMgr.__index = CWorldMgr
inherit(CWorldMgr, datactrl.CDataCtrl)

function CWorldMgr:New()
    local o = super(CWorldMgr).New(self)
    o.m_mOnlinePlayers = {}
    o.m_mLoginPlayers = {}
    o.m_mLogoutPlayers = {}

    o.m_mOfflineROs = {}
    o.m_mOfflineRWs = {}

    o.m_mConnections = {}

    o.m_mPlayerPropChange = {}
    return o
end

function CWorldMgr:Release()
    for _, v in ipairs({self.m_mOnlinePlayers, self.m_mLoginPlayers, self.m_mLogoutPlayers}) do
        for _, v2 in pairs(v) do
            v:Release()
        end
    end
    for _, v in pairs(self.m_mConnections) do
        v:Release()
    end
    self.m_mOnlinePlayers = {}
    self.m_mLoginPlayers = {}
    self.m_mLogoutPlayers = {}
    self.m_mConnections = {}
    self.m_mOfflineROs = {}
    self.m_mOfflineRWs = {}
    super(CWorldMgr).Release(self)
end

function CWorldMgr:Load(m)
    m = m or {}
    self.m_iServerGrade = m.server_grade or 40
    self.m_iOpenDays = m.open_days or 0

    self:Dirty()
end

function CWorldMgr:Save()
    local m = {}
    m.server_grade = self.m_iServerGrade
    m.open_days = self.m_iOpenDays
    return m
end

function CWorldMgr:SetServerGrade(i)
    self.m_iServerGrade = i
    self:Dirty()
end

function CWorldMgr:GetServerGrade()
    return self.m_iServerGrade
end

function CWorldMgr:SetOpenDays(i)
    self.m_iOpenDays = i
    self:Dirty()
end

function CWorldMgr:GetOpenDays()
    return self.m_iOpenDays
end

function CWorldMgr:OnLogin(oPlayer, bReEnter)
    oPlayer:Send("GS2CServerGradeInfo", {
        server_grade = self:GetServerGrade(),
        days = self:GetUpGradeLeftDays(),
    })
end

function CWorldMgr:GetConnection(iHandle)
    return self.m_mConnections[iHandle]
end

function CWorldMgr:DelConnection(iHandle)
    local oConnection = self.m_mConnections[iHandle]
    if oConnection then
        self.m_mConnections[iHandle] = nil
        oConnection:Disconnected()
        oConnection:Release()
    end
end

function CWorldMgr:FindPlayerAnywayByPid(pid)
    local obj
    for _, m in ipairs({self.m_mLoginPlayers, self.m_mOnlinePlayers, self.m_mLogoutPlayers}) do
        obj = m[pid]
        if obj then
            break
        end
    end
    return obj
end

function CWorldMgr:FindPlayerAnywayByFd(iHandle)
    local oConnection = self:GetConnection(iHandle)
    if oConnection then
        local iPid = oConnection:GetOwnerPid()
        return self:FindPlayerAnywayByPid(iPid)
    end
end

function CWorldMgr:GetOnlinePlayerByFd(iHandle)
    local oConnection = self:GetConnection(iHandle)
    if oConnection then
        local iPid = oConnection:GetOwnerPid()
        return self.m_mOnlinePlayers[iPid]
    end
end

function CWorldMgr:GetOnlinePlayerByPid(iPid)
    return self.m_mOnlinePlayers[iPid]
end

function CWorldMgr:KickConnection(iHandle)
    local oConnection = self:GetConnection(iHandle)
    if oConnection then
        self:DelConnection(iHandle)
        skynet.send(oConnection.m_iGateAddr, "text", "kick", oConnection.m_iHandle)
    end
end

function CWorldMgr:Logout(iPid)
    local oPlayer = self.m_mLoginPlayers[iPid]
    if oPlayer then
        self.m_mLoginPlayers[iPid] = nil
        return
    end
    oPlayer = self.m_mOnlinePlayers[iPid]
    if oPlayer then
        self.m_mOnlinePlayers[iPid] = nil
        self.m_mLogoutPlayers[iPid] = oPlayer
        if oPlayer then
            oPlayer:OnLogout()
        end        
        self.m_mLogoutPlayers[iPid] = nil
        oPlayer:Release()
    end
end

function CWorldMgr:Login(mRecord, mConn, mRole)
    local pid = mRole.pid
    if self.m_mLoginPlayers[pid] then
        interactive.Send(mRecord.source, "login", "LoginResult", {pid = pid, handle = mConn.handle, errcode = gamedefines.ERRCODE.in_login})
        return
    end
    if self.m_mLogoutPlayers[pid] then
        interactive.Send(mRecord.source, "login", "LoginResult", {pid = pid, handle = mConn.handle, errcode = gamedefines.ERRCODE.in_logout})
        return
    end

    local oPlayer = self.m_mOnlinePlayers[pid]
    if oPlayer then
        local oOldConn = oPlayer:GetConn()
        if oOldConn and oOldConn.m_iHandle ~= mConn.handle then
            self:KickConnection(oOldConn.m_iHandle)
        end

        local oConnection = connectionobj.NewConnection(mConn, pid)
        oConnection:Forward()
        self.m_mConnections[mConn.handle] = oConnection

        oPlayer:OnLogin(true)
        interactive.Send(mRecord.source, "login", "LoginResult", {pid = pid, handle = mConn.handle, errcode = gamedefines.ERRCODE.ok})
        return
    else
        local oPlayer = playerobj.NewPlayer(mConn, mRole)
        self.m_mLoginPlayers[oPlayer:GetPid()] = oPlayer

        local oConnection = connectionobj.NewConnection(mConn, pid)
        oConnection:Forward()
        self.m_mConnections[mConn.handle] = oConnection

        interactive.Request(".gamedb", "playerdb", "GetPlayer", {pid = pid}, function (mRecord, mData)
            if not self:IsRelease() then
                self:_LoginRole1(mRecord, mData)
            end
        end)
        return
    end
end

function CWorldMgr:_LoginRole1(mRecord, mData)
    local pid = mData.pid
    local m = mData.data
    local oPlayer = self.m_mLoginPlayers[pid]
    if not oPlayer then
        return
    end

    if not m then
        self.m_mLoginPlayers[pid] = nil
        local oConn = oPlayer:GetConn()
        if oConn then
            interactive.Send(".login", "login", "LoginResult", {pid = pid, handle = oConn.m_iHandle, errcode = gamedefines.ERRCODE.not_exist_player})
        end
        return
    end

    interactive.Request(".gamedb", "playerdb", "LoadPlayerBase", {pid = pid}, function (mRecord, mData)
        if not self:IsRelease() then
            self:_LoginRole2(mRecord, mData)
        end
    end)
end

function CWorldMgr:_LoginRole2(mRecord, mData)
    local pid = mData.pid
    local m = mData.data
    local oPlayer = self.m_mLoginPlayers[pid]
    if not oPlayer then
        return
    end

    oPlayer.m_oBaseCtrl:Load(m)

    interactive.Request(".gamedb", "playerdb", "LoadPlayerActive", {pid = pid}, function (mRecord, mData)
        if not self:IsRelease() then
            self:_LoginRole3(mRecord, mData)
        end
    end)
end

function CWorldMgr:_LoginRole3(mRecord, mData)
    local pid = mData.pid
    local m = mData.data
    local oPlayer = self.m_mLoginPlayers[pid]
    if not oPlayer then
        return
    end

    oPlayer.m_oActiveCtrl:Load(m)

    interactive.Request(".gamedb", "playerdb", "LoadPlayerItem", {pid = pid}, function (mRecord, mData)
        if not self:IsRelease() then
            self:_LoginRole4(mRecord, mData)
        end
    end)
  
end

function CWorldMgr:_LoginRole4(mRecord,mData)
    local pid = mData.pid
    local m = mData.data
    local oPlayer = self.m_mLoginPlayers[pid]
    if not oPlayer then
        return
    end
    oPlayer.m_oItemCtrl:Load(m)
    interactive.Request(".gamedb", "playerdb", "LoadPlayerTask", {pid = pid}, function (mRecord, mData)
        if not self:IsRelease() then
            self:_LoginRole5(mRecord, mData)
        end
    end)
end

function CWorldMgr:_LoginRole5(mRecord,mData)
     local pid = mData.pid
    local m = mData.data
    local oPlayer = self.m_mLoginPlayers[pid]
    if not oPlayer then
        return
    end
    oPlayer.m_oTaskCtrl:Load(m)
    interactive.Request(".gamedb", "playerdb", "LoadPlayerWareHouse", {pid = pid}, function (mRecord, mData)
        if not self:IsRelease() then
            self:_LoginRole6(mRecord, mData)
        end
    end)
end

function CWorldMgr:_LoginRole6(mRecord,mData)
    local pid = mData.pid
    local m = mData.data
    local oPlayer = self.m_mLoginPlayers[pid]
    if not oPlayer then
        return
    end
    oPlayer.m_oWHCtrl:Load(m)
    
     interactive.Request(".gamedb", "playerdb", "LoadPlayerTimeInfo", {pid = pid}, function (mRecord, mData)
        if not self:IsRelease() then
            self:_LoginRole7(mRecord, mData)
        end
    end)
end

function CWorldMgr:_LoginRole7(mRecord,mData)
    local pid = mData.pid
    local m = mData.data
    local oPlayer = self.m_mLoginPlayers[pid]
    if not oPlayer then
        return
    end
    oPlayer.m_oTimeCtrl:Load(m)

    local mFunc = {"LoadRO","LoadRW"}
    local mLoad = {}
    for _,sFunc in pairs(mFunc) do
        if self[sFunc] then
            self[sFunc](self,pid,function(oRO)
                mLoad[sFunc] = 1
                if tableop.table_count(mLoad) >=2 then
                    self:LoadEnd(pid)
                end
            end)
        end
    end
end

function CWorldMgr:LoadEnd(pid)
    local oPlayer = self.m_mLoginPlayers[pid]
    if not oPlayer then
        return
    end
    self.m_mLoginPlayers[pid] = nil
    self.m_mOnlinePlayers[pid] = oPlayer

     oPlayer:OnLogin(false)
    local oConn = oPlayer:GetConn()
    if oConn then
        interactive.Send(".login", "login", "LoginResult", {pid = pid, handle = oConn.m_iHandle, errcode = gamedefines.ERRCODE.ok})
    end
end

function CWorldMgr:LoadRO(pid,func)
    local oRO = self.m_mOfflineROs[pid]
    if oRO then
        if func then
            if oRO:IsLoading() then
                oRO:AddWaitFunc(func)
            else
                func(oRO)
                oRO.m_LastTime = timeop.get_time()
            end
        end
    else
        local oRO = offline.NewROCtrl(pid)
        self.m_mOfflineROs[pid] = oRO
        if func then
          oRO:AddWaitFunc(func)
        end
        interactive.Request(".gamedb","offlinedb","LoadOfflineRO",{pid=pid},function (mRecord,mData)
            local oRO = self.m_mOfflineROs[pid]
            if not oRO then
                oRO = offline.NewROCtrl(pid)
                self.m_mOfflineROs[pid] = oRO
            end
            oRO:Load(mData)
            oRO.m_bLoading = false
            oRO:WakeUpFunc()
        end)
    end
end

function CWorldMgr:LoadRW(pid,func)
    local oRW = self.m_mOfflineRWs[pid]
    if oRW then
        if func then
            if oRW:IsLoading() then
                oRW:AddWaitFunc(func)
            else
                func(oRW)
                oRW.m_LastTime = timeop.get_time()
            end
        end
    else
        local oRW = offline.NewRWCtrl(pid)
        self.m_mOfflineRWs[pid] = oRW
        if func then
         oRW:AddWaitFunc(func)
        end
        interactive.Request(".gamedb","offlinedb","LoadOfflineRW",{pid=pid},function (mRecord,mData)
            local oRW = self.m_mOfflineRWs[pid]
            if not oRW then
                oRW = offline.NewRWCtrl(pid)
                self.m_mOfflineRWs[pid] = oRW
            end
            oRW:Load(mData)
            oRW.m_bLoading = false
            oRW:WakeUpFunc()
        end)
    end
end

function CWorldMgr:CleanRO(pid)
    self.m_mOfflineROs[pid] = nil
end

function CWorldMgr:CleanRW(pid)
    self.m_mOfflineRWs[pid] = nil
end

function CWorldMgr:GetRO(pid)
    local oRO = self.m_mOfflineROs[pid]
    return oRO
end

function CWorldMgr:GetRW(pid)
    local oRW = self.m_mOfflineRWs[pid]
    return oRW
end

function CWorldMgr:Schedule()
    local f1
    f1 = function ()
        self:DelTimeCb("_CheckSaveDb")
        self:AddTimeCb("_CheckSaveDb", 5*60*1000, f1)
        self:_CheckSaveDb()
    end
    f1()

    local f2
    f2 = function ()
        self:DelTimeCb("NewHour")
        self:AddTimeCb("NewHour", 60*60*1000, f2)
        self:NewHour()
    end
    local tbl = timeop.get_hourtime({factor=1,hour=1})
    local iSecs = tbl.time - timeop.get_time()
    if iSecs <= 0 then
        self:NewHour()
    else
        self:DelTimeCb("NewHour")
        self:AddTimeCb("NewHour", iSecs * 1000, f2)
    end
end

function CWorldMgr:_CheckSaveDb()
    assert(not self:IsRelease(), "_CheckSaveDb fail")
    self:SaveDb()
end

function CWorldMgr:SaveDb()
    if self:IsDirty() then
        local mData = self:Save()
        interactive.Send(".gamedb", "worlddb", "SaveWorld", {server_id = MY_SERVER_ID, data = mData})
        self:UnDirty()
    end
end

function CWorldMgr:CheckUpGrade()
    local lServerGrade = res["daobiao"]["servergrade"]

    local iTargetGrade = self:GetServerGrade()
    if iTargetGrade >= gamedefines.SERVER_GRADE_LIMIT then
        return
    end

    for _, v in ipairs(lServerGrade) do
        if self:GetOpenDays() < v.days then
            break
        end
        if v.server_grade > iTargetGrade then
            iTargetGrade = v.server_grade
        end
    end
    if iTargetGrade ~= self:GetServerGrade() then
        self:SetServerGrade(iTargetGrade)
        local iLeftDays = self:GetUpGradeLeftDays()

        local sNetData = net.PackData("GS2CServerGradeInfo", {
            server_grade = iTargetGrade,
            days = iLeftDays,
        })
        for _, o in pairs(self.m_mOnlinePlayers) do
            o:SendRaw(sNetData)
        end
    end
end

function CWorldMgr:GetUpGradeLeftDays()
    local lServerGrade = res["daobiao"]["servergrade"]
    local iRet = 0
    local iOpenDays = self.m_iOpenDays
    for _, v in ipairs(lServerGrade) do
        if v.days > iOpenDays then
            iRet = v.days - iOpenDays
            break
        end
    end
    return iRet
end

function CWorldMgr:NewHour()
    local tbl = timeop.get_hourtime({hour=0})
    local date = tbl.date
    local iDay = date.day
    local iHour = date.hour

    if iHour == 0 then
        self:SetOpenDays(self:GetOpenDays() + 1)
        self:CheckUpGrade()
        self:NewDay()
    end
end

function CWorldMgr:NewDay()
end

function CWorldMgr:SetPlayerPropChange(iPid, l)
    local mNow = self.m_mPlayerPropChange[iPid]
    if not mNow then
        mNow = {}
        self.m_mPlayerPropChange[iPid] = mNow
    end
    for _, v in ipairs(l) do
        mNow[v] = true
    end
end

function CWorldMgr:WorldDispatchFinishHook()
    if next(self.m_mPlayerPropChange) then
        local mPlayerPropChange = self.m_mPlayerPropChange
        for k, v in pairs(mPlayerPropChange) do
            local oPlayer = self:GetOnlinePlayerByPid(k)
            if oPlayer and next(v) then
                oPlayer:ClientPropChange(v)
            end
        end
        self.m_mPlayerPropChange = {}
    end
end
