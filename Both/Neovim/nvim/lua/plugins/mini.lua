local wk = require "which-key"

wk.add {
  { "<leader>mt", group = "MiniTest" },
  { "<leader>mtr", "<cmd>lua MiniTest.run()<CR>", desc = "Run" },
  { "<leader>mtf", "<cmd>lua MiniTest.run_file()<CR>", desc = "Run File" },
  { "<leader>mtl", "<cmd>lua MiniTest.run_at_location()<CR>", desc = "Run At Location" },
}

-- mini.ai shortcuts
---@type table<string, string|table>
local text_objects = {
  [" "] = "Whitespace",
  ['"'] = 'Balanced "',
  ["'"] = "Balanced '",
  ["`"] = "Balanced `",
  ["("] = "Balanced (",
  [")"] = { i = "Balanced ) including white-space", a = "Balanced )" },
  ["<"] = "Balanced <",
  [">"] = { i = "Balanced > including white-space", a = "Balanced >" },
  ["["] = "Balanced [",
  ["]"] = { i = "Balanced ] including white-space", a = "Balanced ]" },
  ["{"] = "Balanced {",
  ["}"] = { i = "Balanced } including white-space", a = "Balanced }" },
  ["?"] = "User Prompt",
  ["_"] = "Underscore",
  a = "Argument",
  b = "Balanced ), ], }",
  c = "Class",
  d = "Digit(s)",
  e = "Word in CamelCase & snake_case",
  f = "Function",
  g = "Entire file",
  i = "Indent",
  o = "Block, conditional, loop",
  q = "Quote `, \", '",
  t = "Tag",
  u = "Use/call function & method",
  U = "Use/call without dot in name",
}

local mappings = {
  mode = { "o", "x" },
}

for prefix in pairs { i = true, a = true } do
  for key, desc in pairs(text_objects) do
    local description = type(desc) == "table" and desc[prefix] or desc
    table.insert(mappings, { prefix .. key, desc = description })
  end

  for _, variant in ipairs { "n", "l" } do
    local group_name = (prefix == "i" and "Inside " or "Around ")
      .. (variant == "n" and "Next" or "Last")
      .. " textobject"

    table.insert(mappings, { prefix .. variant, group = group_name })

    for key, desc in pairs(text_objects) do
      local description = type(desc) == "table" and desc[prefix] or desc
      table.insert(mappings, { prefix .. variant .. key, desc = description })
    end
  end
end

wk.add(mappings)

return {
  "echasnovski/mini.nvim",
  version = false,
  require("mini.test").setup(),
  require("mini.ai").setup(),
}
