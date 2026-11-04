-- Small JSON codec for standalone Lua tests and servers without Util. No code evaluation.
local M = {}
local escapes = { ['"']='\\"', ['\\']='\\\\', ['\b']='\\b', ['\f']='\\f', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t' }
local function quote(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c) return escapes[c] or string.format('\\u%04x', c:byte()) end) .. '"'
end
function M.encode(v)
  local t = type(v)
  if t == 'nil' then return 'null' end
  if t == 'boolean' then return tostring(v) end
  if t == 'number' then assert(v == v and math.abs(v) < math.huge, 'nonfinite'); return string.format('%.17g', v) end
  if t == 'string' then return quote(v) end
  assert(t == 'table', 'unsupported JSON type')
  local a, n = true, 0
  for k in pairs(v) do n = n + 1; if type(k) ~= 'number' then a = false end end
  a = a and n > 0 and #v == n
  local out = {}
  if a then for i = 1, n do out[i] = M.encode(v[i]) end
  else for k, val in pairs(v) do out[#out+1] = quote(tostring(k)) .. ':' .. M.encode(val) end end
  return (a and '[' or '{') .. table.concat(out, ',') .. (a and ']' or '}')
end
function M.decode(s)
  local i = 1
  local function ws() local _, j = s:find('^[ \t\r\n]*', i); i = (j or i-1)+1 end
  local parse
  local function str()
    assert(s:sub(i,i) == '"'); i=i+1
    local out = {}
    while i <= #s do
      local c = s:sub(i,i); i=i+1
      if c == '"' then return table.concat(out) end
      if c == '\\' then
        local e=s:sub(i,i); i=i+1
        local map={ ['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t' }
        if e == 'u' then
          local hex=s:sub(i,i+3); assert(hex:match('^%x%x%x%x$')); i=i+4
          local n=tonumber(hex,16)
          if n < 128 then c=string.char(n)
          elseif n < 2048 then c=string.char(192+math.floor(n/64),128+n%64)
          else c=string.char(224+math.floor(n/4096),128+math.floor(n/64)%64,128+n%64) end
        else c=assert(map[e], 'escape') end
      else assert(c:byte() >= 32, 'control') end
      out[#out+1]=c
    end
    error('unterminated string')
  end
  parse=function(depth)
    assert(depth < 100, 'depth'); ws()
    local c=s:sub(i,i)
    if c == '"' then return str() end
    if c == '{' or c == '[' then
      i=i+1; ws(); local out={}; local close=c=='{' and '}' or ']'
      if s:sub(i,i)==close then i=i+1; return out end
      while true do
        local k
        if c=='{' then ws(); k=str(); ws(); assert(s:sub(i,i)==':'); i=i+1 else k=#out+1 end
        out[k]=parse(depth+1); ws()
        local sep=s:sub(i,i); i=i+1
        if sep==close then return out end
        assert(sep==',', 'separator')
      end
    end
    for word, value in pairs({['true']=true,['false']=false}) do
      if s:sub(i,i+#word-1)==word then i=i+#word; return value end
    end
    if s:sub(i,i+3)=='null' then i=i+4; return nil end
    local token=s:sub(i):match('^-?%d+%.?%d*[eE]?[+-]?%d*')
    local n=token and tonumber(token); assert(n and n==n and math.abs(n)<math.huge, 'number')
    i=i+#token; return n
  end
  local value=parse(0); ws(); assert(i>#s, 'trailing JSON'); return value
end
return M
