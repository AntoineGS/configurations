-- Prompts for the named parameters of a sqls query, remembers the answers per
-- connection and query, and submits them with the execution request.
--
-- The SQL buffer is never edited: values travel in the executeQuery envelope as
-- bound parameters. Everything here is asynchronous — discovery, the type and
-- value prompts, and the execution are separate callbacks — so the buffer, URI,
-- changedtick and display options are captured up front and re-checked before
-- anything is submitted.

local M = {}

-- The seven wire type strings, in prompt order. A remembered type is offered
-- first; otherwise text is.
local TYPES = { "text", "integer", "number", "date", "timestamp", "boolean", "null" }

local PROTOCOL_VERSION = 1
local DISCOVERY_COMMAND = "getQueryParameters"
local MAX_ENTRIES = 100

local INT64_MAX = "9223372036854775807"
local INT64_MIN = "9223372036854775808" -- magnitude of the most negative int64

-- Per-client state. Entries are never removed, only emptied: a pending
-- callback holds an epoch taken from this table and compares it against the
-- live one to decide whether it is still the current operation.
local states = {}

local function state_for(client_id)
  local state = states[client_id]
  if not state then
    state = { cache = {}, entries = 0, usage = 0, epoch = 0, busy = false }
    states[client_id] = state
  end
  return state
end

local function notify(message, level)
  vim.notify("sqls: " .. message, level or vim.log.levels.ERROR)
end

local function advertises(client, command)
  local provider = client.server_capabilities and client.server_capabilities.executeCommandProvider
  if type(provider) ~= "table" then
    return false
  end
  return vim.tbl_contains(provider.commands or {}, command)
end

-- offset_length is the end.character the server validates a selection against:
-- the length of the real final line in the client's offset encoding, never
-- v:maxcol and never a byte count.
local function offset_length(line, encoding)
  if encoding == "utf-8" then
    return #line
  end
  return vim.str_utfindex(line, encoding or "utf-16")
end

local function line_range(bufnr, line1, line2, encoding)
  local last = vim.api.nvim_buf_get_lines(bufnr, line2 - 1, line2, false)[1] or ""
  return {
    start = { line = line1 - 1, character = 0 },
    ["end"] = { line = line2 - 1, character = offset_length(last, encoding) },
  }
end

-- preview renders a result the way the installed plugin does — a temp buffer
-- named *.sqls_output shown with pedit and given the sqls_output filetype — so
-- the user keeps that experience without this module reaching into a private
-- vendor function.
local function preview(smods)
  return function(err, result)
    if err then
      notify(err.message)
      return
    end
    if not result then
      return
    end
    local tempfile = vim.fn.tempname() .. ".sqls_output"
    local out = vim.fn.bufnr(tempfile, true)
    vim.api.nvim_buf_set_lines(out, 0, 1, false, vim.split(result, "\n"))
    vim.cmd.pedit { args = { tempfile }, mods = smods or {} }
    vim.api.nvim_set_option_value("filetype", "sqls_output", { buf = out })
  end
end

-- send_execution is the only place an executeQuery request is made. A request
-- that cannot be sent is reported, never retried through another path.
local function send_execution(session, parameter_values)
  local client = vim.lsp.get_client_by_id(session.client_id)
  if not client or client:is_stopped() then
    notify "the language server is no longer available"
    return false
  end
  local params = {
    command = "executeQuery",
    arguments = { session.uri, session.vertical and "-show-vertical" or "" },
    range = session.range,
    parameterValues = parameter_values,
  }
  local sent = client:request("workspace/executeCommand", params, preview(session.smods), session.bufnr)
  if not sent then
    notify "the language server is no longer available"
    return false
  end
  return true
end

-- Cache ---------------------------------------------------------------------

local function cache_key(connection_key, query_key)
  return vim.json.encode { connection_key, query_key }
end

local function touch(state, entry)
  state.usage = state.usage + 1
  entry.usage = state.usage
end

local function evict(state)
  while state.entries > MAX_ENTRIES do
    local oldest_key, oldest_usage
    for key, entry in pairs(state.cache) do
      if not oldest_usage or entry.usage < oldest_usage then
        oldest_key, oldest_usage = key, entry.usage
      end
    end
    state.cache[oldest_key] = nil
    state.entries = state.entries - 1
  end
end

local function remembered(state, key)
  local entry = state.cache[key]
  if not entry then
    return {}
  end
  touch(state, entry)
  return vim.deepcopy(entry.values)
end

local function remember(state, key, values)
  local entry = state.cache[key]
  if not entry then
    entry = {}
    state.cache[key] = entry
    state.entries = state.entries + 1
  end
  entry.values = values
  touch(state, entry)
  evict(state)
end

-- Value validation ----------------------------------------------------------

-- fits_int64 compares decimal digits as strings. The values this checks do not
-- survive a trip through a Lua number, so arithmetic is never used on them.
local function fits_int64(digits, negative)
  local limit = negative and INT64_MIN or INT64_MAX
  digits = digits:gsub("^0+", "")
  if digits == "" then
    return true
  end
  if #digits ~= #limit then
    return #digits < #limit
  end
  return digits <= limit
end

local TIMESTAMP = "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d(.*)$"
local FRACTION = "^%.%d%d?%d?%d?%d?%d?%d?%d?%d?$"

-- invalid returns a message when the entered text obviously cannot be the
-- chosen type. The server remains authoritative; this only saves a round trip.
-- The message never repeats the value the user typed.
local function invalid(value_type, text)
  if value_type == "text" then
    return nil
  end
  local trimmed = vim.trim(text)
  if value_type == "integer" then
    local sign, digits = trimmed:match "^([+-]?)(%d+)$"
    if not digits then
      return "expects whole digits with an optional sign"
    end
    if not fits_int64(digits, sign == "-") then
      return "is outside the 64-bit integer range"
    end
    return nil
  end
  if value_type == "number" then
    local parsed = tonumber(trimmed)
    local hex = trimmed:match "^[+-]?0[xX]"
    if not parsed or hex or parsed ~= parsed or parsed == math.huge or parsed == -math.huge then
      return "expects a finite decimal number"
    end
    return nil
  end
  if value_type == "date" then
    if not trimmed:match "^%d%d%d%d%-%d%d%-%d%d$" then
      return "expects a date as YYYY-MM-DD"
    end
    return nil
  end
  if value_type == "timestamp" then
    local fraction = trimmed:match(TIMESTAMP)
    if not fraction or not (fraction == "" or fraction:match(FRACTION)) then
      return "expects a timestamp as YYYY-MM-DD HH:MM:SS[.fraction]"
    end
    return nil
  end
  if value_type == "boolean" then
    if trimmed ~= "true" and trimmed ~= "false" then
      return "expects true or false"
    end
    return nil
  end
  return nil
end

-- Prompt flow ---------------------------------------------------------------

local function type_choices(previous)
  local first = previous
  if not first or not vim.tbl_contains(TYPES, first) then
    first = "text"
  end
  local items = { first }
  for _, wire in ipairs(TYPES) do
    if wire ~= first then
      items[#items + 1] = wire
    end
  end
  return items
end

-- submittable rejects a context that no longer describes what the user
-- answered for. The server owns connection identity; this owns the client-side
-- facts a server cannot see.
local function submittable(session)
  local client = vim.lsp.get_client_by_id(session.client_id)
  if not client or client:is_stopped() then
    return "the language server is no longer available"
  end
  if not vim.api.nvim_buf_is_valid(session.bufnr) then
    return "the buffer was closed while entering parameters; nothing was executed"
  end
  if vim.uri_from_bufnr(session.bufnr) ~= session.uri then
    return "the buffer was renamed while entering parameters; nothing was executed"
  end
  if vim.api.nvim_buf_get_changedtick(session.bufnr) ~= session.changedtick then
    return "the buffer changed while entering parameters; nothing was executed"
  end
  return nil
end

-- run_prompts asks for each discovered parameter in turn and submits only once
-- every answer is in. The draft is local to this sequence: a cancelled or
-- abandoned run leaves whatever was remembered before untouched.
local function run_prompts(session, state, epoch, discovery)
  local parameters = discovery.parameters
  local previous = remembered(state, session.key)
  local draft = {}
  local index = 0

  local function live()
    return state.epoch == epoch
  end

  local function release()
    if live() then
      state.busy = false
    end
  end

  local function abort(message)
    if message then
      notify(message)
    end
    release()
  end

  local prompt_type

  local function finish()
    local problem = submittable(session)
    if problem then
      abort(problem)
      return
    end
    local values = {}
    local by_name = {}
    for _, entry in ipairs(draft) do
      values[#values + 1] = { name = entry.name, type = entry.type, value = entry.value }
      by_name[entry.name] = { type = entry.type, value = entry.value }
    end
    release()
    local sent = send_execution(session, {
      version = discovery.version,
      connectionKey = discovery.connectionKey,
      connectionGeneration = discovery.connectionGeneration,
      queryKey = discovery.queryKey,
      documentKey = discovery.documentKey,
      values = values,
    })
    if sent then
      remember(state, session.key, by_name)
    end
  end

  local function advance(name, value_type, value)
    draft[#draft + 1] = { name = name, type = value_type, value = value }
    index = index + 1
    if index >= #parameters then
      finish()
    else
      prompt_type()
    end
  end

  local function prompt_value(name, value_type, default, database_type, toggle_null, initially_null)
    local null_active = initially_null == true
    local label = database_type or value_type
    local input_opts = { prompt = name .. " (" .. label .. "): ", default = default }
    if toggle_null then
      local function set_title(win)
        win:set_title(name .. " (" .. label .. ")" .. (null_active and " [NULL]" or ""))
      end
      input_opts.win = {
        actions = {
          toggle_null = function(win)
            null_active = not null_active
            set_title(win)
          end,
        },
        keys = { ["<c-t>"] = { "toggle_null", mode = "i" } },
        on_win = set_title,
      }
    end
    vim.ui.input(input_opts, function(text)
      if not live() then
        return
      end
      if text == nil then
        release()
        return
      end
      if null_active then
        advance(name, "null", "")
        return
      end
      local problem = invalid(value_type, text)
      if problem then
        notify(name .. " " .. problem, vim.log.levels.WARN)
        prompt_value(name, value_type, text, database_type, toggle_null, false)
        return
      end
      advance(name, value_type, text)
    end)
  end

  local function prompt_boolean(name)
    vim.ui.select({ "true", "false" }, { prompt = name .. " (boolean)" }, function(choice)
      if not live() then
        return
      end
      if choice == nil then
        release()
        return
      end
      advance(name, "boolean", choice)
    end)
  end

  prompt_type = function()
    local parameter = parameters[index + 1]
    local name = parameter.name
    local prior = previous[name]
    local inferred = parameter.inferredType
    local snacks = rawget(_G, "Snacks")
    local snacks_owns_input = type(snacks) == "table"
      and type(snacks.input) == "table"
      and type(snacks.input.input) == "function"
      and vim.ui.input == snacks.input.input
    if snacks_owns_input and inferred ~= "null" and vim.tbl_contains(TYPES, inferred) then
      local default = ""
      if prior and prior.type == inferred then
        default = prior.value
      end
      prompt_value(name, inferred, default, parameter.databaseType, true, prior and prior.type == "null")
      return
    end
    vim.ui.select(type_choices(prior and prior.type), { prompt = name .. " type" }, function(choice)
      if not live() then
        return
      end
      if choice == nil then
        release()
        return
      end
      if choice == "null" then
        advance(name, "null", "")
      elseif choice == "boolean" then
        prompt_boolean(name)
      else
        local default = ""
        if prior and prior.type == choice then
          default = prior.value
        end
        prompt_value(name, choice, default)
      end
    end)
  end

  index = 0
  prompt_type()
end

-- Entry points --------------------------------------------------------------

-- execute runs the parameter-aware flow for one command invocation. Everything
-- the submission needs is captured now, while the invoking buffer is still the
-- current one; a prompt that moves focus cannot change what is executed.
function M.execute(client_id, bufnr, opts)
  opts = opts or {}
  local client = vim.lsp.get_client_by_id(client_id)
  if not client or client:is_stopped() then
    notify "the language server is no longer available"
    return
  end
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local session = {
    client_id = client_id,
    bufnr = bufnr,
    uri = vim.uri_from_bufnr(bufnr),
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    range = opts.range,
    vertical = opts.vertical,
    smods = opts.smods,
  }

  if not advertises(client, DISCOVERY_COMMAND) then
    send_execution(session, nil)
    return
  end

  local state = state_for(client_id)
  if state.busy then
    notify("a query parameter prompt is already in progress for this server", vim.log.levels.WARN)
    return
  end
  state.busy = true
  local epoch = state.epoch

  local discovery_params = {
    command = DISCOVERY_COMMAND,
    arguments = { session.uri },
    range = session.range,
  }
  local sent = client:request("workspace/executeCommand", discovery_params, function(err, discovery)
    if state.epoch ~= epoch then
      return
    end
    state.busy = false
    if err then
      -- A supported server that failed to describe the query must not be asked
      -- to run it unparameterized instead.
      notify(err.message)
      return
    end
    if type(discovery) ~= "table" then
      notify "the server returned no query parameter information"
      return
    end
    if discovery.version ~= PROTOCOL_VERSION then
      notify(
        string.format(
          "this server speaks query parameter protocol version %s; this configuration speaks %d",
          tostring(discovery.version),
          PROTOCOL_VERSION
        )
      )
      return
    end
    local parameters = discovery.parameters or {}
    if not discovery.supported or #parameters == 0 then
      send_execution(session, nil)
      return
    end
    session.key = cache_key(discovery.connectionKey, discovery.queryKey)
    state.busy = true
    run_prompts(session, state, epoch, {
      version = discovery.version,
      connectionKey = discovery.connectionKey,
      connectionGeneration = discovery.connectionGeneration,
      queryKey = discovery.queryKey,
      documentKey = discovery.documentKey,
      parameters = parameters,
    })
  end, bufnr)
  if not sent then
    state.busy = false
    notify "the language server is no longer available"
  end
end

-- selected_range is the range a code action actually selected. Invoked in
-- normal mode, vim.lsp.buf.code_action builds the range from the cursor, so
-- start equals end. The server slices the document with whatever range it
-- receives, and a zero-width one slices out the empty string; absent means the
-- whole document, which is what an unselected "Execute Query" means.
local function selected_range(range)
  if not range or not range.start or not range["end"] then
    return nil
  end
  if range.start.line == range["end"].line and range.start.character == range["end"].character then
    return nil
  end
  return range
end

-- code_action runs a server-offered executeQuery. Its range comes from the
-- code action request that produced it, never from wherever the cursor happens
-- to be now.
function M.code_action(command, context)
  context = context or {}
  local bufnr = context.bufnr
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local uri = command and command.arguments and command.arguments[1]
  if type(uri) == "string" and uri ~= vim.uri_from_bufnr(bufnr) then
    notify "this code action belongs to another document; run it from that buffer"
    return
  end
  local range = selected_range(context.params and context.params.range)
  M.execute(context.client_id, bufnr, { range = range })
end

-- clear forgets everything remembered for a client and makes every callback
-- still waiting on a prompt inert.
function M.clear(client_id)
  local state = states[client_id]
  if not state then
    return
  end
  state.cache = {}
  state.entries = 0
  state.usage = 0
  state.busy = false
  state.epoch = state.epoch + 1
end

-- attach replaces the vendor's buffer commands with parameter-aware ones. It is
-- scheduled so the vendor on_attach has already created them, and re-checks the
-- buffer and client before overriding anything.
function M.attach(client, bufnr)
  local client_id = client.id
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) or client:is_stopped() then
      return
    end
    if not vim.lsp.buf_is_attached(bufnr, client_id) then
      return
    end

    local function execute_command(vertical)
      return function(args)
        local range
        if args.range ~= 0 then
          range = line_range(bufnr, args.line1, args.line2, client.offset_encoding)
        end
        M.execute(client_id, bufnr, { range = range, vertical = vertical, smods = args.smods })
      end
    end

    vim.api.nvim_buf_create_user_command(bufnr, "SqlsExecuteQuery", execute_command(false), {
      range = true,
      force = true,
      desc = "Execute SQL, prompting for any query parameters",
    })
    vim.api.nvim_buf_create_user_command(bufnr, "SqlsExecuteQueryVertical", execute_command(true), {
      range = true,
      force = true,
      desc = "Execute SQL vertically, prompting for any query parameters",
    })
    vim.api.nvim_buf_create_user_command(bufnr, "SqlsClearParameters", function()
      M.clear(client_id)
    end, {
      force = true,
      desc = "Forget remembered SQL query parameter values",
    })
  end)
end

return M
