-- Headless tests for the stateful sqls parameter prompt/cache adapter.
--
--   nvim --headless -u NONE -l Both/Neovim/nvim/tests/sqls_parameters_test.lua
--
-- The runner drives the real module through fake LSP clients and callback
-- queues standing in for vim.ui.input/select. It never opens a database
-- connection and never loads the user's init.

local script = debug.getinfo(1, "S").source:sub(2)
local nvim_dir = vim.fn.fnamemodify(script, ":h:h")
package.path = nvim_dir .. "/lua/?.lua;" .. package.path

local M, fake, client_id, bufnr

local saved = {}
local notifications = {}
local buffers = {}
local serial = 0

local function new_fake()
  local f = { requests = {}, selects = {}, inputs = {}, clients = {}, request_serial = 0 }

  function f.last_request()
    return f.requests[#f.requests]
  end

  function f.count(command)
    local total = 0
    for _, request in ipairs(f.requests) do
      if request.params.command == command then
        total = total + 1
      end
    end
    return total
  end

  function f.execution_count()
    return f.count "executeQuery"
  end

  function f.client(id, opts)
    opts = opts or {}
    local commands = opts.commands
    if commands == nil then
      commands = { "executeQuery", "explainQuery", "showTables", "getQueryParameters" }
    end
    local client = {
      id = id,
      name = "sqls",
      offset_encoding = "utf-16",
      server_capabilities = { executeCommandProvider = { commands = commands } },
      stopped = false,
    }
    function client:is_stopped()
      return self.stopped
    end
    function client:request(method, params, handler, request_bufnr)
      if self.stopped then
        return false
      end
      f.request_serial = f.request_serial + 1
      table.insert(f.requests, {
        client_id = self.id,
        method = method,
        params = vim.deepcopy(params),
        handler = handler,
        bufnr = request_bufnr,
        id = f.request_serial,
      })
      return true, f.request_serial
    end
    f.clients[id] = client
    return client
  end

  return f
end

local function new_buffer(lines)
  serial = serial + 1
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, "/tmp/sqls-parameters-test-" .. serial .. ".sql")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { "SELECT * FROM EMPLOYE WHERE EMPLYID = :EMPLYID;" })
  table.insert(buffers, buf)
  return buf
end

local function setup(opts)
  opts = opts or {}
  package.loaded["sqls_parameters"] = nil
  M = require "sqls_parameters"
  fake = new_fake()
  client_id = fake.client(1, opts).id
  bufnr = new_buffer(opts.lines)

  saved.input = vim.ui.input
  saved.select = vim.ui.select
  saved.get_client_by_id = vim.lsp.get_client_by_id
  saved.buf_is_attached = vim.lsp.buf_is_attached
  saved.notify = vim.notify

  vim.ui.input = function(input_opts, on_confirm)
    fake.last_input = vim.deepcopy(input_opts)
    table.insert(fake.inputs, { opts = input_opts, confirm = on_confirm })
  end
  vim.ui.select = function(items, select_opts, on_choice)
    fake.last_select = { items = vim.deepcopy(items), prompt = select_opts and select_opts.prompt }
    table.insert(fake.selects, { items = items, opts = select_opts, choose = on_choice })
  end
  vim.lsp.get_client_by_id = function(id)
    return fake.clients[id]
  end
  vim.lsp.buf_is_attached = function(buf, id)
    return fake.clients[id] ~= nil and vim.api.nvim_buf_is_valid(buf)
  end
  vim.notify = function(message, level)
    table.insert(notifications, { message = message, level = level })
  end
end

local function teardown()
  vim.ui.input = saved.input
  vim.ui.select = saved.select
  vim.lsp.get_client_by_id = saved.get_client_by_id
  vim.lsp.buf_is_attached = saved.buf_is_attached
  vim.notify = saved.notify
  for _, buf in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  buffers = {}
  notifications = {}
end

local function pending_discovery()
  for _, request in ipairs(fake.requests) do
    if request.params.command == "getQueryParameters" and not request.answered then
      return request
    end
  end
end

local function answer_discovery(connection_key, query_key, parameters, overrides)
  local request = pending_discovery()
  assert(request, "no pending discovery request")
  request.answered = true
  local response = vim.tbl_extend("force", {
    version = 1,
    connectionKey = connection_key,
    connectionGeneration = 1,
    queryKey = query_key,
    documentKey = "document-key",
    supported = true,
    parameters = parameters or {},
  }, overrides or {})
  request.handler(nil, response, { client_id = request.client_id })
end

local function fail_discovery(message)
  local request = pending_discovery()
  assert(request, "no pending discovery request")
  request.answered = true
  request.handler({ code = -32603, message = message }, nil, { client_id = request.client_id })
end

local function take_select(what)
  local pending = table.remove(fake.selects, 1)
  assert(pending, "no pending " .. what)
  return pending
end

local function choose(value, what)
  local pending = take_select(what)
  for _, item in ipairs(pending.items) do
    if item == value then
      pending.choose(item, 1)
      return
    end
  end
  error(value .. " was not offered as a " .. what)
end

local function choose_type(wire)
  choose(wire, "type selection")
end

local function choose_boolean(wire)
  choose(wire, "boolean value")
end

local function cancel_select(what)
  take_select(what or "selection").choose(nil)
end

local function enter_value(text)
  local pending = table.remove(fake.inputs, 1)
  assert(pending, "no pending value input")
  pending.confirm(text)
end

local function answer_execution(result)
  local request = fake.last_request()
  assert(request and request.params.command == "executeQuery", "no execution request to answer")
  request.handler(nil, result, { client_id = request.client_id })
end

local function submitted_values()
  local request = fake.last_request()
  assert(request, "no request was sent")
  assert(request.params.parameterValues, "the last request carried no parameter values")
  return request.params.parameterValues.values
end

local function notified(fragment)
  for _, entry in ipairs(notifications) do
    if entry.message:find(fragment, 1, true) then
      return true
    end
  end
  return false
end

local function assert_eq(got, want, what)
  if got ~= want then
    error(string.format("%s = %s, want %s", what, vim.inspect(got), vim.inspect(want)), 2)
  end
end

local function assert_same(got, want, what)
  if not vim.deep_equal(got, want) then
    error(string.format("%s = %s, want %s", what, vim.inspect(got), vim.inspect(want)), 2)
  end
end

local one_parameter = { { name = "EMPLYID", key = "EMPLYID" } }

local function complete_flow(value, value_type)
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type(value_type or "text")
  enter_value(value)
end

local tests = {}

local function test(name, opts, fn)
  if fn == nil then
    fn, opts = opts, {}
  end
  table.insert(tests, { name = name, opts = opts, fn = fn })
end

test("prefills the previous value for the same connection and query", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "text"
  enter_value "000123"
  assert_eq(fake.last_request().params.parameterValues.values[1].value, "000123", "submitted value")

  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "text"
  assert_eq(fake.last_input.default, "000123", "prefilled default")
  enter_value(nil)
  assert_eq(fake.execution_count(), 1, "executions")
end)

test("prompts once for a name repeated in the selection", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", { { name = "EMPLYID", key = "EMPLYID" } })
  choose_type "text"
  enter_value "000123"
  assert_eq(#fake.inputs, 0, "left over input prompts")
  assert_eq(#fake.selects, 0, "left over selections")
  assert_same(submitted_values(), { { name = "EMPLYID", type = "text", value = "000123" } }, "values")
end)

test("submits the identity the discovery was made under", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter, { connectionGeneration = 7, documentKey = "document-2" })
  choose_type "text"
  enter_value "1"
  local submission = fake.last_request().params.parameterValues
  assert_eq(submission.version, 1, "version")
  assert_eq(submission.connectionKey, "nrf-key", "connectionKey")
  assert_eq(submission.connectionGeneration, 7, "connectionGeneration")
  assert_eq(submission.queryKey, "query-key", "queryKey")
  assert_eq(submission.documentKey, "document-2", "documentKey")
  assert_same(fake.last_request().params.arguments, { vim.uri_from_bufnr(bufnr), "" }, "arguments")
  assert_eq(fake.last_request().bufnr, bufnr, "request buffer")
end)

test("the same query on another connection starts empty", function()
  complete_flow "000123"
  M.execute(client_id, bufnr, {})
  answer_discovery("centrale-key", "query-key", one_parameter)
  choose_type "text"
  assert_eq(fake.last_input.default, "", "prefilled default")
end)

test("switching back to the first connection recovers its value", function()
  complete_flow "000123"
  M.execute(client_id, bufnr, {})
  answer_discovery("centrale-key", "query-key", one_parameter)
  choose_type "text"
  enter_value "999"
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "text"
  assert_eq(fake.last_input.default, "000123", "prefilled default")
end)

test("a changed query does not prefill", function()
  complete_flow "000123"
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "other-query-key", one_parameter)
  choose_type "text"
  assert_eq(fake.last_input.default, "", "prefilled default")
end)

test("the same query in another buffer prefills", function()
  complete_flow "000123"
  local other = new_buffer()
  M.execute(client_id, other, {})
  answer_discovery("nrf-key", "query-key", one_parameter, { documentKey = "other-document" })
  choose_type "text"
  assert_eq(fake.last_input.default, "000123", "prefilled default")
  enter_value "000123"
  assert_eq(fake.last_request().params.arguments[1], vim.uri_from_bufnr(other), "executed uri")
end)

test("text is the first type initially and the cached type afterwards", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  assert_eq(fake.last_select.items[1], "text", "first choice")
  assert_eq(#fake.last_select.items, 7, "offered types")
  choose_type "integer"
  enter_value "5"

  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  assert_eq(fake.last_select.items[1], "integer", "first choice")
  assert_eq(#fake.last_select.items, 7, "offered types")
end)

test("text NULL is ordinary text and typed NULL has no value prompt", function()
  complete_flow "NULL"
  assert_same(submitted_values(), { { name = "EMPLYID", type = "text", value = "NULL" } }, "values")

  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "other-query-key", one_parameter)
  choose_type "null"
  assert_eq(#fake.inputs, 0, "pending input prompts")
  assert_eq(#fake.selects, 0, "pending selections")
  assert_same(submitted_values(), { { name = "EMPLYID", type = "null", value = "" } }, "values")
end)

test("booleans are chosen, not typed", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "boolean"
  assert_eq(#fake.inputs, 0, "pending input prompts")
  assert_same(fake.last_select.items, { "true", "false" }, "boolean choices")
  choose_boolean "false"
  assert_same(submitted_values(), { { name = "EMPLYID", type = "boolean", value = "false" } }, "values")
end)

test("int64 text is compared as digits, never converted to a number", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "integer"
  enter_value "9223372036854775808"
  assert_eq(fake.execution_count(), 0, "executions")
  enter_value "9223372036854775807"
  local values = submitted_values()
  assert_eq(type(values[1].value), "string", "value type")
  assert_eq(values[1].value, "9223372036854775807", "submitted value")
end)

test("an invalid value re-prompts without echoing it", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "integer"
  enter_value "12x"
  assert_eq(fake.execution_count(), 0, "executions")
  assert_eq(fake.last_input.default, "12x", "re-prompt default")
  assert(notified "EMPLYID", "expected a notification naming the parameter")
  assert(not notified "12x", "the notification echoed the entered value")
  enter_value "42"
  assert_same(submitted_values(), { { name = "EMPLYID", type = "integer", value = "42" } }, "values")
end)

test("date, timestamp and number values are checked before submission", function()
  local function reject_then_accept(wire, bad, good)
    local before = fake.execution_count()
    M.execute(client_id, bufnr, {})
    answer_discovery("nrf-key", "query-" .. wire, one_parameter)
    choose_type(wire)
    enter_value(bad)
    assert_eq(fake.execution_count(), before, wire .. " executions after an invalid value")
    enter_value(good)
    assert_same(submitted_values(), { { name = "EMPLYID", type = wire, value = good } }, wire .. " values")
    answer_execution(nil)
  end

  reject_then_accept("date", "2026-9-1", "2026-09-01")
  reject_then_accept("timestamp", "2026-09-01T00:00:00", "2026-09-01 12:30:00.123456789")
  reject_then_accept("number", "0x10", " 1.5 ")
end)

test("escape at the first prompt sends nothing", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", {
    { name = "EMPLYID", key = "EMPLYID" },
    { name = "YEAR", key = "YEAR" },
  })
  cancel_select "type selection"
  assert_eq(fake.execution_count(), 0, "executions")
  assert_eq(#fake.selects, 0, "pending selections")
  assert_eq(#fake.inputs, 0, "pending input prompts")
end)

test("escape at the last prompt sends nothing and keeps earlier values", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", {
    { name = "EMPLYID", key = "EMPLYID" },
    { name = "YEAR", key = "YEAR" },
  })
  choose_type "text"
  enter_value "000123"
  choose_type "integer"
  enter_value(nil)
  assert_eq(fake.execution_count(), 0, "executions")

  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", { { name = "EMPLYID", key = "EMPLYID" } })
  choose_type "text"
  assert_eq(fake.last_input.default, "", "prefilled default after a cancelled sequence")
end)

test("a cancelled sequence leaves previous complete values intact", function()
  complete_flow "000123"
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "text"
  enter_value(nil)
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "text"
  assert_eq(fake.last_input.default, "000123", "prefilled default")
  assert_eq(fake.execution_count(), 1, "executions")
end)

test("a buffer edited during prompts cancels the submission", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "text"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "SELECT 2 FROM RDB$DATABASE;" })
  enter_value "000123"
  assert_eq(fake.execution_count(), 0, "executions")
  assert(notified "changed", "expected a notification about the changed buffer")
end)

test("a buffer closed during prompts cancels the submission", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "text"
  vim.api.nvim_buf_delete(bufnr, { force = true })
  enter_value "000123"
  assert_eq(fake.execution_count(), 0, "executions")
end)

test("a stopped client during prompts cancels the submission", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "text"
  fake.clients[client_id].stopped = true
  enter_value "000123"
  assert_eq(fake.execution_count(), 0, "executions")
end)

test("one prompt flow per client at a time", function()
  M.execute(client_id, bufnr, {})
  M.execute(client_id, bufnr, {})
  assert_eq(fake.count "getQueryParameters", 1, "discovery requests")
  assert(notified "already", "expected a notification about the running prompt")
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "text"
  enter_value "000123"
  assert_eq(fake.execution_count(), 1, "executions")

  M.execute(client_id, bufnr, {})
  assert_eq(fake.count "getQueryParameters", 2, "discovery requests after the flow ended")
end)

test("clear makes pending callbacks inert and drops the cache", function()
  complete_flow "000123"
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "text"
  M.clear(client_id)
  enter_value "999"
  assert_eq(fake.execution_count(), 1, "executions")

  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "text"
  assert_eq(fake.last_input.default, "", "prefilled default after clear")
end)

test("clear aborts a pending discovery callback", function()
  M.execute(client_id, bufnr, {})
  M.clear(client_id)
  answer_discovery("nrf-key", "query-key", one_parameter)
  assert_eq(#fake.selects, 0, "pending selections")
  assert_eq(fake.execution_count(), 0, "executions")
end)

test("the 101st query evicts the least recently used one", function()
  for i = 1, 101 do
    M.execute(client_id, bufnr, {})
    answer_discovery("nrf-key", "query-" .. i, one_parameter)
    choose_type "text"
    enter_value("value-" .. i)
  end
  assert_eq(fake.execution_count(), 101, "executions")

  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-1", one_parameter)
  choose_type "text"
  assert_eq(fake.last_input.default, "", "prefilled default for the evicted query")
  enter_value(nil)

  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-2", one_parameter)
  choose_type "text"
  assert_eq(fake.last_input.default, "value-2", "prefilled default for a retained query")
  enter_value(nil)
end)

test("the SQL buffer is never edited", function()
  local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  complete_flow "000123"
  answer_execution "id|name\n1|a"
  assert_same(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), before, "buffer lines")
  assert_eq(vim.api.nvim_buf_get_changedtick(bufnr), tick, "changedtick")
  vim.cmd "pclose"
end)

test("a server without the command executes the legacy way", { commands = { "executeQuery" } }, function()
  M.execute(client_id, bufnr, { vertical = true })
  assert_eq(fake.count "getQueryParameters", 0, "discovery requests")
  assert_eq(fake.execution_count(), 1, "executions")
  local params = fake.last_request().params
  assert_eq(params.parameterValues, nil, "parameter values")
  assert_same(params.arguments, { vim.uri_from_bufnr(bufnr), "-show-vertical" }, "arguments")
end)

test("an unsupported connection executes the legacy way", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("", "query-key", nil, { supported = false })
  assert_eq(fake.execution_count(), 1, "executions")
  assert_eq(fake.last_request().params.parameterValues, nil, "parameter values")
end)

test("a selection without parameters executes the legacy way", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", {})
  assert_eq(fake.execution_count(), 1, "executions")
  assert_eq(fake.last_request().params.parameterValues, nil, "parameter values")
end)

test("a discovery error aborts instead of executing", function()
  M.execute(client_id, bufnr, {})
  fail_discovery "document not found"
  assert_eq(fake.execution_count(), 0, "executions")
  assert(notified "document not found", "expected the server error to be reported")

  M.execute(client_id, bufnr, {})
  assert_eq(fake.count "getQueryParameters", 2, "discovery requests after the aborted flow")
end)

test("an unknown protocol version aborts instead of executing", function()
  M.execute(client_id, bufnr, {})
  answer_discovery("nrf-key", "query-key", one_parameter, { version = 2 })
  assert_eq(fake.execution_count(), 0, "executions")
  assert_eq(#fake.selects, 0, "pending selections")
end)

test("a selected range is sent with exact utf-16 endpoints", {
  lines = { "SELECT * FROM T", "WHERE N = :N -- héllo 𝄞" },
}, function()
  M.attach(fake.clients[client_id], bufnr)
  vim.wait(2000, function()
    return vim.api.nvim_buf_get_commands(bufnr, {})["SqlsExecuteQuery"] ~= nil
  end)
  assert(vim.api.nvim_buf_get_commands(bufnr, {})["SqlsExecuteQuery"], "SqlsExecuteQuery was not created")
  assert(vim.api.nvim_buf_get_commands(bufnr, {})["SqlsExecuteQueryVertical"], "SqlsExecuteQueryVertical missing")
  assert(vim.api.nvim_buf_get_commands(bufnr, {})["SqlsClearParameters"], "SqlsClearParameters missing")

  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd "1,2SqlsExecuteQuery"
  end)
  local request = fake.last_request()
  assert_eq(request.params.command, "getQueryParameters", "command")
  assert_same(request.params.range, {
    start = { line = 0, character = 0 },
    ["end"] = { line = 1, character = 24 },
  }, "range")

  answer_discovery("nrf-key", "query-key", { { name = "N", key = "N" } })
  choose_type "integer"
  enter_value "7"
  assert_same(fake.last_request().params.range, {
    start = { line = 0, character = 0 },
    ["end"] = { line = 1, character = 24 },
  }, "executed range")
end)

test("a code action executes with its own range and buffer", function()
  local range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 12 } }
  M.code_action({ command = "executeQuery", arguments = { vim.uri_from_bufnr(bufnr) } }, {
    bufnr = bufnr,
    client_id = client_id,
    params = { range = range },
  })
  local request = fake.last_request()
  assert_eq(request.params.command, "getQueryParameters", "command")
  assert_same(request.params.range, range, "discovery range")
  answer_discovery("nrf-key", "query-key", one_parameter)
  choose_type "text"
  enter_value "000123"
  assert_same(fake.last_request().params.range, range, "executed range")
end)

test("a code action for another document is refused", function()
  M.code_action({ command = "executeQuery", arguments = { "file:///tmp/somewhere-else.sql" } }, {
    bufnr = bufnr,
    client_id = client_id,
    params = {},
  })
  assert_eq(#fake.requests, 0, "requests")
  assert(notified "document", "expected a notification about the mismatched document")
end)

test("results are previewed in a sqls_output buffer", function()
  complete_flow "000123"
  local windows = #vim.api.nvim_list_wins()
  answer_execution "id|name\n1|alpha"
  local output
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf):match "%.sqls_output$" then
      output = buf
    end
  end
  assert(output, "no sqls_output buffer was created")
  assert_same(vim.api.nvim_buf_get_lines(output, 0, -1, false), { "id|name", "1|alpha" }, "rendered lines")
  assert_eq(vim.api.nvim_get_option_value("filetype", { buf = output }), "sqls_output", "filetype")
  assert(#vim.api.nvim_list_wins() > windows, "no preview window was opened")
  vim.cmd "pclose"
  vim.api.nvim_buf_delete(output, { force = true })
end)

test("an empty result opens no window", function()
  complete_flow "000123"
  local windows = #vim.api.nvim_list_wins()
  answer_execution(nil)
  assert_eq(#vim.api.nvim_list_wins(), windows, "windows")
end)

test("a server error on execution is reported once", function()
  complete_flow "000123"
  local request = fake.last_request()
  request.handler({ code = -32603, message = "boom" }, nil, {})
  assert(notified "boom", "expected the server error to be reported")
  assert_eq(fake.execution_count(), 1, "executions")
end)

local failed = 0
for _, entry in ipairs(tests) do
  setup(entry.opts)
  local ok, err = xpcall(entry.fn, debug.traceback)
  teardown()
  if not ok then
    failed = failed + 1
    io.write("FAIL " .. entry.name .. "\n" .. tostring(err) .. "\n")
  end
end

io.write(string.format("%d/%d tests passed\n", #tests - failed, #tests))
if failed > 0 then
  vim.cmd "cquit 1"
end
