-- Word only: keep each table together on one page, leaving lists free to break.
local function mark(row, style)
  for _, cell in ipairs(row.cells) do
    local blocks = cell.contents:walk({ Plain = function(p) return pandoc.Para(p.content) end })
    cell.contents = { pandoc.Div(blocks, pandoc.Attr("", {}, { { "custom-style", style } })) }
  end
end

function Table(t)
  for _, row in ipairs(t.head.rows) do mark(row, "Table Text") end
  for _, body in ipairs(t.bodies) do
    for i, row in ipairs(body.body) do
      mark(row, i == #body.body and "Compact" or "Table Text")
    end
  end
  return t
end
