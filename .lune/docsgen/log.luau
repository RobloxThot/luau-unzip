local stdio = require("@lune/stdio")

local base = stdio.style("bold")

local STYLE_INFO = base .. `{stdio.color("green")}info{stdio.color("reset")}:`
local STYLE_WARN = base .. `{stdio.color("yellow")}warn{stdio.color("reset")}:`
local STYLE_ERROR = base .. `{stdio.color("red")}error{stdio.color("reset")}:`

export type LogType = "info" | "warn" | "error"
local styleMappings: { [LogType]: string } = {
  info = STYLE_INFO,
  warn = STYLE_WARN,
  error = STYLE_ERROR,
}

return {
  styles = styleMappings,
  log = function<T...>(type: LogType, ...: T...): ()
    local writer: (string) -> () = if type == "info" then stdio.write else stdio.ewrite
    local fmtMsg = stdio.format(styleMappings[type], ...) 

    return writer(fmtMsg .. "\n")
  end
}
