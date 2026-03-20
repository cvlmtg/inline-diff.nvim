-- Benchmark runner: measures diff computation + render time for 3 approaches.
--
-- Usage:
--   nvim --headless --clean -c "set rtp+=." -c "luafile bench/run.lua"

vim.opt.rtp:append(".")

local highlight = require("inline-diff.highlight")
local state = require("inline-diff.state")
local render = require("inline-diff.render")
local data = require("bench.data")
local approaches = require("bench.approaches")

highlight.define()

local WARMUP = 2
local ITERATIONS = 10

-- ── Statistics ────────────────────────────────────────────────────────────────

local function median(t)
  local s = {}
  for _, v in ipairs(t) do s[#s + 1] = v end
  table.sort(s)
  local n = #s
  if n == 0 then return 0 end
  if n % 2 == 1 then return s[math.ceil(n / 2)] end
  return (s[n / 2] + s[n / 2 + 1]) / 2
end

local function mean(t)
  if #t == 0 then return 0 end
  local sum = 0
  for _, v in ipairs(t) do sum = sum + v end
  return sum / #t
end

local function minmax(t)
  if #t == 0 then return 0, 0 end
  local lo, hi = t[1], t[1]
  for _, v in ipairs(t) do
    if v < lo then lo = v end
    if v > hi then hi = v end
  end
  return lo, hi
end

-- ── Coroutine-based async runner ─────────────────────────────────────────────

local results = {}
local co

co = coroutine.create(function()
  local datasets = data.generate()

  for _, dataset in ipairs(datasets) do
    -- One scratch buffer per dataset; set lines once.
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, dataset.new_lines)
    -- Initialize per-buffer state so render.apply() can access it.
    local s = state.get(bufnr)
    local ns = s.ns

    for _, approach in ipairs(approaches.all) do
      local times = {}

      for iter = 1, WARMUP + ITERATIONS do
        render.clear(bufnr, ns)

        local t0 = vim.uv.hrtime()
        approach.run(dataset.old_lines, dataset.new_lines, bufnr, ns, function()
          local elapsed_ms = (vim.uv.hrtime() - t0) / 1e6
          if iter > WARMUP then
            times[#times + 1] = elapsed_ms
          end
          vim.schedule(function()
            coroutine.resume(co)
          end)
        end)
        coroutine.yield()
      end

      results[#results + 1] = {
        dataset = dataset.label,
        approach = approach.name,
        times = times,
      }
    end

    -- Clean up buffer
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end

  -- ── Print results ───────────────────────────────────────────────────────────

  local sep  = string.rep("─", 100)
  local dbl  = string.rep("═", 100)

  local function out(s)
    io.stdout:write(s)
    io.stdout:flush()
  end

  out("\n")
  out("Benchmark: neovim-inline-diff  |  " .. tostring(vim.version()) .. "\n")
  out(string.format("Iterations: %d (+ %d warmup)\n", ITERATIONS, WARMUP))
  out(dbl .. "\n")
  out(string.format("%-38s  %-20s  %10s  %8s  %8s  %8s\n",
    "Dataset", "Approach", "Median ms", "Min ms", "Max ms", "Mean ms"))
  out(sep .. "\n")

  local last_dataset = nil
  for _, r in ipairs(results) do
    if last_dataset and r.dataset ~= last_dataset then
      out(sep .. "\n")
    end
    last_dataset = r.dataset

    local med = median(r.times)
    local mn, mx = minmax(r.times)
    local avg = mean(r.times)
    out(string.format("%-38s  %-20s  %10.3f  %8.3f  %8.3f  %8.3f\n",
      r.dataset, r.approach, med, mn, mx, avg))
  end

  out(dbl .. "\n\n")

  vim.cmd("qa!")
end)

coroutine.resume(co)
