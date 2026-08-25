PortOps = PortOps or {}
PortOps.Config = PortOps.Config or {}
PortOps.Config.equipment = {
    types = { CRANE = true, TERMINAL_TRACTOR = true, YARD_HANDLER = true },
    defaults = { availability = 'AVAILABLE' }
}
return PortOps.Config.equipment
