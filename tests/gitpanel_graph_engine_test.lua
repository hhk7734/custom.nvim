local gitgraph = require("core.sidebar.gitgraph")

local function commit(hash, parents, opts)
  opts = opts or {}
  return {
    hash = hash,
    parents = parents,
    msg = opts.msg or ("subject " .. hash),
    branch_names = opts.branch_names or {},
    tags = opts.tags or {},
    author_date = "2026-01-01 00:00",
    author_name = "tester",
  }
end

-- linear history: c -> b -> a renders one straight lane, messages on the
-- connector rows
do
  local g = gitgraph._gitgraph({
    commit("ccccccc", { "bbbbbbb" }, { branch_names = { "HEAD -> main" } }),
    commit("bbbbbbb", { "aaaaaaa" }),
    commit("aaaaaaa", {}),
  }, {})

  assert(#g.lines == 6, "linear: expected 6 rows, got " .. #g.lines)
  assert(g.lines[1]:match("^●%s+ccccccc"), "linear row 1: " .. g.lines[1])
  assert(g.lines[2]:match("^│") and g.lines[2]:find("subject ccccccc", 1, true), "linear row 2: " .. g.lines[2])
  assert(g.lines[3]:match("^●%s+bbbbbbb"), "linear row 3: " .. g.lines[3])
  assert(g.lines[5]:match("^●%s+aaaaaaa"), "linear row 5: " .. g.lines[5])
  assert(g.lines[6]:find("subject aaaaaaa", 1, true), "linear: last commit message missing: " .. g.lines[6])
  assert(g.lines[1]:find("(HEAD -> main)", 1, true), "linear: HEAD decoration missing: " .. g.lines[1])
  assert(g.head_lnum == 1, "linear: head_lnum should be 1")
  assert(g.row_commits[1].hash == "ccccccc" and g.row_commits[2].hash == "ccccccc", "linear: row commit map")
end

-- merge diamond: m(b, a), b(a), a renders the docs/layout Graph Click shape
do
  local g = gitgraph._gitgraph({
    commit("m000000", { "bbbbbbb", "aaaaaaa" }, { tags = { "tag: v1.0" } }),
    commit("bbbbbbb", { "aaaaaaa" }),
    commit("aaaaaaa", {}),
  }, {})

  assert(#g.lines == 6, "merge: expected 6 rows, got " .. #g.lines)
  assert(g.lines[1]:match("^◉%s+m000000"), "merge row 1: " .. g.lines[1])
  assert(g.lines[1]:find("(tag: v1.0)", 1, true), "merge: tag decoration missing: " .. g.lines[1])
  assert(g.lines[2]:match("^├─╮"), "merge row 2: " .. g.lines[2])
  assert(g.lines[3]:match("^● │%s+bbbbbbb"), "merge row 3: " .. g.lines[3])
  assert(g.lines[4]:match("^├─╯"), "merge row 4: " .. g.lines[4])
  assert(g.lines[5]:match("^●%s+aaaaaaa"), "merge row 5: " .. g.lines[5])

  local lane_marks, tag_marks = 0, 0
  for _, m in ipairs(g.marks) do
    if m.hl:match("^GitPanelGraphBranch%d$") then
      lane_marks = lane_marks + 1
    end
    if m.hl == "GitPanelGraphTag" then
      tag_marks = tag_marks + 1
    end
  end
  assert(lane_marks > 0, "merge: expected colored lane marks")
  assert(tag_marks == 1, "merge: expected one tag mark")
end

-- two stacked merges must resolve every connector (no '?' placeholders) and
-- keep the alternating commit/connector row structure
do
  local g = gitgraph._gitgraph({
    commit("m222222", { "m111111", "ddddddd" }),
    commit("m111111", { "bbbbbbb", "ccccccc" }),
    commit("ddddddd", { "aaaaaaa" }),
    commit("ccccccc", { "aaaaaaa" }),
    commit("bbbbbbb", { "aaaaaaa" }),
    commit("aaaaaaa", {}),
  }, {})

  assert(#g.lines == 12, "double merge: expected 12 rows, got " .. #g.lines)
  for i, line in ipairs(g.lines) do
    assert(not line:find("?", 1, true), "unresolved connector on row " .. i .. ": " .. line)
  end
  for i = 1, #g.lines - 1, 2 do
    assert(g.lines[i]:find("●", 1, true) or g.lines[i]:find("◉", 1, true), "row " .. i .. " should be a commit row")
  end
end
