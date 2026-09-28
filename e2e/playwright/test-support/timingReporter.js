// Write each attempt immediately: HTML/JSON reporters only finish at the end,
// so a CI job timeout otherwise loses timings for every successful test.
const fs = require('node:fs')
const path = require('node:path')

class TimingReporter {
  onBegin(config, suite) {
    this.file = path.join(config.projects[0].outputDir, 'timings.jsonl')
    fs.mkdirSync(path.dirname(this.file), { recursive: true })
    fs.writeFileSync(this.file, JSON.stringify({ event: 'begin', tests: suite.allTests().length }) + '\n')
  }

  onTestEnd(test, result) {
    fs.appendFileSync(this.file, JSON.stringify({
      event: 'test',
      file: path.relative(process.cwd(), test.location.file),
      title: test.titlePath().filter(Boolean).join(' > '),
      status: result.status,
      retry: result.retry,
      duration: result.duration,
    }) + '\n')
  }

  onEnd(result) {
    if (!this.file) return
    fs.appendFileSync(this.file, JSON.stringify({
      event: 'end', status: result.status, duration: result.duration,
    }) + '\n')
  }
}

module.exports = TimingReporter
