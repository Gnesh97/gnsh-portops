PortOps = PortOps or {}; PortOps.Client = PortOps.Client or {}
local Controller={}; Controller.__index=Controller
function Controller.new(options) options=options or {}; return setmetatable({rig=options.rig,maxAcceleration=options.maxAcceleration or 8,velocity={gantry=0,trolley=0,spreader=0,yaw=0}},Controller) end
function Controller:step(input,dt)
    dt=math.max(0,math.min(tonumber(dt) or 0,0.1)); input=input or {}; local state=self.rig:getState(); local next={}
    for _,axis in ipairs({'gantry','trolley','spreader','yaw'}) do local target=math.max(-1,math.min(1,tonumber(input[axis]) or 0)); local delta=target-self.velocity[axis]; local maxDelta=self.maxAcceleration*dt; if delta>maxDelta then delta=maxDelta elseif delta< -maxDelta then delta=-maxDelta end; self.velocity[axis]=self.velocity[axis]+delta; next[axis]=state[axis]+self.velocity[axis]*dt end
    self.rig:setState(next); return self.rig:getState()
end
PortOps.Client.CraneController=Controller; return Controller
