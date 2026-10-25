#!/usr/bin/env node
// Splits the suite's spec files into shards of about equal running time.
//
// Playwright's own --shard balances by test count, keeping each file whole
// (fullyParallel is off), so a shard of slow block-editor files took twice as
// long as a shard of quick layout checks. This assigns whole files by their
// recorded durations instead, slowest first, each to the shard with the least
// time so far. Every spec file lands in exactly one shard; stale or missing
// timings only make the shards less even.
//
//   node scripts/shards.mjs files 2/4 [tests/blocks ...]
//     Prints the spec files of shard 2 of 4, one per line, from the given
//     files and directories (default: all of tests/). Prints nothing when the
//     shard gets no files.
//
//   node scripts/shards.mjs record <timings.jsonl ...>
//     Rewrites shard-timings.json from timingReporter.js output: the mean
//     first-attempt duration of each test, summed per file. For CI's numbers,
//     download one run's legacy shard artifacts:
//       gh run download <run-id> -p 'e2e-artifacts-legacy-*' -D /tmp/e2e-timings
//       node scripts/shards.mjs record /tmp/e2e-timings/*/test-results/timings.jsonl
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const timingsFile = path.join(root, 'shard-timings.json')
// Playwright's default testMatch; playwright.config.js does not override it.
const specPattern = /\.(spec|test)\.[cm]?[jt]sx?$/

function specFiles(dir) {
  return fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap(entry => {
    const rel = `${dir}/${entry.name}`
    if (entry.isDirectory()) return specFiles(rel)
    return specPattern.test(entry.name) ? [rel] : []
  })
}

function selectedFiles(filters) {
  const all = specFiles('tests')
  if (filters.length === 0) return all

  const prefixes = filters.map(filter => path.relative(root, path.resolve(root, filter)).split(path.sep).join('/'))
  return all.filter(file => prefixes.some(prefix => file === prefix || file.startsWith(`${prefix}/`)))
}

function files(shardArg, filters) {
  const match = /^(\d+)\/(\d+)$/.exec(shardArg || '')
  const [current, total] = match ? [Number(match[1]), Number(match[2])] : []
  if (!match || total < 1 || current < 1 || current > total) {
    throw new Error(`Expected a shard as <current>/<total>, got ${shardArg}`)
  }

  const recorded = fs.existsSync(timingsFile) ? JSON.parse(fs.readFileSync(timingsFile, 'utf8')).files : {}
  const known = Object.values(recorded)
  // A file without a timing (a new spec) counts as an average file.
  const fallback = known.length ? known.reduce((sum, s) => sum + s, 0) / known.length : 1

  const weighted = selectedFiles(filters)
    .map(file => ({ file, seconds: recorded[file] ?? fallback }))
    .sort((a, b) => b.seconds - a.seconds || a.file.localeCompare(b.file))

  const shards = Array.from({ length: total }, () => ({ seconds: 0, files: [] }))
  for (const { file, seconds } of weighted) {
    const lightest = shards.reduce((min, shard) => (shard.seconds < min.seconds ? shard : min))
    lightest.seconds += seconds
    lightest.files.push(file)
  }

  const mine = shards[current - 1]
  console.error(
    `shard ${current}/${total}: ${mine.files.length} files, ~${Math.round(mine.seconds)} s ` +
      `(shards ${shards.map(shard => Math.round(shard.seconds)).join(' / ')} s)`
  )
  for (const file of mine.files.sort()) console.log(file)
}

function record(inputs) {
  if (inputs.length === 0) throw new Error('Expected one or more timings.jsonl files')

  const durations = new Map()
  for (const input of inputs) {
    for (const line of fs.readFileSync(input, 'utf8').split('\n')) {
      if (!line.trim()) continue
      const entry = JSON.parse(line)
      if (entry.event !== 'test' || entry.retry !== 0) continue
      const key = `${entry.file}\n${entry.title}`
      durations.set(key, [...(durations.get(key) || []), entry.duration])
    }
  }

  const perFile = {}
  for (const [key, runs] of durations) {
    const file = key.split('\n')[0]
    perFile[file] = (perFile[file] || 0) + runs.reduce((sum, ms) => sum + ms, 0) / runs.length / 1000
  }

  const sorted = Object.fromEntries(
    Object.keys(perFile)
      .sort()
      .map(file => [file, Math.round(perFile[file] * 10) / 10])
  )
  fs.writeFileSync(timingsFile, JSON.stringify({ files: sorted }, null, 2) + '\n')
  console.error(`Wrote ${Object.keys(sorted).length} files to ${path.relative(process.cwd(), timingsFile)}`)
}

const [command, ...args] = process.argv.slice(2)
try {
  if (command === 'files') files(args[0], args.slice(1))
  else if (command === 'record') record(args)
  else throw new Error('Usage: shards.mjs files <current>/<total> [paths...] | record <timings.jsonl...>')
} catch (error) {
  console.error(error.message)
  process.exit(1)
}
