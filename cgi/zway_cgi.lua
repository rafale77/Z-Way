#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

ABOUT = {
  NAME          = "zway_cgi",
  VERSION       = "2020.03.22",
  DESCRIPTION   = "a WSAPI CGI proxy configuring the ZWay plugin",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2020 AKBooer",
  DOCUMENTATION = "",
  LICENSE       = [[
  Copyright 2013-2020 AK Booer

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
]]
}


-- 2016.10.17  original version

-- 2020.02.16  update for I_ZWay2 device configuration
-- 2020.02.23  handle POST request to reconfigure ZWay child devices
-- 2020.03.19  display all variables of any not fully-configured devices


local wsapi = require "openLuup.wsapi" 
local xml   = require "openLuup.xml"
local json  = require "openLuup.json"

local xhtml = xml.createHTMLDocument ()       -- factory for all HTML tags

local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

local DEV = {
    combo   = "D_ComboDevice1.xml",
  }

local SID = {
    ZWay    = "urn:akbooer-com:serviceId:ZWay1",
  }

local button_class = "w3-button w3-border w3-margin w3-round-large "
local nbsp = json.decode '["\\u00A0"]' [1]    -- yes, really

--[[  
  local status, txt = ZWay.HTTP_request (wsapi_env.SCRIPT_NAME)
--]]

--[[

ZWayVDev [Node ID]:[Instance ID]:[Command Class ID]:[Scale ID] 

The Node Id is the node id of the physical device, 
the Instance ID is the instance id of the device or ’0’ if there is only one instance. 
The command class ID refers to the command class the function is embedded in. 
The scale id is usually ’0’ unless the virtual device is generated from a Z-Wave device 
that supports multiple sensors with different scales in one single command class.

--]]

-- given vDev structure, return altid, vtype, etc...
--   ... node, instance, command_class, scale, sub_class, sub_scale, tail
local NICS_pattern = "^(%d+)%-(%d+)%-?(%d*)%-?(%d*)%-?(%d*)%-?(%d*)%-?(.-)$"
local function NICS_etc (vDev)
  local vtype, altid = vDev.id: match "^ZWayVDev_(zway_%D*)(.+)" 
  if altid then 
    return altid, vtype, altid: match (NICS_pattern)
  end
end

-- find ZWay bridges only
local function find_ZWay_bridge ()
  local bridge = {}
  local B = luup.openLuup.bridge
  local info = B.get_info()
  for n,d in pairs (info.by_devNo) do
    local dev = luup.devices[n]
    if dev.device_type == "ZWay" then
      local dev = luup.devices[n]
      bridge[#bridge+1] = {id = n, offset = d.offset, dev = dev}
    end
  end
  return bridge
end

-- deal with posted form with new child configuration
-- decoded form data looks like:
--[[
{
  "82-0-49-5":"on",
  "83-0-49-1":"on",
  "83-0-49-3":"on",
  "83-0-49-5":"on",
  "bridge":"23"
}
--]]

local function bridge_post (form)
  local devNo = tonumber(form.bridge)
  local dev = luup.devices[devNo]
  if not dev then return end
  
  -- collect all the ticked items by node-instance
  local ticked = {}
  for nics, on in pairs (form) do
    if on == "on" then
      local n, i = nics: match (NICS_pattern)
      local n_i = table.concat {n, '-', i} 
      local x = ticked[n_i] or {}
      x[#x+1] = nics
      ticked[n_i] = x
    end
  end
  
  -- update all the Children variables in the nodes
  local children = dev:get_children()   -- get the device numbers of the bridge node devices
  for _,n in ipairs (children) do
    local specified = luup.variable_get (SID.ZWay, "Children", n) or ''
    local n_i = luup.devices[n].id    -- get the (alt)id
    local new = ticked[n_i]
    if new then 
      table.sort(new)
      new =  table.concat (ticked[n_i], ", ") 
    else
      new = ''  -- no children is the default
    end
    if specified ~= new then    -- it's changed! so update
      luup.variable_set (SID.ZWay, "Children", new, n) 
    end
  end
  
end

-- returns an ordered list 
-- NB: these are openLuup vars, not ZWay ones!
local function listVars (vars)
  local list = {}
  for _,v in ipairs (vars) do
    local vtype, nics = v.name: match "zway_(%D*)(.*)"
    nics = nics or ''
    local node, instance, command_class, scale, sub_class, sub_scale, tail = nics: match (NICS_pattern)
    if node and not tail: match "LastUpdate$" and command_class ~= "128" then  -- ignore batteries
      list[#list+1] = nics
    end
  end
--  print ((json.encode(list)))
  return list
end

-- display bridge info as HTML table
--       bridge = {id = n, offset = d.offset, dev = dev}
local function bridge_form (bridge, action)
  
  -- find the direct children (should just be the Zwave nodes)
  local dev = bridge.dev
  local children = dev:get_children()
  table.sort (children)
--  print ('', "#children", #children)
  
  -- find ALL the descendants of the bridge (includes instance nodes and specified devices)
  local current = luup.openLuup.bridge.all_descendants (bridge.id)
  local currentIndexedByAltid = {}
  for n,v in pairs(current) do 
    if n > luup.openLuup.bridge.BLOCKSIZE then        -- ignore anything not in the block
      currentIndexedByAltid[v.id] = n                 -- 'id' is actually altid!
    end
  end
  
  -- set up the HTML devices table
  local rows = xhtml.tbody {}
  local tbl = xhtml.table {class="w3-small w3-hoverable w3-border",
    xhtml.thead {
      xhtml.trow ({ {colspan=2, "devNo"},
      {colspan=2, "altid"}, "device file", nbsp:rep(3), "name"}, true)},
      rows
    }
  
  for _,n in ipairs (children) do
    local c = luup.devices[n]
    local g = c:get_children()      -- get grandchildren
    local grandchild = {}           -- index by altid
    for _, gc in ipairs (g) do
      local gdev = luup.devices[gc]
      grandchild[gdev.id] = gdev
    end
    
    local cvar = luup.variable_get (SID.ZWay, "Children", n) or ''
    local cs = {}
    for alt in cvar: gmatch "[%-%w]+" do cs[alt] = true end  -- individuals
    
    local altid = c.id
--    print ('', altid, c.attributes.device_file, c.description)
    
    local vars = listVars (c.variables)
    local upnp_file = c.attributes.device_file or ''
--    local button = #vars < 2
--      and ''
--      or xhtml.button{type = "button", onclick= table.concat {"ShowHide('", altid, "')"}, '▼'}
    local button = ''
    rows[#rows+1] = xhtml.tbody {
      xhtml.trow {n, '', '', altid, upnp_file, '', c.description}  }
    
    do          
        -- now go through all variables within the instance
        local sw_or_dim = "^%d+%-%d+%-3[78]"
        if #vars > 1
        -- ignore switch + dimmer (= Somfy blind?)
        and not (#vars == 2 and vars[1]:match (sw_or_dim) and vars[2]: match (sw_or_dim)) then
          local v = xhtml.tbody {id = altid }
--          local v = xhtml.tbody {id = altid, class="w3-hide" }
          rows[#rows+1] = v
          for _, nics in ipairs (vars) do
            local checked = cs[nics] and nics or nil
            local dfile, dname, dnumber
            local gdev = grandchild[nics]
            if checked and gdev then
              dfile, dname, dnumber = gdev.attributes.device_file, gdev.description, gdev.attributes.id
            end
            v[#v+1] = xhtml.trow {'', dnumber or '',
              xhtml.input {type="checkbox", name=nics, checked=checked}, 
              nics, -- vtype,
              dfile, ' ', dname }
          end
        end
--      end
    end
  end
    
  local title = xhtml.div {class = "w3-container w3-grey", 
    xhtml.h3 {'[', bridge.id, '] ', dev.description,
              xhtml.input {class = button_class .. "w3-pale-red",
                  type="Submit", value="Commit", title="change child configuration"},
              xhtml.input {class = button_class .. "w3-pale-green",
                  type="Reset", title="reset child configuration"},
    } }
  
  return xhtml.div {class = "w3-panel",
    xhtml.form {class = "w3-container w3-margin-top",
      action=action, 
      method="post",
      xhtml.input {type = "hidden", name="bridge", value = bridge.id},
      title, tbl } }
end

---------
--
--  CGI
--
function run(wsapi_env)

  _log = function (...) wsapi_env.error:write(...) end      -- set up the log output, note colon syntax
  
  local req = wsapi.request.new (wsapi_env)   -- use request library to get object with useful methods
  local res = wsapi.response.new ()           -- and the response library to build the response!
  
  -- deal with POST of form data
  if req.method == "POST" then
    bridge_post (req.POST)
  end
  
  -- find the ZWay bridges
  --       bridge = {id = n, offset = d.offset, dev = dev}
  local bridges = find_ZWay_bridge ()    
  
  -- create the web page
  local h = xml.createHTMLDocument "ZWay-config"
  local d = h.div {class = "w3=container"}
  for _, b in ipairs(bridges) do
    local tbl = bridge_form (b, req.script_name)
    d[#d+1] = tbl
  end
    
  local script = h.script {
  [[
  function ShowHide(id) {
    var x = document.getElementById(id);
    if (x.className.indexOf("w3-show") == -1) {
      x.className += " w3-show";
    } else {
      x.className = x.className.replace(" w3-show", "");
    }
  }]]}
  
  h.body:appendChild {
    h.meta {charset="utf-8", name="viewport", content="width=device-width, initial-scale=1"}, 
    h.link {rel="stylesheet", href="https://www.w3schools.com/w3css/4/w3.css"},
    script,
    h.div {class = "w3-grey", 
      h.div {class = "w3-bar", h.h2 "Device configuration for ZWay plugin"} },
      d } 
    
  res:write (tostring(h))
  res:content_type "text/html" 
  return res:finish()
end
 
-----
