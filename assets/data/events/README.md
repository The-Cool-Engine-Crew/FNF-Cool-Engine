# Events Folder — data/events/

This folder contains the engine's event definitions organized by context.

## Folder Structure

data/events/
  chart/        ← Events triggered during gameplay (Chart Editor)
  cutscene/     ← Events for SpriteCutscene
  playstate/    ← Events for the PlayState Editor
  modchart/     ← Events for the Modchart Editor
  global/       ← Visible and active in ALL contexts

## Event Format — flat files

The file name (without extension) = event name.

chart/
  Camera Follow.json    ← editor UI configuration
  Camera Follow.hx      ← HScript handler (optional)
  Camera Follow.lua     ← Lua handler (optional)

## Event Format — folder per event

chart/
  My Custom Event/
    event.json          ← (or config.json)
    handler.hx          ← (or My Custom Event.hx)
    handler.lua         ← (or My Custom Event.lua)

## JSON Format (event.json or EventName.json)

{
  "name": "My Event",
  "description": "Does something cool during gameplay.",
  "color": "#88FF88",
  "context": ["chart"],
  "aliases": ["my event", "ME"],
  "params": [
    {
      "name": "Target",
      "type": "DropDown(bf,dad,gf)",
      "defaultValue": "bf",
      "description": "Target character"
    },
    {
      "name": "Duration",
      "type": "Float(0,10)",
      "defaultValue": "1.0",
      "description": "Duration in seconds"
    },
    {
      "name": "Loop",
      "type": "Bool",
      "defaultValue": "false",
      "description": "Repeat the effect?"
    },
    {
      "name": "Value",
      "type": "Int(0,100)",
      "defaultValue": "50",
      "description": "Integer value"
    },
    {
      "name": "Label",
      "type": "String",
      "defaultValue": "",
      "description": "Free text"
    }
  ]
}

### Supported Parameter Types

- "String": Free text field  
- "Bool": true/false dropdown  
- "Int": Integer number  
- "Int(min,max)": Integer with range  
- "Float": Decimal number  
- "Float(min,max)": Decimal with range  
- "DropDown(a,b,c)": Dropdown with fixed options  
- "Color": Hex color field (e.g. #FFFFFF)

### Available Contexts

- "chart": Chart Editor + during gameplay  
- "cutscene": SpriteCutscene Editor  
- "playstate": PlayState Editor  
- "modchart": Modchart Editor  
- "global": All editors and contexts  

An event can have multiple contexts: "context": ["chart", "modchart"]

## Script Handlers

The handler receives the event when triggered. It can return true to cancel the engine built-in, or false/nil to allow it to run as well.

## Dispatch Priority (execution order)

1. Global scripts → onEvent(name, v1, v2, time)
2. Custom handlers → registerCustomEvent() / registerEvent()
3. Per-event handler → onTrigger(v1, v2, time)
4. Engine built-in
