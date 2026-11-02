import { registerSystemVerilog, SV_LANGUAGE_ID } from './sv-language.js';
import { registerMlir, MLIR_LANGUAGE_ID } from './mlir-language.js';
import { registerLlvm } from './llvm-language.js';
import { parseSchedules, renderSchedules } from './schedule-view.js';
import { CompilerSession } from './compiler-session.js';
import { clearWaveform, loadWaveform, saveWaveform } from './waveform-storage.js';
import { CoverageView } from './coverage-view.js';
import { EXAMPLES } from './examples.js';
import { STAGES, DEFAULT_STAGE, findStage } from './stages.js';
import {
  COLOR_CHOICES, htmlSnippet, markdownSnippet, snippetSource, tokensFromListing,
} from './embed-snippet.js';
import {
  DEFAULTS, buildArgs, formatCommand, toPermalink, loadState, saveState,
} from './options.js';

const MONACO_CDN = 'https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min';

const el = (id) => document.getElementById(id);
const ui = {
  editor: el('editor'), output: el('output'), status: el('status'),
  run: el('run'), runLabel: el('runLabel'), stages: el('stages'),
  stageBlurb: el('stageBlurb'), command: el('command'),
  flagsToggle: el('flagsToggle'), flagsPanel: el('flagsPanel'),
  examples: el('examples'), handle: el('handle'), workbench: document.querySelector('.workbench'),
  share: el('share'), copyCommand: el('copyCommand'), copyOutput: el('copyOutput'),
  irEditor: el('irEditor'), scheduleView: el('scheduleView'),
  scheduleToggle: el('scheduleToggle'),
  waveformView: el('waveformView'), waveformEmpty: el('waveformEmpty'),
  surfer: el('surfer'), downloadWaveform: el('downloadWaveform'),
  coverageView: el('coverageView'), coverageEmpty: el('coverageEmpty'),
  coverageFrame: el('coverageFrame'), downloadCoverage: el('downloadCoverage'),
  embed: el('embed'), embedDialog: el('embedDialog'), embedHtml: el('embedHtml'),
  embedMarkdown: el('embedMarkdown'), embedCode: el('embedCode'),
  embedNote: el('embedNote'), copyEmbed: el('copyEmbed'), embedColors: el('embedColors'),
};

const OPTION_FIELDS = [
  'std', 'opt', 'tier', 'scheduler', 'specialization', 'coverage',
  'top', 'timescale', 'defines', 'extra',
];

let monaco = null;
let editor = null;
let irEditor = null;
let irModel = null;
let irLanguage = MLIR_LANGUAGE_ID;
let scheduleSourceHighlight = null;
const session = new CompilerSession();
let job = null;
let compilerUnavailable = false;
let compilerReady = false;
let options = { ...DEFAULTS };
let activeStage = DEFAULT_STAGE;
let busy = false;
let latestWaveform = null;
let surferReady = null;
let waveformRequest = 0;
// While a finished run's coverage report is being built: the run's status,
// shown again once the report arrives.
let coveragePending = null;
const coverage = new CoverageView({
  frame: ui.coverageFrame, empty: ui.coverageEmpty, download: ui.downloadCoverage,
});
let scheduleText = '';
let scheduleRaw = false;
let storedWaveform = null;

function restoreWaveform() {
  return storedWaveform ??= loadWaveform()
    .then((waveform) => { latestWaveform ??= waveform; })
    .catch(() => {});
}

// Results are cached per stage and dropped whenever the source or options
// change, so switching tabs is instant but never shows something stale.
const results = new Map();

/* -------------------------------------------------------------- rendering */

function setStatus(text, kind = '') {
  ui.status.textContent = text;
  ui.status.className = `status ${kind}`;
}

let consoleChunks = [];
let consoleFrame = null;

function clearConsole() {
  if (consoleFrame !== null) cancelAnimationFrame(consoleFrame);
  consoleFrame = null;
  consoleChunks = [];
  ui.output.textContent = '';
}

// Commit streamed output once per frame, with a single layout for scrolling.
function flushConsole() {
  if (consoleFrame !== null) cancelAnimationFrame(consoleFrame);
  consoleFrame = null;
  if (!consoleChunks.length) return;
  const fragment = document.createDocumentFragment();
  let node = null;
  let text = [];
  for (const chunk of consoleChunks) {
    if (!node || node.className !== chunk.className) {
      if (node) node.textContent = text.join('');
      node = document.createElement('span');
      node.className = chunk.className;
      fragment.appendChild(node);
      text = [];
    }
    text.push(chunk.text);
  }
  node.textContent = text.join('');
  consoleChunks = [];
  ui.output.appendChild(fragment);
  ui.output.scrollTop = ui.output.scrollHeight;
}

function write(text, className = '') {
  consoleChunks.push({ text, className });
  consoleFrame ??= requestAnimationFrame(flushConsole);
}

function renderCommand() {
  ui.command.textContent = formatCommand({ ...options, stage: activeStage });
}

/* ------------------------------------------------------------ diagnostics */

// slang reports as `design.sv:LINE:COL: severity: message`. Surfacing these in
// the gutter is the difference between reading a log and fixing the line.
const DIAGNOSTIC = /^(?:[^\s:]*):(\d+):(\d+):\s*(error|warning|note):\s*(.*)$/;

function applyDiagnostics(text) {
  if (!monaco || !editor) return { errors: 0, warnings: 0 };
  const markers = [];
  let errors = 0;
  let warnings = 0;

  for (const line of text.split('\n')) {
    const match = DIAGNOSTIC.exec(line.trim());
    if (!match) continue;
    const [, lineNumber, column, severity, message] = match;
    if (severity === 'error') errors++;
    else if (severity === 'warning') warnings++;
    markers.push({
      startLineNumber: Number(lineNumber),
      startColumn: Number(column),
      endLineNumber: Number(lineNumber),
      endColumn: Number(column) + 1,
      message,
      severity: severity === 'error' ? monaco.MarkerSeverity.Error
        : severity === 'warning' ? monaco.MarkerSeverity.Warning
          : monaco.MarkerSeverity.Info,
    });
  }
  monaco.editor.setModelMarkers(editor.getModel(), 'talos', markers);
  return { errors, warnings };
}

/* -------------------------------------------------------------- pipeline  */

function buildStageTabs() {
  for (const [index, stage] of STAGES.entries()) {
    const item = document.createElement('li');
    const button = document.createElement('button');
    button.className = 'stage';
    button.type = 'button';
    button.role = 'tab';
    button.dataset.stage = stage.id;
    button.title = stage.blurb;
    button.innerHTML = `<span class="ord">${String(index + 1).padStart(2, '0')}</span>`;
    button.appendChild(document.createTextNode(stage.label));
    button.addEventListener('click', () => selectStage(stage.id));
    item.appendChild(button);
    ui.stages.appendChild(item);
  }
}

function paintStageSelection() {
  let selected = null;
  for (const button of ui.stages.querySelectorAll('.stage')) {
    const isSelected = button.dataset.stage === activeStage;
    button.setAttribute('aria-selected', String(isSelected));
    if (isSelected) selected = button;
  }
  ui.stageBlurb.textContent = findStage(activeStage).blurb;
  renderCommand();
  selected?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
}

function selectStage(id) {
  activeStage = id;
  if (id !== 'waveform') waveformRequest++;
  paintStageSelection();

  const stage = findStage(id);
  if (stage.kind === 'waveform') {
    showWaveform();
    return;
  }
  if (stage.kind === 'coverage') {
    showCoverage();
    return;
  }

  showConsole();

  const cached = results.get(id);
  if (cached) {
    restore(cached);
    return;
  }
  // Landing on Run with nothing cached should not silently compile; the Run
  // button is the explicit action. Other stages compile on demand.
  if (stage.kind === 'text') compileStage(id);
  else { clearConsole(); setStatus('ready'); }
}

function restore(cached) {
  const text = cached.chunks.map((chunk) => chunk.text).join('');
  if (cached.stage === 'schedule') {
    showSchedule(text);
    setStatus(cached.status.text, cached.status.kind);
    return;
  }
  if (cached.language) {
    showIr(text, cached.language);
    setStatus(cached.status.text, cached.status.kind);
    return;
  }
  showConsole();
  clearConsole();
  for (const chunk of cached.chunks) write(chunk.text, chunk.className);
  setStatus(cached.status.text, cached.status.kind);
}

/* --------------------------------------------------------------- compiling */

let recording = null;

function record(text, className) {
  write(text, className);
  recording?.chunks.push({ text, className });
}

function finishRecording(statusText, statusKind) {
  flushConsole();
  // Replace the busy status immediately. Besides exposing the final timings,
  // changing the class removes the flashing .status.busy indicator.
  setStatus(statusText, statusKind);
  if (!recording) return;
  recording.status = { text: statusText, kind: statusKind };
  results.set(recording.stage, recording);
  recording = null;
}

function compileStage(stageId) {
  if (busy || !editor || compilerUnavailable) return;
  // A token listing for the Embed dialog holds the session for a moment.
  if (tokenJob) {
    const waiting = deferredStage !== null;
    deferredStage = stageId;
    if (!waiting) {
      tokenJob.then(() => {
        const id = deferredStage;
        deferredStage = null;
        compileStage(id);
      });
    }
    return;
  }
  const stage = findStage(stageId);
  if (stage.kind === 'binary') coverage.clear();
  showConsole();
  busy = true;
  setBusyLabel(true);
  clearConsole();
  setStatus(stage.kind === 'binary' ? 'compiling' : 'generating', 'busy');
  recording = { stage: stageId, chunks: [], status: {} };
  job = session.run({
    type: 'compile',
    source: editor.getValue(),
    args: buildArgs({ ...options, stage: stageId }),
    stage: stageId,
    kind: stage.kind,
    // With --coverage, a run also brings back its HTML coverage report.
    coverageReport: stage.kind === 'binary',
  }, onMessage);
}

function invalidate() {
  results.clear();
  scheduleSourceHighlight?.clear();
  if (monaco && editor) monaco.editor.setModelMarkers(editor.getModel(), 'talos', []);
}

function run() {
  if (busy || ui.run.disabled) return;
  activeStage = 'run';
  paintStageSelection();
  compileStage('run');
}

// Terminating the worker is the only way to end a design that never calls
// $finish. A stopped result is not cached, so revisiting the stage compiles
// again instead of replaying a partial log.
function stop() {
  job?.stop();
}

function finishRun(refreshResults = false) {
  flushConsole();
  busy = false;
  job = null;
  setBusyLabel(false);
  if (refreshResults) {
    if (activeStage === 'waveform') showWaveform();
    else if (activeStage === 'coverage') showCoverage();
  }
}

function setBusyLabel(isBusy) {
  if (compilerUnavailable && !isBusy) return;
  ui.run.disabled = false;
  ui.runLabel.textContent = isBusy ? 'Stop' : 'Run';
}

/* ----------------------------------------------------------------- worker */

let diagnosticText = '';
let compileMs = 0;
let diagnosticCounts = { errors: 0, warnings: 0 };

function warningNote(counts) {
  return counts.warnings ? `${counts.warnings} warning${counts.warnings === 1 ? '' : 's'} · ` : '';
}

async function onMessage(message) {
  switch (message.type) {
    case 'log':
      diagnosticText += message.text;
      record(message.text, message.stream === 'stderr' ? 'stderr' : '');
      break;

    case 'compiled': {
      const counts = applyDiagnostics(diagnosticText);
      diagnosticText = '';
      compileMs = Math.round(message.elapsedMs);

      if (!message.ok) {
        record(`\ncompilation failed (exit ${message.status})\n`, 'stderr');
        if (message.message) record(`${message.message}\n`, 'stderr');
        finishRecording(`${counts.errors} error${counts.errors === 1 ? '' : 's'}`, 'err');
        finishRun();
        return;
      }

      if (message.kind === 'text') {
        if (message.text) record(message.text.replace(/\s*$/, '\n'), '');
        recording.language = findStage(message.stage).language;
        finishRecording(`${warningNote(counts)}${compileMs} ms`, 'ok');
        const cached = results.get(message.stage);
        if (cached?.language && activeStage === message.stage) {
          const text = cached.chunks.map((chunk) => chunk.text).join('');
          if (message.stage === 'schedule') showSchedule(text);
          else showIr(text, cached.language);
        }
        finishRun();
        return;
      }

      diagnosticCounts = counts;
      record(`compiled ${formatBytes(message.byteLength)} in ${compileMs} ms\n\n`, 'note');
      setStatus('running', 'busy');
      break;
    }

    case 'output':
      record(message.text, message.stream === 'stderr' ? 'stderr' : '');
      break;

    case 'exited':
      await finishSimulation(message);
      // The run is recorded; its coverage report follows.
      if (message.coveragePending) {
        coveragePending = {
          status: ui.status.textContent,
          kind: ui.status.className.replace(/^status\s*/, ''),
        };
        setStatus('building coverage report', 'busy');
        break;
      }
      finishRun(message.error === undefined);
      break;

    case 'coverage':
      noteCoverage(message);
      setStatus(coveragePending.status, coveragePending.kind);
      coveragePending = null;
      finishRun(true);
      break;

    case 'failed':
      diagnosticText = '';
      if (coveragePending) {
        // The worker broke while building the report; the run is kept.
        noteCoverage({ coverageError: message.message });
        setStatus('coverage report failed', 'err');
        coveragePending = null;
        finishRun(true);
        break;
      }
      record(`\n${message.message}\n`, 'stderr');
      finishRecording('failed', 'err');
      finishRun();
      break;

    case 'stopped':
      diagnosticText = '';
      recording = null;
      if (coveragePending) {
        // The run itself finished and is kept; only its report is lost.
        noteCoverage({ coverageError: 'stopped before the report was ready' });
        setStatus('coverage report stopped', 'err');
        coveragePending = null;
        finishRun(true);
        break;
      }
      write('\nstopped\n', 'stderr');
      setStatus('stopped', 'err');
      finishRun();
      break;
  }
}

/**
 * A run's coverage report, or why it has none. The report can arrive after
 * the run was recorded, so the note is added to the run's cached log too.
 */
function noteCoverage(result) {
  let note;
  if (result.coverage) {
    coverage.update(result.coverage);
    note = ['coverage report ready in the Coverage tab\n', 'note'];
  } else if (result.coverageError) {
    coverage.fail(result.coverageError);
    note = [`coverage report failed: ${result.coverageError}\n`, 'stderr'];
  } else {
    return;
  }
  if (recording) record(...note);
  else {
    write(...note);
    results.get('run')?.chunks.push({ text: note[0], className: note[1] });
  }
}

async function finishSimulation(result) {
  const { code, error, simulatedTime, files } = result;
  if (error !== undefined) {
    record(`\nsimulation aborted: ${error}\n`, 'stderr');
    noteCoverage(result);
    finishRecording('aborted', 'err');
    return;
  }
  const waveform = files.find((file) => isVcd(file));
  await storedWaveform;
  storedWaveform = Promise.resolve();
  latestWaveform = null;
  if (waveform) {
    latestWaveform = { ...waveform, createdAt: Date.now() };
    let saved = true;
    try {
      await saveWaveform(latestWaveform);
    } catch {
      saved = false;
    }
    record(
      `${saved ? 'saved' : 'captured'} ${displayFilename(waveform.name)} ` +
      `(${formatBytes(waveform.data.byteLength)})${saved ? ' locally' : ''}\n`,
      'note',
    );
  } else {
    try {
      await clearWaveform();
    } catch {
      // The in-memory result is still cleared if browser storage is unavailable.
    }
  }
  noteCoverage(result);
  record(`\nexited with code ${code}\n`, code === 0 ? 'good' : 'stderr');
  const note = warningNote(diagnosticCounts);
  const runMs = Math.round(result.runMs);
  const simulated = simulatedTime
    ? ` · simulated ${formatSimulatedTime(simulatedTime)}`
    : '';
  finishRecording(
    `${note}compile ${compileMs} ms · run ${runMs} ms${simulated}`,
    code === 0 ? 'ok' : 'err',
  );
}

function isVcd(file) {
  const prefix = new TextDecoder().decode(file.data.subarray(0, 4096));
  const header = prefix.includes('$date') && prefix.includes('$version');
  return header && (/\.vcd$/i.test(file.name) || prefix.includes('$scope'));
}

function displayFilename(path) {
  return path.split(/[\\/]/).filter(Boolean).at(-1) ?? 'dump.vcd';
}

function showView(view) {
  scheduleSourceHighlight?.clear();
  for (const panel of [ui.output, ui.irEditor, ui.scheduleView, ui.waveformView, ui.coverageView]) {
    panel.hidden = panel !== view;
  }
  ui.downloadCoverage.hidden = true;
  ui.scheduleToggle.hidden = true;
  ui.copyOutput.hidden = view === ui.waveformView || view === ui.coverageView;
  ui.downloadWaveform.hidden = true;
}

function showConsole() { showView(ui.output); }

function showIr(text, language = MLIR_LANGUAGE_ID) {
  showView(ui.irEditor);
  if (monaco && !irEditor) initIrEditor();
  if (monaco && irModel && language !== irLanguage) {
    monaco.editor.setModelLanguage(irModel, language);
    irLanguage = language;
  }
  irModel?.setValue(text);
  requestAnimationFrame(() => irEditor?.layout());
}

function showSchedule(text) {
  scheduleText = text;
  if (scheduleRaw) {
    showIr(text, text.trimStart().startsWith('{') ? 'json' : MLIR_LANGUAGE_ID);
    ui.scheduleToggle.hidden = false;
    ui.scheduleToggle.textContent = 'View graph';
    return;
  }
  try {
    const schedules = parseSchedules(text);
    renderSchedules(ui.scheduleView, schedules, {
      onSourceLocation: revealScheduleSource,
      onSourceDeselected: () => scheduleSourceHighlight?.clear(),
    });
  } catch (error) {
    console.error('could not visualize schedule', error);
    showIr(text);
    return;
  }
  showView(ui.scheduleView);
  ui.scheduleToggle.hidden = false;
  ui.scheduleToggle.textContent = 'View IR';
}

function revealScheduleSource(location) {
  if (!editor) return;
  const model = editor.getModel();
  const line = Math.max(1, Math.min(location.line, model.getLineCount()));
  scheduleSourceHighlight?.set([{
    range: new monaco.Range(line, 1, line, model.getLineMaxColumn(line)),
    options: {
      isWholeLine: true,
      className: 'scheduleSourceLine',
      linesDecorationsClassName: 'scheduleSourceLineMarker',
    },
  }]);
  editor.setPosition({
    lineNumber: line,
    column: Math.max(1, Math.min(location.column, model.getLineMaxColumn(line))),
  });
  editor.revealLineInCenter(line);
}

function ensureSurfer() {
  if (surferReady) return surferReady;
  const loading = new Promise((resolve, reject) => {
    let timeout;
    const finish = (callback, value) => {
      clearTimeout(timeout);
      window.removeEventListener('message', onMessage);
      callback(value);
    };
    const onMessage = (event) => {
      if (event.source !== ui.surfer.contentWindow) return;
      if (event.origin !== 'null') return;
      if (event.data?.type === 'surfer-ready') finish(resolve);
      else if (event.data?.type === 'surfer-error') {
        finish(reject, new Error(event.data.message || 'Surfer failed to load'));
      }
    };
    timeout = setTimeout(() => finish(
      reject, new Error('Surfer did not load within 30 seconds'),
    ), 30_000);
    window.addEventListener('message', onMessage);
    ui.surfer.src = `./surfer.html?parentOrigin=${encodeURIComponent(location.origin)}`;
  });
  surferReady = loading.catch((error) => {
    surferReady = null;
    throw error;
  });
  return surferReady;
}

function showCoverage() {
  showView(ui.coverageView);
  const status = coverage.show(options.coverage === 'on');
  if (options.coverage === 'on' && busy &&
      (recording?.stage === 'run' || coveragePending)) {
    ui.coverageEmpty.textContent = 'Waiting for this run’s coverage report…';
    setStatus('waiting for coverage', 'busy');
    return;
  }
  setStatus(status.text, status.kind);
}

async function showWaveform() {
  const request = ++waveformRequest;
  showView(ui.waveformView);
  ui.downloadWaveform.hidden = !latestWaveform;
  ui.surfer.hidden = true;
  ui.waveformEmpty.hidden = false;
  ui.waveformEmpty.textContent = 'Loading the latest waveform saved in this browser…';
  setStatus('loading', 'busy');

  await restoreWaveform();
  if (request !== waveformRequest || activeStage !== 'waveform') return;
  if (!latestWaveform) {
    ui.waveformEmpty.textContent =
      'No waveform yet. Add $dumpvars to the design and run it; $dumpfile is optional.';
    setStatus('no VCD');
    return;
  }

  ui.downloadWaveform.hidden = false;
  ui.waveformEmpty.textContent = 'Loading Surfer…';
  try {
    await ensureSurfer();
    if (request !== waveformRequest || activeStage !== 'waveform') return;
    const buffer = latestWaveform.data.slice().buffer;
    ui.surfer.contentWindow.postMessage(
      { type: 'load-waveform', buffer },
      '*',
      [buffer],
    );
    ui.waveformEmpty.hidden = true;
    ui.surfer.hidden = false;
    const name = displayFilename(latestWaveform.name);
    setStatus(`${name} · ${formatBytes(latestWaveform.data.byteLength)}`, 'ok');
  } catch (error) {
    if (request !== waveformRequest || activeStage !== 'waveform') return;
    ui.waveformEmpty.textContent = `Waveform viewer unavailable: ${error?.message ?? error}`;
    setStatus('viewer unavailable', 'err');
  }
}

/* ----------------------------------------------------------------- editor */

function loadMonaco() {
  return new Promise((resolve, reject) => {
    const loader = document.createElement('script');
    loader.src = `${MONACO_CDN}/vs/loader.js`;
    loader.onload = () => {
      window.require.config({ paths: { vs: `${MONACO_CDN}/vs` } });
      window.require(['vs/editor/editor.main'], () => resolve(window.monaco), reject);
    };
    loader.onerror = () => reject(new Error('the editor failed to load'));
    document.head.appendChild(loader);
  });
}

async function initEditor(initialSource) {
  monaco = await loadMonaco();
  registerSystemVerilog(monaco);

  // Dracula, following the official palette's part of speech: pink keywords,
  // cyan italic types, green functions, purple numbers, yellow strings.
  // Comments and line numbers use brighter secondary ink for text contrast.
  monaco.editor.defineTheme('talos-dracula', {
    base: 'vs-dark',
    inherit: true,
    rules: [
      { token: 'keyword', foreground: 'ff79c6' },
      { token: 'type', foreground: '8be9fd', fontStyle: 'italic' },
      { token: 'predefined', foreground: '50fa7b' },
      { token: 'keyword.directive', foreground: 'ff79c6' },
      { token: 'comment', foreground: 'b9bcce', fontStyle: 'italic' },
      { token: 'number', foreground: 'bd93f9' },
      { token: 'number.hex', foreground: 'bd93f9' },
      { token: 'number.binary', foreground: 'bd93f9' },
      { token: 'number.octal', foreground: 'bd93f9' },
      { token: 'number.float', foreground: 'bd93f9' },
      { token: 'string', foreground: 'f1fa8c' },
      { token: 'string.escape', foreground: 'ff79c6' },
      { token: 'operator', foreground: 'ff79c6' },
      { token: 'delimiter', foreground: 'f8f8f2' },
      { token: 'identifier', foreground: 'f8f8f2' },
      { token: 'variable', foreground: '8be9fd' },
      { token: 'tag', foreground: 'bd93f9' },
      { token: 'function', foreground: '50fa7b' },
      { token: 'annotation', foreground: 'ffb86c' },
    ],
    colors: {
      'editor.background': '#282a36',
      'editor.foreground': '#f8f8f2',
      'editorLineNumber.foreground': '#b9bcce',
      'editorLineNumber.dimmedForeground': '#b9bcce',
      'editorLineNumber.activeForeground': '#f8f8f2',
      'editor.lineHighlightBackground': '#44475a45',
      'editor.selectionBackground': '#383a49',
      'editor.inactiveSelectionBackground': '#383a49',
      'editorBracketHighlight.foreground1': '#f1fa8c',
      'editorBracketHighlight.foreground2': '#bd93f9',
      'editorBracketHighlight.foreground3': '#8be9fd',
      'editorBracketHighlight.foreground4': '#ff79c6',
      'editorBracketHighlight.foreground5': '#50fa7b',
      'editorBracketHighlight.foreground6': '#ffb86c',
      'editorCursor.foreground': '#f8f8f2',
      'editorIndentGuide.background1': '#3b3d4c',
      'editorWidget.background': '#21222c',
      'editorError.foreground': '#ff5555',
      'editorWarning.foreground': '#ffb86c',
    },
  });

  editor = monaco.editor.create(ui.editor, {
    value: initialSource,
    language: SV_LANGUAGE_ID,
    theme: 'talos-dracula',
    fontSize: 13,
    fontFamily: '"IBM Plex Mono", ui-monospace, monospace',
    minimap: { enabled: false },
    scrollBeyondLastLine: false,
    automaticLayout: true,
    tabSize: 2,
    padding: { top: 12 },
    smoothScrolling: true,
  });
  scheduleSourceHighlight = editor.createDecorationsCollection();

  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter, run);
  editor.onDidChangeModelContent(() => {
    const source = editor.getValue();
    const exampleIndex = EXAMPLES.findIndex(
      (example) => example.source === source,
    );
    ui.examples.value = exampleIndex < 0 ? '' : String(exampleIndex);
    invalidate();
    // Waveforms and coverage describe the last run, not the edited source.
    if (activeStage === 'waveform' || activeStage === 'coverage') {
      waveformRequest++;
      activeStage = 'run';
      paintStageSelection();
      showConsole();
      clearConsole();
      if (!busy) setStatus('ready');
    }
    persist();
  });
}

function initIrEditor() {
  registerMlir(monaco);
  registerLlvm(monaco);
  irModel = monaco.editor.createModel('', MLIR_LANGUAGE_ID);
  irEditor = monaco.editor.create(ui.irEditor, {
    model: irModel,
    theme: 'talos-dracula',
    readOnly: true,
    domReadOnly: true,
    fontSize: 12.5,
    lineHeight: 20,
    fontFamily: '"IBM Plex Mono", ui-monospace, monospace',
    minimap: { enabled: false },
    automaticLayout: true,
    scrollBeyondLastLine: false,
    renderLineHighlight: 'none',
    folding: true,
    wordWrap: 'off',
    padding: { top: 12, bottom: 12 },
  });
}

/* ---------------------------------------------------------------- options */

function readOptions() {
  for (const field of OPTION_FIELDS) options[field] = el(field).value;
}

function writeOptions() {
  for (const field of OPTION_FIELDS) el(field).value = options[field];
}

let persistTimer = null;

function flushState() {
  if (persistTimer === null) return;
  clearTimeout(persistTimer);
  persistTimer = null;
  if (editor) saveState(editor.getValue(), { ...options, stage: activeStage });
}

function persist() {
  clearTimeout(persistTimer);
  persistTimer = setTimeout(flushState, 250);
}

function initOptions() {
  for (const field of OPTION_FIELDS) {
    el(field).addEventListener('input', () => {
      readOptions();
      invalidate();
      renderCommand();
      persist();
    });
  }

  ui.flagsToggle.addEventListener('click', () => {
    const open = ui.flagsPanel.hasAttribute('hidden');
    ui.flagsPanel.toggleAttribute('hidden', !open);
    ui.flagsToggle.setAttribute('aria-expanded', String(open));
  });
}

/* ------------------------------------------------------------------ chrome */

async function copy(text, button) {
  const original = button.textContent;
  try {
    await navigator.clipboard.writeText(text);
    button.textContent = 'Copied';
  } catch {
    button.textContent = 'Press ⌘C';
  }
  setTimeout(() => { button.textContent = original; }, 1400);
}

function initChrome(initialSource) {
  ui.run.addEventListener('click', () => (busy ? stop() : run()));
  ui.copyCommand.addEventListener('click', () =>
    copy(formatCommand({ ...options, stage: activeStage }), ui.copyCommand));
  ui.scheduleToggle.addEventListener('click', () => {
    scheduleRaw = !scheduleRaw;
    showSchedule(scheduleText);
  });
  ui.copyOutput.addEventListener('click', () => {
    flushConsole();
    copy(!ui.scheduleView.hidden ? scheduleText
      : ui.irEditor.hidden ? ui.output.textContent : irModel.getValue(), ui.copyOutput);
  });
  ui.downloadWaveform.addEventListener('click', () => {
    if (!latestWaveform) return;
    const url = URL.createObjectURL(new Blob(
      [latestWaveform.data], { type: 'text/x-vcd' },
    ));
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = displayFilename(latestWaveform.name);
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(url));
  });
  ui.downloadCoverage.addEventListener('click', () => coverage.save(document));
  ui.share.addEventListener('click', () => {
    if (!editor) return;
    const link = toPermalink(editor.getValue(), { ...options, stage: activeStage });
    history.replaceState(null, '', link);
    copy(link, ui.share);
  });
  initEmbed();

  window.addEventListener('pagehide', flushState);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) flushState();
  });

  for (const [index, example] of EXAMPLES.entries()) {
    const option = document.createElement('option');
    option.value = String(index);
    option.textContent = example.name;
    ui.examples.appendChild(option);
  }
  const initialExampleIndex = EXAMPLES.findIndex(
    (example) => example.source === initialSource,
  );
  ui.examples.value = initialExampleIndex < 0 ? '' : String(initialExampleIndex);
  ui.examples.addEventListener('change', () => {
    if (ui.examples.value === '') return;
    const example = EXAMPLES[Number(ui.examples.value)];
    if (example && editor) {
      editor.setValue(example.source);
      editor.focus();
    }
  });

  document.addEventListener('keydown', (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
      event.preventDefault();
      run();
    }
  });

  initHandle();
  initPipelineScroll();
}

const EMBED_NOTES = {
  light: 'Colors are built in, so the block looks the same on any site. ' +
    'Include the script once per page.',
  dark: 'Colors are built in, for sites with a dark background. ' +
    'Include the script once per page.',
  plain: 'No built-in colors: your site\'s highlighter styles the block, or ' +
    'the script colors it to match the page. Include the script once per page.',
  markdown: 'For Jekyll, Hugo, MkDocs, and other site generators that allow ' +
    'raw HTML. Include the script once, in your layout. GitHub strips ' +
    'scripts, so Run does not appear there.',
};

const EMBED_STORAGE_KEY = 'talos.embed';

// Baked snippet colors come from the compiler's own lexer, so they agree with
// how Talos reads the design. Listing tokens is a short job on the shared
// session once the compiler has loaded; while it is still downloading, when a
// run holds the session, or when the compiler is unavailable, it resolves to
// null and the built-in tokenizer colors the snippet instead.
let tokenJob = null;
let deferredStage = null;

function listTokens(source, std) {
  if (!compilerReady || busy || session.busy) return Promise.resolve(null);
  tokenJob = new Promise((resolve) => {
    session.run({
      type: 'compile',
      source,
      args: ['-dump-tokens', `--std=${std}`],
      stage: 'tokens',
      kind: 'text',
    }, (message) => {
      if (message.type === 'compiled') {
        resolve(message.ok ? tokensFromListing(source, message.text) : null);
      } else if (message.type === 'failed' || message.type === 'stopped') {
        resolve(null);
      }
    });
  }).finally(() => { tokenJob = null; });
  return tokenJob;
}

function initEmbed() {
  let format = 'html';
  let colors = 'light';
  try {
    const saved = JSON.parse(localStorage.getItem(EMBED_STORAGE_KEY) ?? 'null');
    if (COLOR_CHOICES.includes(saved?.colors)) colors = saved.colors;
  } catch {
    // Unreadable storage: keep the default.
  }

  // Listings are cached per language version and source; the dialog is modal,
  // so neither changes while it is open.
  let listed = { key: null, tokens: null, pending: false };

  const render = () => {
    const source = editor.getValue();
    const html = format === 'html';
    const baked = html && colors !== 'plain';
    const key = `${options.std}\n${snippetSource(source)}`;
    if (baked && listed.key !== key) {
      listed = { key, tokens: null, pending: true };
      const request = listed;
      listTokens(snippetSource(source), options.std).then((tokens) => {
        if (listed !== request) return;
        listed = { key, tokens, pending: false };
        render();
      });
    }
    const input = {
      source,
      options,
      runnerUrl: new URL('runner.js', window.location.href).href,
      colors,
      tokens: listed.key === key ? listed.tokens : null,
    };
    const pending = baked && listed.pending;
    ui.embedCode.textContent = html ? htmlSnippet(input) : markdownSnippet(input);
    ui.embedNote.textContent = pending
      ? 'Coloring with the compiler\'s lexer…'
      : EMBED_NOTES[html ? colors : 'markdown'];
    ui.copyEmbed.disabled = pending;
    ui.embedHtml.setAttribute('aria-selected', String(html));
    ui.embedMarkdown.setAttribute('aria-selected', String(!html));
    // A Markdown fence cannot carry colors.
    ui.embedColors.hidden = !html;
    for (const button of ui.embedColors.querySelectorAll('[data-colors]')) {
      button.setAttribute('aria-checked', String(button.dataset.colors === colors));
    }
  };
  const choose = (next) => { format = next; render(); };

  ui.embedColors.addEventListener('click', (event) => {
    const choice = event.target.closest('[data-colors]')?.dataset.colors;
    if (!choice) return;
    colors = choice;
    render();
    try {
      localStorage.setItem(EMBED_STORAGE_KEY, JSON.stringify({ colors }));
    } catch {
      // Private browsing or a full quota: the choice just is not remembered.
    }
  });

  ui.embed.addEventListener('click', () => {
    if (!editor) return;
    // A listing that fell back (busy or failed compiler) is retried on open.
    if (!listed.pending && !listed.tokens) listed = { key: null, tokens: null, pending: false };
    render();
    ui.embedDialog.showModal();
  });
  ui.embedHtml.addEventListener('click', () => choose('html'));
  ui.embedMarkdown.addEventListener('click', () => choose('markdown'));
  ui.copyEmbed.addEventListener('click', () =>
    copy(ui.embedCode.textContent, ui.copyEmbed));
  // Clicks on the backdrop are dispatched to the dialog itself, as are clicks
  // in its own margins, so tell them apart by position. The press must start
  // there too: a text selection dragged out of the snippet can end with a
  // click on the dialog.
  const onBackdrop = (event) => {
    if (event.target !== ui.embedDialog) return false;
    const box = ui.embedDialog.getBoundingClientRect();
    return event.clientX < box.left || event.clientX > box.right ||
      event.clientY < box.top || event.clientY > box.bottom;
  };
  let pressedBackdrop = false;
  ui.embedDialog.addEventListener('pointerdown', (event) => {
    pressedBackdrop = onBackdrop(event);
  });
  ui.embedDialog.addEventListener('click', (event) => {
    if (pressedBackdrop && onBackdrop(event)) ui.embedDialog.close();
    pressedBackdrop = false;
  });
}

function initPipelineScroll() {
  const pipeline = ui.stages.closest('.pipeline');
  let pointerId = null;
  let startX = 0;
  let startScrollLeft = 0;
  let dragged = false;

  // Touch already gets native momentum scrolling. Mouse users need an
  // equivalent when a narrow desktop window clips the tab strip.
  const updateDraggable = () => pipeline.classList.toggle(
    'canDrag', pipeline.scrollWidth > pipeline.clientWidth + 1,
  );
  const resizeObserver = new ResizeObserver(updateDraggable);
  resizeObserver.observe(pipeline);
  resizeObserver.observe(ui.stages);
  requestAnimationFrame(updateDraggable);

  pipeline.addEventListener('pointerdown', (event) => {
    if (!pipeline.classList.contains('canDrag')
        || event.pointerType !== 'mouse' || event.button !== 0) return;
    pointerId = event.pointerId;
    startX = event.clientX;
    startScrollLeft = pipeline.scrollLeft;
    dragged = false;
  });
  pipeline.addEventListener('pointermove', (event) => {
    if (event.pointerId !== pointerId) return;
    const distance = event.clientX - startX;
    if (Math.abs(distance) < 4 && !dragged) return;
    dragged = true;
    pipeline.setPointerCapture(pointerId);
    pipeline.classList.add('isDragging');
    pipeline.scrollLeft = startScrollLeft - distance;
    event.preventDefault();
  });
  const stopDragging = (event) => {
    if (event.pointerId !== pointerId) return;
    if (pipeline.hasPointerCapture(pointerId)) pipeline.releasePointerCapture(pointerId);
    pointerId = null;
    pipeline.classList.remove('isDragging');
  };
  pipeline.addEventListener('pointerup', stopDragging);
  pipeline.addEventListener('pointercancel', stopDragging);
  pipeline.addEventListener('click', (event) => {
    if (!dragged) return;
    event.preventDefault();
    event.stopPropagation();
    dragged = false;
  }, true);
}

function initHandle() {
  let dragging = false;
  const stackedMedia = window.matchMedia('(max-width: 860px)');
  const stacked = () => stackedMedia.matches;

  // Inline grid tracks set by dragging outrank media-query styles. Clear the
  // track for the old axis when crossing the breakpoint so rotating a phone or
  // resizing a browser cannot leave the workbench in a three-column mobile
  // layout (or a three-row desktop layout).
  const syncOrientation = () => {
    if (stacked()) ui.workbench.style.gridTemplateColumns = '';
    else ui.workbench.style.gridTemplateRows = '';
    ui.handle.setAttribute('aria-orientation', stacked() ? 'horizontal' : 'vertical');
  };

  const move = (event) => {
    if (!dragging) return;
    const rect = ui.workbench.getBoundingClientRect();
    const fraction = stacked()
      ? (event.clientY - rect.top) / rect.height
      : (event.clientX - rect.left) / rect.width;
    const clamped = Math.min(0.85, Math.max(0.15, fraction));
    if (stacked()) ui.workbench.style.gridTemplateRows = `${clamped}fr 5px ${1 - clamped}fr`;
    else ui.workbench.style.gridTemplateColumns = `${clamped}fr 5px ${1 - clamped}fr`;
  };

  ui.handle.addEventListener('pointerdown', (event) => {
    dragging = true;
    ui.handle.setPointerCapture(event.pointerId);
    document.body.style.userSelect = 'none';
  });
  const stopDragging = (event) => {
    dragging = false;
    if (ui.handle.hasPointerCapture(event.pointerId))
      ui.handle.releasePointerCapture(event.pointerId);
    document.body.style.userSelect = '';
  };
  ui.handle.addEventListener('pointerup', stopDragging);
  ui.handle.addEventListener('pointercancel', stopDragging);
  ui.handle.addEventListener('pointermove', move);
  stackedMedia.addEventListener('change', syncOrientation);
  syncOrientation();
}

/* -------------------------------------------------------------------- misc */

// Simulated time is reported as a tick count plus the design's precision in
// femtoseconds, which is the only pair that survives the module boundary. Pick
// the largest unit that leaves a value at or above one, so a nanosecond design
// reads in nanoseconds rather than as a large femtosecond count.
const TIME_UNITS = [
  [1000000000000000n, 's'],
  [1000000000000n, 'ms'],
  [1000000000n, 'us'],
  [1000000n, 'ns'],
  [1000n, 'ps'],
  [1n, 'fs'],
];

function formatSimulatedTime({ ticks, precisionFs }) {
  const femtoseconds = ticks * precisionFs;
  if (femtoseconds === 0n) return '0 s';
  for (const [scale, unit] of TIME_UNITS) {
    if (femtoseconds < scale) continue;
    const whole = femtoseconds / scale;
    const remainder = femtoseconds % scale;
    if (remainder === 0n) return `${whole} ${unit}`;
    // Three decimals is enough to distinguish adjacent units without
    // implying precision the timescale does not have.
    const fraction = (remainder * 1000n) / scale;
    return `${whole}.${fraction.toString().padStart(3, '0')} ${unit}`;
  }
  return `${femtoseconds} fs`;
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

async function main() {
  // Download the compiler while Monaco loads. Handle a failed preload below,
  // even if it rejects before the editor has finished loading.
  const compiler = Promise.resolve().then(() => session.preload());
  compiler.catch(() => {});
  const saved = loadState();
  if (saved) {
    options = { ...saved.options };
    activeStage = saved.options.stage ?? DEFAULT_STAGE;
  }
  const initialSource = saved?.source ?? EXAMPLES[0].source;

  buildStageTabs();
  writeOptions();
  paintStageSelection();
  initOptions();
  initChrome(initialSource);

  setStatus('loading editor', 'busy');
  try {
    await initEditor(initialSource);
  } catch (error) {
    session.cancelPreload();
    setStatus('editor failed', 'err');
    write(`${error.message}\n`, 'stderr');
    return;
  }

  setStatus('loading compiler', 'busy');
  try {
    await compiler;
  } catch (error) {
    compilerUnavailable = true;
    ui.run.disabled = true;
    ui.runLabel.textContent = 'Unavailable';
    setStatus('compiler unavailable', 'err');
    write(`\n${error.message}\n`, 'stderr');
    return;
  }
  compilerReady = true;
  if (busy) return;
  setBusyLabel(false);
  if (findStage(activeStage).kind === 'waveform') showWaveform();
  else if (findStage(activeStage).kind === 'coverage') showCoverage();
  else setStatus('ready');
}

main();
