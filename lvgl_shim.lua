-- Band Face Viewer: a small LVGL + dataman stand-in so watchface main.lua files run
-- in the browser (fengari, Lua 5.3). Mirrors the luavgl API used on the band.
-- Anything not emulated logs a warning instead of crashing.
local js = require "js"
local H = js.global.__band
local floor, max, min = math.floor, math.max, math.min
local SW, SH = H.screenW or 336, H.screenH or 480 -- the device picked in the viewer

local roots, timers, anims, subs = {}, {}, {}, {}
local warned = {}
local function warn(msg)
  if not warned[msg] then warned[msg] = true; H:log("warn", msg) end
end
local function safe(fn, ...)
  local ok, err = xpcall(fn, debug.traceback, ...)
  if not ok then H:log("error", tostring(err)) end
  return ok, err
end

print = function(...)
  local t = table.pack(...)
  for i = 1, t.n do t[i] = tostring(t[i]) end
  H:log("print", table.concat(t, "\t"))
end

-- ---------------------------------------------------------------- constants
local ALIGN = { DEFAULT = 0, TOP_LEFT = 1, TOP_MID = 2, TOP_RIGHT = 3, BOTTOM_LEFT = 4,
  BOTTOM_MID = 5, BOTTOM_RIGHT = 6, LEFT_MID = 7, RIGHT_MID = 8, CENTER = 9 }
local EV = { ALL = 0, PRESSED = 1, PRESSING = 2, PRESS_LOST = 3, SHORT_CLICKED = 4,
  LONG_PRESSED = 5, LONG_PRESSED_REPEAT = 6, CLICKED = 7, RELEASED = 8, GESTURE = 13,
  VALUE_CHANGED = 28, FOCUSED = 14, DEFOCUSED = 15 }
local FLAG = {}
for _, n in ipairs { "HIDDEN", "CLICKABLE", "SCROLLABLE", "EVENT_BUBBLE", "GESTURE_BUBBLE",
  "CLICK_FOCUSABLE", "CHECKABLE", "SCROLL_ELASTIC", "SCROLL_MOMENTUM", "PRESS_LOCK",
  "OVERFLOW_VISIBLE", "IGNORE_LAYOUT", "FLOATING", "ADV_HITTEST", "SNAPPABLE", "SCROLL_ON_FOCUS" } do
  FLAG[n] = n
end
setmetatable(FLAG, { __index = function(_, k) warn("lvgl.FLAG." .. k .. " not emulated"); return k end })

local function color(c)
  if type(c) == "string" then return tonumber((c:gsub("^#", ""):gsub("^0x", "")), 16) or 0 end
  if type(c) == "table" then return c.hex or 0 end
  return c or 0
end
local function opa(v, default)
  if v == nil then return default end
  return max(0, min(255, v))
end
local function resolve(v, parent)
  if type(v) == "table" and v.pct then return parent * v.pct / 100 end
  if type(v) == "number" then return v end
  return nil
end

-- ---------------------------------------------------------------- objects
local M = {}
local O = { __index = function(_, k)
  local m = M[k]
  if m then return m end
  warn("obj:" .. tostring(k) .. "() not emulated (ignored)")
  return function() end
end }

local DEFAULT_CLICK = { obj = true, label = false, img = false }
local function new(kind, parent, props)
  if parent ~= nil and getmetatable(parent) ~= O then parent, props = nil, parent end
  -- every internal field is set here so a missing one never hits the "not emulated" __index
  local o = setmetatable({ kind = kind, p = { x = 0, y = 0 }, kids = {}, parent = parent or false,
    flags = { CLICKABLE = DEFAULT_CLICK[kind] }, ev = {}, rect = false, dead = false }, O)
  table.insert(parent and parent.kids or roots, o)
  if props then o:set(props) end
  return o
end

function M:set(q)
  local p = self.p
  for k, v in pairs(q) do
    if k == "align" then
      if type(v) == "table" then p.align, p.x, p.y = v.type or 0, v.x_ofs or 0, v.y_ofs or 0
      else p.align = v end
    elseif k == "src" then
      p.src = v
      if type(v) == "string" and not H:hasImg(v) then warn("image not found in .face: " .. v) end
    elseif k == "flex_flow" or k == "flex_main_place" or k == "layout" or k == "grid_dsc_array" then
      warn(k .. " (flex/grid layout) not emulated: children use their own x/y")
    else
      p[k] = v
    end
  end
end
function M:add_flag(f) self.flags[f] = true end
function M:clear_flag(f) self.flags[f] = false end
function M:has_flag(f) return self.flags[f] == true end
function M:onevent(code, fn) table.insert(self.ev, { code = code, fn = fn }) end
function M:onClicked(fn) self:onevent(EV.CLICKED, fn) end
function M:onPressed(fn) self:onevent(EV.PRESSED, fn) end
function M:onShortClicked(fn) self:onevent(EV.SHORT_CLICKED, fn) end
function M:Object(p) return new("obj", self, p) end
function M:Label(p) return new("label", self, p) end
function M:Image(p) return new("img", self, p) end
function M:get_parent() return self.parent or nil end
function M:get_child_cnt() return #self.kids end
function M:get_child(i) return self.kids[(i or 0) + 1] end
function M:invalidate() end
function M:scroll_to() end
function M:update_layout() end
local function detach(o)
  local list = o.parent and o.parent.kids or roots
  for i, k in ipairs(list) do if k == o then table.remove(list, i); return end end
end
function M:delete() detach(self); self.dead = true end
function M:clean() for _, k in ipairs(self.kids) do k.dead = true end; self.kids = {} end
function M:set_parent(par) detach(self); self.parent = par or false; table.insert(par and par.kids or roots, self) end
function M:move_foreground() detach(self); table.insert(self.parent and self.parent.kids or roots, self) end
function M:move_background() detach(self); table.insert(self.parent and self.parent.kids or roots, 1, self) end
function M:get_coords()
  local r = self.rect or { 0, 0, 0, 0 }
  return { x1 = r[1], y1 = r[2], x2 = r[1] + r[3] - 1, y2 = r[2] + r[4] - 1 }
end
function M:get_pos() local r = self.rect or { 0, 0 }; return r[1], r[2] end
function M:get_size() local r = self.rect or { 0, 0, 0, 0 }; return r[3], r[4] end
function M:Anim(p)
  local a = { obj = self, p = {}, t0 = nil, running = false }
  function a:set(q) for k, v in pairs(q) do self.p[k] = v end end
  function a:start() self.t0, self.running = nil, true end
  function a:stop() self.running = false end
  function a:delete() self.running = false end
  a:set(p or {})
  if a.p.run then a:start() end
  anims[#anims + 1] = a
  return a
end

-- ---------------------------------------------------------------- text
local mcache = {}
local function measure(s, size, weight)
  local key = s .. "\0" .. size .. weight
  local w = mcache[key]
  if not w then w = H:measure(s, size, weight); mcache[key] = w end
  return w
end
local function font_of(o)
  local f = o.p.text_font
  if type(f) == "table" then return f.size or 20, f.weight or 400 end
  return 20, 400
end
local function lines_of(o, wrap_w)
  local text = tostring(o.p.text or "")
  local size, weight = font_of(o)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if wrap_w and measure(line, size, weight) > wrap_w then
      local cur = ""
      for word in line:gmatch("%S+") do
        local try = cur == "" and word or cur .. " " .. word
        if cur ~= "" and measure(try, size, weight) > wrap_w then out[#out + 1] = cur; cur = word
        else cur = try end
      end
      out[#out + 1] = cur
    else
      out[#out + 1] = line
    end
  end
  return out, size, weight
end

-- ---------------------------------------------------------------- layout + draw
local function size_of(o, pw, ph)
  local p = o.p
  local w, h = resolve(p.w, pw), resolve(p.h, ph)
  if o.kind == "img" then
    if not (w and h) then
      local iw, ih = H:imgW(p.src or ""), H:imgH(p.src or "")
      w, h = w or iw, h or ih
    end
  elseif o.kind == "label" then
    if not (w and h) then
      local lines, size, weight = lines_of(o, w)
      local tw = 0
      for _, l in ipairs(lines) do tw = max(tw, measure(l, size, weight)) end
      w, h = w or math.ceil(tw), h or floor(#lines * size * 1.2 + 0.5)
    end
  else
    w, h = w or 100, h or 50 -- ponytail: lvgl's default obj size, content-sizing not emulated
  end
  return w, h
end

local function place(o, px, py, pw, ph)
  local w, h = size_of(o, pw, ph)
  local a = o.p.align or 0
  local x, y = resolve(o.p.x, pw) or 0, resolve(o.p.y, ph) or 0
  local ax, ay = 0, 0
  if a == 2 or a == 5 or a == 9 then ax = (pw - w) / 2 elseif a == 3 or a == 6 or a == 8 then ax = pw - w end
  if a == 7 or a == 8 or a == 9 then ay = (ph - h) / 2 elseif a == 4 or a == 5 or a == 6 then ay = ph - h end
  return floor(px + ax + x), floor(py + ay + y), w, h
end

local stats = { objects = 0 }
local touch_map = false
local marks = {}

local function draw(o, px, py, pw, ph, inherited_opa)
  if o.flags.HIDDEN then o.rect = false; return end
  local x, y, w, h = place(o, px, py, pw, ph)
  o.rect = { x, y, w, h }
  stats.objects = stats.objects + 1
  local p = o.p
  local alpha = (opa(p.opa, 255) / 255) * inherited_opa
  if o.kind == "obj" then
    local bg = opa(p.bg_opa, 0)
    local bw = p.border_width or 0
    if bg > 0 or bw > 0 then
      H:rect(x, y, w, h, color(p.bg_color or 0xFFFFFF), bg / 255 * alpha, p.radius or 0,
        bw, color(p.border_color or 0x000000), opa(p.border_opa, 255) / 255 * alpha)
    end
  elseif o.kind == "label" then
    local lines, size, weight = lines_of(o, resolve(p.w, pw))
    local ta = p.text_align or 0
    H:text(table.concat(lines, "\n"), x, y, w, color(p.text_color or 0xFFFFFF), size, weight,
      ta == 2 and "center" or ta == 3 and "right" or "left", opa(p.text_opa, 255) / 255 * alpha)
  elseif o.kind == "img" and p.src then
    H:img(p.src, x, y, w, h, p.angle or 0, p.zoom or 256, opa(p.img_opa, 255) / 255 * alpha,
      p.img_recolor or 0, opa(p.img_recolor_opa, 0) / 255)
  end
  if touch_map and o.flags.CLICKABLE then marks[#marks + 1] = o.rect end
  if #o.kids > 0 then
    local pad = p.pad_all or 0
    local cl, ct = p.pad_left or pad, p.pad_top or pad
    local cw, ch = w - cl - (p.pad_right or pad), h - ct - (p.pad_bottom or pad)
    local clip = not o.flags.OVERFLOW_VISIBLE
    if clip then H:clip(x, y, w, h, p.radius or 0) end
    for _, k in ipairs(o.kids) do draw(k, x + cl, y + ct, cw, ch, alpha) end
    if clip then H:unclip() end
  end
end

-- ---------------------------------------------------------------- input
local function hit(list, px, py)
  for i = #list, 1, -1 do
    local o = list[i]
    local r = o.rect
    if r and not o.flags.HIDDEN and px >= r[1] and py >= r[2] and px < r[1] + r[3] and py < r[2] + r[4] then
      local t = hit(o.kids, px, py)
      if t then return t end
      if o.flags.CLICKABLE then return o end
    end
  end
end

local function fire(o, code)
  while o do
    for _, h in ipairs(o.ev) do
      if h.code == EV.ALL or h.code == code then safe(h.fn, o, code) end
    end
    if not o.flags.EVENT_BUBBLE then return end
    o = o.parent
  end
end

local point = { x = 0, y = 0 }
local press -- { target, t0, long }

local function describe(o)
  local s = o.kind
  if o.kind == "img" and o.p.src then s = s .. " " .. tostring(o.p.src):match("[^/]*$") end
  if o.kind == "label" and o.p.text then s = s .. ' "' .. tostring(o.p.text):sub(1, 16) .. '"' end
  if not o.parent then s = s .. " (root)" end
  return s
end

H.pointer = function(_, kind, x, y, now)
  point.x, point.y = floor(x), floor(y)
  if kind == "down" then
    local t = hit(roots, point.x, point.y)
    press = { target = t, t0 = now, long = false }
    if t then fire(t, EV.PRESSED) end
  elseif kind == "move" then
    if press and press.target then fire(press.target, EV.PRESSING) end
  elseif kind == "up" and press then
    local t = press.target
    if t then
      fire(t, EV.RELEASED)
      if not press.long then fire(t, EV.SHORT_CLICKED) end
      fire(t, EV.CLICKED)
    end
    press = nil
  end
end

local function check_long(now)
  if press and not press.long and now - press.t0 >= 400 then
    press.long = true
    local t = press.target
    if t then
      fire(t, EV.LONG_PRESSED)
      H:longpress(false, describe(t))
    else
      H:longpress(true, "")
    end
  end
end

-- share of the screen where a long-press reaches the band (nothing clickable)
H.freeArea = function()
  local free, n = 0, 0
  for gy = 20, SH - 20, 40 do
    for gx = 20, SW - 20, 40 do
      n = n + 1
      if not hit(roots, gx, gy) then free = free + 1 end
    end
  end
  return floor(free * 100 / n)
end

-- ---------------------------------------------------------------- timers / anims
local function timer_new(p)
  local t = { period = p.period or 500, cb = p.cb, paused = p.paused == true, last = nil,
    repeat_count = p.repeat_count or -1 }
  function t:pause() self.paused = true end
  function t:resume() self.paused = false end
  function t:delete() self.dead = true end
  function t:ready() self.last = -1e9 end
  function t:reset() self.last = nil end
  function t:set(q) for k, v in pairs(q) do self[k] = v end end
  timers[#timers + 1] = t
  return t
end

local PATHS = {
  linear = function(t) return t end,
  ease_in = function(t) return t * t * t end,
  ease_out = function(t) return 1 - (1 - t) ^ 3 end,
  ease_in_out = function(t) return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2 end,
  overshoot = function(t) local c = 1.70158; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end,
  bounce = function(t)
    if t < 1 / 2.75 then return 7.5625 * t * t end
    if t < 2 / 2.75 then t = t - 1.5 / 2.75; return 7.5625 * t * t + 0.75 end
    if t < 2.5 / 2.75 then t = t - 2.25 / 2.75; return 7.5625 * t * t + 0.9375 end
    t = t - 2.625 / 2.75; return 7.5625 * t * t + 0.984375
  end,
}

local function run_anim(a, now)
  local p = a.p
  if not a.running or a.obj.dead or not p.exec_cb then return end
  a.t0 = a.t0 or now + (p.delay or 0)
  if now < a.t0 then return end
  local dur = max(1, p.duration or 500)
  local back = p.playback_time or 0
  local cycle = dur + (back > 0 and (p.playback_delay or 0) + back or 0) + (p.repeat_delay or 0)
  local el = now - a.t0
  local reps = p.repeat_count or 1
  if reps ~= 0xFFFF and el >= cycle * max(1, reps) then
    a.running = false
    safe(p.exec_cb, a.obj, floor(back > 0 and (p.start_value or 0) or (p.end_value or 0)))
    if p.done_cb then safe(p.done_cb, a.obj) end
    return
  end
  local t = el % cycle
  local f
  if t < dur then f = t / dur
  elseif back > 0 and t >= dur + (p.playback_delay or 0) then f = 1 - min(1, (t - dur - (p.playback_delay or 0)) / back)
  else f = back > 0 and 1 or 1 end
  local ease = PATHS[p.path or "linear"] or PATHS.linear
  local s, e = p.start_value or 0, p.end_value or 0
  safe(p.exec_cb, a.obj, floor(s + (e - s) * ease(f) + 0.5))
end

-- ---------------------------------------------------------------- dataman
local last_data = 0
local function poll_data(now, force)
  if not force and now - last_data < 200 then return end
  last_data = now
  for _, s in ipairs(subs) do
    if not s.dead then
      local v = H:data(s.name)
      if v == nil then
        warn("dataman '" .. s.name .. "' has no simulated value in the viewer")
      else
        if type(v) == "number" then v = floor(v * 256) end
        if v ~= s.last then s.last = v; safe(s.cb, s.obj, v) end
      end
    end
  end
end

package.preload.dataman = function()
  return {
    subscribe = function(name, obj, cb)
      local s = { name = name, obj = obj, cb = cb }
      subs[#subs + 1] = s
      return { unsubscribe = function() s.dead = true end }
    end,
    unsubscribe = function() end,
    get = function(name) local v = H:data(name); return type(v) == "number" and floor(v * 256) or v end,
  }
end

package.preload.lvgl = function()
  return setmetatable({
    HOR_RES = function() return SW end, VER_RES = function() return SH end,
    OPA = function(pct) return floor((pct or 0) * 255 / 100 + 0.5) end,
    PCT = function(v) return { pct = v } end,
    SIZE_CONTENT = "content",
    ALIGN = ALIGN, EVENT = EV, FLAG = FLAG,
    TEXT_ALIGN = { AUTO = 0, LEFT = 1, CENTER = 2, RIGHT = 3 },
    ANIM_REPEAT_INFINITE = 0xFFFF, ANIM_PLAYTIME_INFINITE = 0xFFFFFFFF,
    STATE = { DEFAULT = 0, CHECKED = 1, PRESSED = 32 },
    color_hex = function(c) return c end,
    Object = function(parent, p) return new("obj", parent, p) end,
    Label = function(parent, p) return new("label", parent, p) end,
    Image = function(parent, p) return new("img", parent, p) end,
    Timer = timer_new,
    Font = function(name, size, weight)
      local w = 400
      local n = (tostring(name) .. " " .. tostring(weight)):lower()
      if n:find("bold") then w = n:find("demi") and 600 or 700 elseif n:find("medium") then w = 500 end
      return { name = name, size = size or 20, weight = w }
    end,
    BUILTIN_FONT = setmetatable({}, { __index = function(_, k)
      return { size = tonumber(tostring(k):match("%d+")) or 20, weight = 400 } end }),
    indev = { get_act = function()
      return { get_point = function() return point.x, point.y end,
               get_vect = function() return 0, 0 end }
    end },
  }, { __index = function(_, k) warn("lvgl." .. tostring(k) .. " not emulated"); return nil end })
end

-- unknown modules: stub that warns instead of failing require()
table.insert(package.searchers, function(name)
  return function()
    warn("require('" .. name .. "') not emulated: using an empty stub")
    return setmetatable({}, { __index = function(_, k)
      return function() warn(name .. "." .. tostring(k) .. "() is a stub") end
    end })
  end
end)

-- ---------------------------------------------------------------- io / os
local function make_file(content, path, mode)
  local pos, buf = 1, {}
  local f = {}
  function f:read(fmt)
    fmt = tostring(fmt or "l"):gsub("^%*", "")
    if pos > #content then return nil end
    if fmt:sub(1, 1) == "a" then local s = content:sub(pos); pos = #content + 1; return s end
    if fmt:sub(1, 1) == "n" then
      local s, e = content:find("^%s*[-+]?%d+%.?%d*", pos)
      if not s then return nil end
      pos = e + 1; return tonumber(content:sub(s, e))
    end
    local e = content:find("\n", pos, true) or #content + 1
    local s = content:sub(pos, e - 1); pos = e + 1
    if fmt:sub(1, 1) == "L" then s = s .. "\n" end
    return s
  end
  function f:lines() return function() return self:read("l") end end
  function f:write(...) for _, v in ipairs { ... } do buf[#buf + 1] = tostring(v) end; return self end
  function f:seek() return pos - 1 end
  function f:flush() end
  function f:close()
    if mode ~= "r" then
      local data = table.concat(buf)
      if mode:sub(1, 1) == "a" then data = content .. data end
      H:store(path, data)
    end
    return true
  end
  return f
end
io = io or {}
io.open = function(path, mode)
  mode = (mode or "r"):gsub("b", "")
  if mode:sub(1, 1) == "r" then
    local s = H:load(path)
    if s == nil then return nil, path .. ": No such file or directory" end
    return make_file(s, path, "r")
  end
  return make_file(mode:sub(1, 1) == "a" and (H:load(path) or "") or "", path, mode)
end
io.lines = function(path) local f = assert(io.open(path)); return f:lines() end
os.execute = function(cmd) warn("os.execute('" .. tostring(cmd) .. "') does nothing in the viewer"); return nil end
os.remove = function(path) H:store(path, nil); return true end

-- ---------------------------------------------------------------- host hooks
local screen_on = true
H.tick = function(_, now)
  check_long(now)
  if not screen_on then return end
  poll_data(now)
  for i = #timers, 1, -1 do
    local t = timers[i]
    if t.dead or t.repeat_count == 0 then table.remove(timers, i)
    elseif not t.paused then
      if not t.last then t.last = now
      elseif now - t.last >= t.period - 4 then
        t.last = (now - t.last > t.period * 3) and now or t.last + t.period
        if t.repeat_count > 0 then t.repeat_count = t.repeat_count - 1 end
        safe(t.cb, t)
      end
    end
  end
  for _, a in ipairs(anims) do run_anim(a, now) end
end

H.render = function(_, map)
  touch_map = map
  marks = {}
  stats.objects = 0
  H:clear()
  if screen_on then
    for _, r in ipairs(roots) do draw(r, 0, 0, SW, SH, 1) end
    for _, r in ipairs(marks) do H:mark(r[1], r[2], r[3], r[4]) end
  end
  return stats.objects
end

H.screen = function(_, on)
  if on == screen_on then return end
  screen_on = on
  if on then
    if pageOnResume then safe(pageOnResume) end
    poll_data(0, true)
  elseif pageOnPause then
    safe(pageOnPause)
  end
end

H.run = function(_, src, chunk)
  SCRIPT_PATH = H.scriptPath
  local fn, err = load(src, "=" .. chunk)
  if not fn then H:log("error", err); return false end
  local ok = safe(fn)
  poll_data(0, true)
  return ok
end
