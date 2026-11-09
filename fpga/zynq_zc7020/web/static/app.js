// =========================================================================
// app.js -- Viterbi Decoder FPGA Demo frontend (Multi-K, Job Queue)
// =========================================================================

const API_BASE = "";

// Elements
const messageInput = document.getElementById("message-input");
const sendBtn = document.getElementById("send-btn");
const errorSlider = document.getElementById("error-slider");
const errorValue = document.getElementById("error-value");
const statusIndicator = document.getElementById("status-indicator");
const statusText = document.getElementById("status-text");
const kSelect = document.getElementById("k-select");
const modeToggleBtn = document.getElementById("mode-toggle-btn");
const subtitle = document.getElementById("subtitle");
const footerText = document.getElementById("footer-text");
const activityLog = document.getElementById("activity-log");
const queueIndicator = document.getElementById("queue-indicator");

let currentMode = "Software";

// Update error rate display
errorSlider.addEventListener("input", () => {
    errorValue.textContent = errorSlider.value + "%";
});

// Enter key sends
messageInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") runDecode();
});

// K selector — no longer triggers switch_k, just selects for next decode
kSelect.addEventListener("change", () => {
    const k = parseInt(kSelect.value);
    const cfg = {3: {d: 12}, 5: {d: 24}, 7: {d: 42}, 9: {d: 60}};
    updateKDisplay(k, cfg[k] ? cfg[k].d : "?", "");
});

// =========================================================================
// Check FPGA status on load
// =========================================================================
async function checkStatus() {
    try {
        const resp = await fetch(API_BASE + "/api/status");
        const data = await resp.json();

        currentMode = data.mode;

        if (data.programmed) {
            statusIndicator.className = "indicator on";
            statusText.textContent = `FPGA Ready (${data.mode}, K=${data.fpga_k || data.k} loaded)`;
        } else if (data.fpga_available) {
            statusIndicator.className = "indicator warn";
            statusText.textContent = "FPGA available — will auto-program on first decode";
        } else {
            statusIndicator.className = "indicator warn";
            statusText.textContent = `${data.mode} mode (K=${data.k})`;
        }

        kSelect.value = String(data.k);
        updateKDisplay(data.k, data.traceback_depth, data.polynomials);

        if (data.k_options) {
            for (const opt of kSelect.options) {
                const kInfo = data.k_options[opt.value];
                if (kInfo) {
                    const swOnly = !kInfo.bitstream_found && data.mode === "FPGA";
                    opt.textContent = kInfo.label + (swOnly ? " (SW only)" : "");
                }
            }
        }

        if (data.queue_depth > 0) {
            queueIndicator.textContent = `(${data.queue_depth} in queue)`;
        } else {
            queueIndicator.textContent = "";
        }

        updateModeToggle();
    } catch (e) {
        statusIndicator.className = "indicator off";
        statusText.textContent = "Server not connected";
    }
}

function updateKDisplay(k, d, polynomials) {
    const states = Math.pow(2, k - 1);
    subtitle.textContent = `K=${k}, Rate-1/2, ${states} states — ${polynomials || ""}`;
    footerText.textContent =
        `Viterbi Decoder — K=${k}, Rate-1/2, Traceback=${d || "?"} — Running on PYNQ-Z2 (Zynq ZC7020)`;
}

function updateModeToggle() {
    modeToggleBtn.textContent = currentMode === "FPGA"
        ? "Switch to Software" : "Switch to FPGA";
}

// =========================================================================
// Toggle mode
// =========================================================================
async function toggleMode() {
    const newMode = currentMode === "FPGA" ? "software" : "fpga";
    modeToggleBtn.disabled = true;
    statusText.textContent = `Switching to ${newMode} mode...`;

    try {
        const resp = await fetch(API_BASE + "/api/set_mode", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ mode: newMode })
        });
        const data = await resp.json();
        if (data.error) {
            statusText.textContent = "Error: " + data.error;
        } else {
            currentMode = data.mode;
            statusText.textContent = data.message;
            updateModeToggle();
        }
        await checkStatus();
    } catch (e) {
        statusText.textContent = "Error: " + e.message;
    } finally {
        modeToggleBtn.disabled = false;
    }
}

// =========================================================================
// Program FPGA
// =========================================================================
async function programFPGA() {
    statusText.textContent = "Programming FPGA...";
    statusIndicator.className = "indicator warn";

    try {
        const resp = await fetch(API_BASE + "/api/program", { method: "POST" });
        const data = await resp.json();
        if (data.success) {
            statusIndicator.className = "indicator on";
            statusText.textContent = "FPGA Programmed!";
        } else {
            statusIndicator.className = "indicator off";
            statusText.textContent = data.message || "Programming failed";
        }
    } catch (e) {
        statusIndicator.className = "indicator off";
        statusText.textContent = "Error: " + e.message;
    }
}

// =========================================================================
// Poll job status (FPGA async mode)
// =========================================================================
async function pollJob(jobId) {
    const POLL_MS = 500;
    const MAX_POLLS = 120;  // 60s max

    for (let i = 0; i < MAX_POLLS; i++) {
        try {
            const resp = await fetch(API_BASE + "/api/job/" + jobId);
            const data = await resp.json();

            // Update status bar with job progress
            if (data.status === "queued") {
                sendBtn.textContent = `Queued (#${data.position})...`;
                statusText.textContent = `Queue position: ${data.position} of ${data.queue_depth + 1}`;
            } else if (data.status === "programming") {
                sendBtn.textContent = `Programming K=${data.k}...`;
                statusText.textContent = `Programming FPGA for K=${data.k}...`;
                statusIndicator.className = "indicator warn";
            } else if (data.status === "decoding") {
                sendBtn.textContent = "Decoding...";
                statusText.textContent = `FPGA decoding (K=${data.k})...`;
            } else if (data.status === "done") {
                statusIndicator.className = "indicator on";
                statusText.textContent = `FPGA Ready (K=${data.k} loaded)`;
                return data.result;
            } else if (data.status === "error") {
                statusIndicator.className = "indicator off";
                statusText.textContent = data.result?.error || "Job failed";
                return null;
            }
        } catch (e) {
            // Network blip — keep polling
        }
        await new Promise(r => setTimeout(r, POLL_MS));
    }
    statusText.textContent = "Job timed out";
    return null;
}

// =========================================================================
// Run decode (sends per-request K)
// =========================================================================
async function runDecode() {
    const message = messageInput.value.trim();
    if (!message) return;

    const selectedK = parseInt(kSelect.value);

    sendBtn.disabled = true;
    sendBtn.textContent = "Decoding...";
    document.body.classList.add("loading");

    try {
        const resp = await fetch(API_BASE + "/api/decode", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                message: message,
                error_rate: parseInt(errorSlider.value),
                k: selectedK,
                trellis: document.getElementById("trellis-check").checked
            })
        });

        const data = await resp.json();
        if (data.error) {
            alert(data.error);
            return;
        }

        let result;
        if (data.async && data.job_id) {
            // FPGA mode: poll for result
            result = await pollJob(data.job_id);
        } else {
            // Software mode: instant result
            result = data;
        }

        if (result) {
            updatePipeline(result);
            updateSymbolGrid(result);
            updateResults(result);
            updateTrellis(result);
        }

        // Refresh activity log
        fetchActivity();

    } catch (e) {
        alert("Error: " + e.message);
    } finally {
        sendBtn.disabled = false;
        sendBtn.textContent = "Decode";
        document.body.classList.remove("loading");
    }
}

// =========================================================================
// Update pipeline visualization
// =========================================================================
function updatePipeline(data) {
    document.getElementById("pipe-input").textContent = data.input_text;
    document.getElementById("pipe-bits").textContent = data.info_bits + " bits";
    document.getElementById("pipe-encoded").textContent = data.num_symbols + " syms";
    document.getElementById("pipe-noise").textContent =
        data.num_errors_injected + " errors";
    document.getElementById("pipe-decoded").textContent =
        data.decode_method + " " + data.decode_time_ms + "ms";
    document.getElementById("pipe-output").textContent = data.decoded_text;
}

// =========================================================================
// Update symbol grid
// =========================================================================
function updateSymbolGrid(data) {
    const grid = document.getElementById("symbol-grid");
    grid.innerHTML = "";

    const symLabels = ["00", "01", "10", "11"];
    const errorSet = new Set(data.error_positions);

    for (let i = 0; i < data.noisy_symbols.length; i++) {
        const cell = document.createElement("div");
        cell.className = "sym-cell " + (errorSet.has(i) ? "error" : "clean");
        cell.textContent = symLabels[data.noisy_symbols[i]];
        cell.title = `Sym ${i}: ${symLabels[data.encoded_symbols[i]]}` +
            (errorSet.has(i)
                ? ` -> ${symLabels[data.noisy_symbols[i]]} (ERROR)`
                : "");
        grid.appendChild(cell);
    }
}

// =========================================================================
// Update results
// =========================================================================
function updateResults(data) {
    document.getElementById("result-text").textContent = data.decoded_text;
    document.getElementById("result-channel-ber").textContent =
        data.channel_ber + "%";
    document.getElementById("result-decoded-ber").textContent =
        data.decoded_ber + "%";
    document.getElementById("result-errors").textContent =
        data.bit_errors + " / " + data.info_bits;
    document.getElementById("result-injected").textContent =
        data.num_errors_injected + " / " + data.num_symbols;
    document.getElementById("result-time").textContent =
        data.decode_time_ms + " ms";

    const berEl = document.getElementById("result-decoded-ber");
    berEl.style.color = data.decoded_ber === 0 ? "var(--success)"
        : data.decoded_ber < data.channel_ber ? "var(--accent)"
        : "var(--error)";

    const verdict = document.getElementById("verdict");
    if (data.bit_errors === 0 && data.num_errors_injected > 0) {
        verdict.className = "verdict perfect";
        verdict.textContent =
            `PERFECT CORRECTION - All ${data.num_errors_injected} channel errors corrected!`;
    } else if (data.bit_errors === 0) {
        verdict.className = "verdict perfect";
        verdict.textContent = "PERFECT DECODE - No errors in, no errors out";
    } else if (data.bit_errors < data.num_errors_injected) {
        verdict.className = "verdict corrected";
        verdict.textContent =
            `PARTIAL CORRECTION - Reduced from ${data.num_errors_injected} channel errors to ${data.bit_errors} bit errors`;
    } else {
        verdict.className = "verdict failed";
        verdict.textContent =
            `DECODER OVERWHELMED - ${data.bit_errors} bit errors remain (error rate too high)`;
    }

    const textEl = document.getElementById("result-text");
    textEl.style.color = data.bit_errors === 0 ? "var(--success)" : "var(--error)";
}

// =========================================================================
// Activity log
// =========================================================================
async function fetchActivity() {
    try {
        const resp = await fetch(API_BASE + "/api/activity");
        const data = await resp.json();
        if (!data.activity || data.activity.length === 0) {
            activityLog.innerHTML = '<p class="placeholder">No activity yet...</p>';
            return;
        }
        activityLog.innerHTML = data.activity.slice(0, 20).map(entry => {
            const ago = formatTimeAgo(entry.timestamp);
            const icon = {
                "decoded": "✅",
                "programmed": "⚡",
                "programming": "⏳",
                "error": "❌",
                "server_start": "🚀",
                "ber_sweep": "📈",
                "ber_done": "📈",
            }[entry.event] || "•";
            return `<div class="activity-entry">
                <span class="activity-icon">${icon}</span>
                <span class="activity-detail">${escapeHtml(entry.detail)}</span>
                <span class="activity-time">${ago}</span>
            </div>`;
        }).join("");
    } catch (e) {
        // Silently fail
    }
}

function formatTimeAgo(ts) {
    const diff = Math.floor(Date.now() / 1000 - ts);
    if (diff < 5) return "just now";
    if (diff < 60) return diff + "s ago";
    if (diff < 3600) return Math.floor(diff / 60) + "m ago";
    return Math.floor(diff / 3600) + "h ago";
}

function escapeHtml(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
}

// =========================================================================
// Trellis Diagram (read back from FPGA block RAM when available)
// =========================================================================
const trellisSection = document.getElementById("trellis-section");
const trellisCanvas = document.getElementById("trellis-canvas");
const trellisContainer = document.getElementById("trellis-container");
const trellisTooltip = document.getElementById("trellis-tooltip");
const trellisInfo = document.getElementById("trellis-info");
const trellisSubtitle = document.getElementById("trellis-subtitle");
const trellisSource = document.getElementById("trellis-source");
const trellisVerify = document.getElementById("trellis-verify");
const trellisStepRow = document.getElementById("trellis-step-row");
const trellisStep = document.getElementById("trellis-step");
const trellisPlay = document.getElementById("trellis-play");
const trellisStepInfo = document.getElementById("trellis-step-info");

const SYM_LABELS = ["00", "01", "10", "11"];
const C_PATH = "#0d7c3e";     // decided path (decoded entity)
const C_WIN = "#2a78d6";      // traceback window
const C_INK = "#1a2332";
const C_MUTED = "#5a6577";

let trellisZoom = 1.0;
let lastTrellisData = null;
let lastTrellisK = 0;
let lastResult = null;
let trellisAnimId = null;
let trellisPlayId = null;
let trellisBaseImage = null;  // cached background (edges + nodes)
let trellisBaseZoom = null;   // zoom level when base was rendered
let trellisSel = -1;          // selected step for the traceback-window overlay

function trellisBest(T, t) {
    if (T.best_states) return T.best_states[t];
    if (!T.path_metrics) return null;
    // Same rule as the RTL argmin: last state with the minimum metric wins
    const row = T.path_metrics[t];
    let best = 0, bv = Infinity;
    for (let s = 0; s < row.length; s++) {
        const v = row[s];
        if (v !== null && v <= bv) { bv = v; best = s; }
    }
    return best;
}

// Walk back D-1 steps from the best state at step t -- exactly what the
// hardware traceback unit does after every trellis step.
function trellisWindow(T, t) {
    const D = T.traceback_depth || 0;
    if (!D || t < D - 1 || t >= T.n_timesteps) return null;
    const m = Math.log2(T.n_states);
    let s = trellisBest(T, t);
    if (s === null) return null;
    const path = [{ t, s }];
    for (let j = 0; j < D - 1; j++) {
        const b = T.survivors[t - j][s];
        s = ((s >> 1) | (b << (m - 1))) & (T.n_states - 1);
        path.push({ t: t - j - 1, s });
    }
    return path;
}

function updateTrellis(data) {
    if (!data.trellis) {
        trellisSection.style.display = "none";
        return;
    }
    stopTrellisPlay();
    trellisSection.style.display = "";
    lastTrellisData = data.trellis;
    lastTrellisK = data.k;
    lastResult = data;
    trellisBaseImage = null;  // invalidate cache on new data
    trellisSel = -1;

    const T = data.trellis;
    const D = T.traceback_depth || 0;
    trellisSubtitle.textContent = `(${T.n_states} states x ${T.n_timesteps} steps)`;
    trellisInfo.textContent = `K=${data.k}, traceback depth ${D || "?"}`;

    const hw = T.source === "FPGA";
    trellisSource.textContent = hw ? "captured from FPGA block RAM" : "software replay";
    trellisSource.className = "source-badge " + (hw ? "hw" : "sw");
    if (hw) {
        const ok = T.replay_mismatches === 0;
        trellisVerify.className = "trellis-verify " + (ok ? "ok" : "bad");
        trellisVerify.textContent = ok
            ? `✓ ${T.n_timesteps * T.n_states} add-compare-select results recorded by the chip. ` +
              `Replaying the hardware's ${T.replay_checked} traceback windows from these survivor bits ` +
              `reproduces every bit the FPGA emitted.`
            : `⚠ ${T.replay_mismatches} of ${T.replay_checked} replayed traceback windows ` +
              `disagree with the FPGA output.`;
    } else {
        trellisVerify.className = "trellis-verify";
        trellisVerify.textContent = currentMode === "FPGA"
            ? "This bitstream has no trellis capture, so this view is recomputed in software."
            : "Software mode: this trellis is computed by the Python reference decoder.";
    }

    const canStep = D > 0 && T.n_timesteps >= D && (T.best_states || T.path_metrics);
    trellisStepRow.style.display = canStep ? "" : "none";
    if (canStep) {
        trellisStep.min = D - 1;
        trellisStep.max = T.n_timesteps - 1;
        trellisStep.value = D - 1;
        trellisStepInfo.textContent =
            "Drag the slider, click the trellis, or press Play to step through the decoder.";
    }
    drawTrellis(T, data.k, true);
}

function getTrellisLayout(nStates, nTime) {
    let cellW, cellH;
    if (nStates <= 4) { cellW = 18; cellH = 40; }
    else if (nStates <= 16) { cellW = 14; cellH = 16; }
    else if (nStates <= 64) { cellW = 10; cellH = 6; }
    else { cellW = 8; cellH = 3; }
    cellW = Math.max(2, Math.round(cellW * trellisZoom));
    cellH = Math.max(1, Math.round(cellH * trellisZoom));
    const marginL = 45, marginR = 15, marginT = 20, marginB = 25;
    return {
        cellW, cellH, marginL, marginR, marginT, marginB,
        w: marginL + nTime * cellW + marginR,
        h: marginT + nStates * cellH + marginB,
        xFor: t => marginL + t * cellW,
        yFor: s => marginT + s * cellH,
    };
}

function pmUsable(v) { return v !== null && v !== undefined && v < 1000; }

function renderTrellisBase(T) {
    const nStates = T.n_states;
    const nTime = T.n_timesteps;
    const m = Math.log2(nStates);
    const L = getTrellisLayout(nStates, nTime);
    const dpr = window.devicePixelRatio || 1;

    const offscreen = document.createElement("canvas");
    offscreen.width = L.w * dpr;
    offscreen.height = L.h * dpr;
    const ctx = offscreen.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    // Flush region (zero symbols pushed in to drain the traceback)
    const nData = T.n_data_steps || nTime;
    if (nData < nTime) {
        const x0 = L.xFor(nData) - L.cellW / 2;
        ctx.fillStyle = "rgba(90,101,119,0.08)";
        ctx.fillRect(x0, L.marginT - 10, L.xFor(nTime - 1) - x0 + L.cellW / 2,
                     (nStates - 1) * L.cellH + 20);
        ctx.fillStyle = C_MUTED;
        ctx.font = "10px monospace";
        ctx.textAlign = "left";
        ctx.fillText("flush", x0 + 3, L.marginT - 4);
    }

    // Axis labels
    ctx.fillStyle = C_MUTED;
    ctx.font = `${Math.max(8, Math.min(11, L.cellH))}px monospace`;
    ctx.textAlign = "right";
    const stateStep = nStates <= 16 ? 1 : nStates <= 64 ? 8 : 32;
    for (let s = 0; s < nStates; s += stateStep)
        ctx.fillText(s, L.marginL - 4, L.yFor(s) + 4);
    ctx.textAlign = "center";
    ctx.font = "10px monospace";
    const timeStep = nTime * L.cellW < 400 ? 5 : nTime <= 100 ? 10 : 20;
    for (let t = 0; t < nTime; t += timeStep)
        ctx.fillText(t, L.xFor(t), L.h - 5);

    // Max path metric for color scaling
    let pmMax = 1;
    if (T.path_metrics) {
        for (let t = 0; t < nTime; t++)
            for (let s = 0; s < nStates; s++) {
                const v = T.path_metrics[t][s];
                if (pmUsable(v) && v > pmMax) pmMax = v;
            }
    }

    // Survivor edges
    ctx.lineWidth = nStates <= 16 ? 1 : 0.5;
    for (let t = 1; t < nTime; t++) {
        for (let s = 0; s < nStates; s++) {
            let alpha = 0.12;
            if (T.path_metrics) {
                const v = T.path_metrics[t][s];
                if (!pmUsable(v)) continue;   // unreachable state
                alpha = 0.05 + 0.2 * (1 - v / pmMax);
            }
            const b = T.survivors[t][s];
            const prev = ((s >> 1) | (b << (m - 1))) & (nStates - 1);
            ctx.strokeStyle = `rgba(13,124,62,${alpha})`;
            ctx.beginPath();
            ctx.moveTo(L.xFor(t - 1), L.yFor(prev));
            ctx.lineTo(L.xFor(t), L.yFor(s));
            ctx.stroke();
        }
    }

    // State nodes
    if (nStates <= 64) {
        const r = nStates <= 16 ? 2 : 1.5;
        for (let t = 0; t < nTime; t++) {
            for (let s = 0; s < nStates; s++) {
                let intensity = 0.15;
                if (T.path_metrics) {
                    const v = T.path_metrics[t][s];
                    if (!pmUsable(v)) continue;
                    intensity = 0.1 + 0.6 * (1 - v / pmMax);
                }
                ctx.fillStyle = `rgba(13,124,62,${intensity})`;
                ctx.beginPath();
                ctx.arc(L.xFor(t), L.yFor(s), r, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }

    return offscreen;
}

function drawTrellis(T, k, fresh) {
    if (trellisAnimId) {
        clearTimeout(trellisAnimId);
        trellisAnimId = null;
    }

    const nStates = T.n_states;
    const nTime = T.n_timesteps;
    const L = getTrellisLayout(nStates, nTime);
    const dpr = window.devicePixelRatio || 1;

    // Render base (edges + nodes) only when zoom changes or new data
    if (!trellisBaseImage || trellisBaseZoom !== trellisZoom) {
        trellisBaseImage = renderTrellisBase(T);
        trellisBaseZoom = trellisZoom;
    }

    trellisCanvas.width = L.w * dpr;
    trellisCanvas.height = L.h * dpr;
    trellisCanvas.style.width = L.w + "px";
    trellisCanvas.style.height = L.h + "px";

    const ctx = trellisCanvas.getContext("2d");
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.drawImage(trellisBaseImage, 0, 0);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const doAnimate = fresh && trellisSel < 0 &&
        document.getElementById("trellis-animate").checked;
    if (doAnimate) {
        animateTraceback(ctx, T, L.xFor, L.yFor, nStates);
    } else {
        drawTracebackFull(ctx, T, L.xFor, L.yFor, nStates);
        if (trellisSel >= 0) drawWindow(ctx, T, L, trellisSel);
    }
}

function drawTracebackFull(ctx, T, xFor, yFor, nStates) {
    const path = T.traceback_path || [];
    if (path.length === 0) return;
    ctx.strokeStyle = C_PATH;
    ctx.lineWidth = nStates <= 16 ? 3 : 2;
    ctx.beginPath();
    ctx.moveTo(xFor(0), yFor(path[0]));
    for (let t = 1; t < path.length; t++) ctx.lineTo(xFor(t), yFor(path[t]));
    ctx.stroke();

    const r = nStates <= 16 ? 3.5 : 2.5;
    ctx.fillStyle = C_PATH;
    for (let t = 0; t < path.length; t++) {
        ctx.beginPath();
        ctx.arc(xFor(t), yFor(path[t]), r, 0, Math.PI * 2);
        ctx.fill();
    }
}

function animateTraceback(ctx, T, xFor, yFor, nStates) {
    const path = T.traceback_path || [];
    const total = path.length;
    if (total < 2) return;
    let step = total - 1;
    const lineW = nStates <= 16 ? 3 : 2;
    const nodeR = nStates <= 16 ? 3.5 : 2.5;
    const speed = Math.max(10, Math.min(40, 1500 / total));

    function frame() {
        if (step <= 0) {
            trellisAnimId = null;
            return;
        }
        ctx.strokeStyle = C_PATH;
        ctx.lineWidth = lineW;
        ctx.beginPath();
        ctx.moveTo(xFor(step), yFor(path[step]));
        ctx.lineTo(xFor(step - 1), yFor(path[step - 1]));
        ctx.stroke();
        ctx.fillStyle = C_PATH;
        ctx.beginPath();
        ctx.arc(xFor(step - 1), yFor(path[step - 1]), nodeR, 0, Math.PI * 2);
        ctx.fill();
        step--;
        trellisAnimId = setTimeout(frame, speed);
    }

    ctx.fillStyle = C_PATH;
    ctx.beginPath();
    ctx.arc(xFor(total - 1), yFor(path[total - 1]), nodeR, 0, Math.PI * 2);
    ctx.fill();
    frame();
}

function drawWindow(ctx, T, L, t) {
    const w = trellisWindow(T, t);
    if (!w) return;
    const D = T.traceback_depth;
    const top = L.marginT - 8;
    const height = (T.n_states - 1) * L.cellH + 16;

    // Window span + current-step cursor
    ctx.fillStyle = "rgba(42,120,214,0.06)";
    ctx.fillRect(L.xFor(t - D + 1), top, L.xFor(t) - L.xFor(t - D + 1), height);
    ctx.fillStyle = "rgba(42,120,214,0.16)";
    ctx.fillRect(L.xFor(t) - Math.max(1, L.cellW / 2), top, Math.max(2, L.cellW), height);

    // Traceback walk
    ctx.strokeStyle = C_WIN;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(L.xFor(w[0].t), L.yFor(w[0].s));
    for (let i = 1; i < w.length; i++) ctx.lineTo(L.xFor(w[i].t), L.yFor(w[i].s));
    ctx.stroke();

    // Start (best state) ring and emitted-bit node, each with a 2px surface ring
    const end = w[w.length - 1];
    for (const [pt, filled] of [[w[0], false], [end, true]]) {
        ctx.beginPath();
        ctx.arc(L.xFor(pt.t), L.yFor(pt.s), 5, 0, Math.PI * 2);
        ctx.fillStyle = "#ffffff";
        ctx.fill();
        ctx.beginPath();
        ctx.arc(L.xFor(pt.t), L.yFor(pt.s), 4, 0, Math.PI * 2);
        if (filled) { ctx.fillStyle = C_WIN; ctx.fill(); }
        else { ctx.strokeStyle = C_WIN; ctx.lineWidth = 2; ctx.stroke(); }
    }

    // Label the emitted bit (ink text, not series color)
    ctx.font = "11px monospace";
    ctx.textAlign = "center";
    const label = `bit ${end.t} = ${end.s & 1}`;
    const lx = L.xFor(end.t), ly = Math.max(12, L.yFor(end.s) - 9);
    const tw = ctx.measureText(label).width + 6;
    ctx.fillStyle = "rgba(255,255,255,0.9)";
    ctx.fillRect(lx - tw / 2, ly - 10, tw, 13);
    ctx.fillStyle = C_INK;
    ctx.fillText(label, lx, ly);
}

function describeStep(T, t) {
    const D = T.traceback_depth;
    const w = trellisWindow(T, t);
    if (!w || !lastResult) return "";
    const nData = T.n_data_steps || T.n_timesteps;
    const sym = t < nData ? SYM_LABELS[lastResult.noisy_symbols[t]] : "00";
    const corrupted = t < nData && (lastResult.error_positions || []).includes(t);
    const best = w[0].s;
    const pm = T.path_metrics && pmUsable(T.path_metrics[t][best]) ? T.path_metrics[t][best] : null;
    const i = t - D + 1;
    const bit = w[w.length - 1].s & 1;
    let what;
    if (i < lastResult.info_bits) {
        const ch = lastResult.input_text[Math.floor(i / 8)] || "?";
        what = `message bit ${i} ('${ch}', bit ${7 - (i % 8)})`;
    } else {
        what = `tail bit ${i}`;
    }
    return `step ${t}: received ${sym}${t >= nData ? " (flush)" : ""}${corrupted ? " ⚠ corrupted" : ""}` +
        ` → best state ${best}${pm !== null ? ` (metric +${pm})` : ""}` +
        ` → trace back ${D - 1} steps → emit ${what} = ${bit}`;
}

function selectTrellisStep(t) {
    const T = lastTrellisData;
    if (!T) return;
    trellisSel = t;
    trellisStep.value = t;
    trellisStepInfo.textContent = describeStep(T, t);
    drawTrellis(T, lastTrellisK, false);
    // Keep the traceback window in view (it starts D-1 steps left of t)
    const L = getTrellisLayout(T.n_states, T.n_timesteps);
    const x0 = L.xFor(t - T.traceback_depth + 1) - 20, x1 = L.xFor(t) + 30;
    const c = trellisContainer, view = c.clientWidth;
    if (x1 > c.scrollLeft + view || x0 < c.scrollLeft) {
        c.scrollLeft = x1 - x0 > view ? x1 - view : Math.max(0, x0 - (view - (x1 - x0)) / 2);
    }
}

function stopTrellisPlay() {
    if (trellisPlayId) clearTimeout(trellisPlayId);
    trellisPlayId = null;
    trellisPlay.innerHTML = "&#9654; Play decoder";
}

trellisPlay.addEventListener("click", () => {
    const T = lastTrellisData;
    if (!T) return;
    if (trellisPlayId) { stopTrellisPlay(); return; }
    trellisPlay.innerHTML = "&#10074;&#10074; Pause";
    let t = trellisSel < 0 || trellisSel >= T.n_timesteps - 1
        ? T.traceback_depth - 1 : trellisSel;
    const delay = Math.max(40, Math.min(150, 10000 / T.n_timesteps));
    const tick = () => {
        selectTrellisStep(t);
        if (t >= T.n_timesteps - 1) { stopTrellisPlay(); return; }
        t++;
        trellisPlayId = setTimeout(tick, delay);
    };
    tick();
});

trellisStep.addEventListener("input", () => {
    stopTrellisPlay();
    selectTrellisStep(parseInt(trellisStep.value));
});

// Zoom controls
document.getElementById("trellis-zoom-in").addEventListener("click", () => {
    trellisZoom = Math.min(3, trellisZoom * 1.3);
    if (lastTrellisData) drawTrellis(lastTrellisData, lastTrellisK, false);
});
document.getElementById("trellis-zoom-out").addEventListener("click", () => {
    trellisZoom = Math.max(0.3, trellisZoom / 1.3);
    if (lastTrellisData) drawTrellis(lastTrellisData, lastTrellisK, false);
});

function trellisHit(e) {
    const T = lastTrellisData;
    const rect = trellisCanvas.getBoundingClientRect();
    const L = getTrellisLayout(T.n_states, T.n_timesteps);
    const t = Math.round((e.clientX - rect.left - L.marginL) / L.cellW);
    const s = Math.round((e.clientY - rect.top - L.marginT) / L.cellH);
    return { t, s, ok: t >= 0 && t < T.n_timesteps && s >= 0 && s < T.n_states };
}

trellisCanvas.addEventListener("mousemove", (e) => {
    if (!lastTrellisData) return;
    const T = lastTrellisData;
    const { t, s, ok } = trellisHit(e);
    if (!ok) { trellisTooltip.style.display = "none"; return; }
    const m = Math.log2(T.n_states);
    let txt = `t=${t} state=${s}`;
    if (T.path_metrics && T.path_metrics[t]) {
        const v = T.path_metrics[t][s];
        txt += pmUsable(v) ? ` metric=+${v}` : " (unreachable)";
    }
    if (t >= 1) {
        const b = T.survivors[t][s];
        const prev = ((s >> 1) | (b << (m - 1))) & (T.n_states - 1);
        txt += ` ← from ${prev}`;
    }
    const path = T.traceback_path || [];
    if (path[t] === s) txt += " [decided path]";
    if (T.best_states && T.best_states[t] === s) txt += " [best]";
    trellisTooltip.textContent = txt;
    trellisTooltip.style.display = "block";
    trellisTooltip.style.left = (e.clientX + 12) + "px";
    trellisTooltip.style.top = (e.clientY - 8) + "px";
});

trellisCanvas.addEventListener("click", (e) => {
    if (!lastTrellisData || trellisStepRow.style.display === "none") return;
    const T = lastTrellisData;
    const { t } = trellisHit(e);
    const D = T.traceback_depth;
    stopTrellisPlay();
    selectTrellisStep(Math.min(T.n_timesteps - 1, Math.max(D - 1, t)));
});

trellisCanvas.addEventListener("mouseleave", () => {
    trellisTooltip.style.display = "none";
});

// =========================================================================
// Live BER curves (measured by the on-chip tester)
// =========================================================================
const berCanvas = document.getElementById("ber-canvas");
const berWrap = document.getElementById("ber-wrap");
const berTooltip = document.getElementById("ber-tooltip");
const berRunBtn = document.getElementById("ber-run");
const berStatus = document.getElementById("ber-status");
const berLegend = document.getElementById("ber-legend");
const berStats = document.getElementById("ber-stats");
const berTable = document.getElementById("ber-table");

const C_DEC = "#0d7c3e";   // decoded bits (entity 1)
const C_CH = "#2a78d6";    // channel bits (entity 2)
const C_REF = "#8a94a3";   // reference curves (neutral)
const C_GRID = "#e6e9ef";
const BER_X0 = 0, BER_X1 = 8, BER_Y0 = -7, BER_Y1 = 0;

let berData = null;
let berPollId = null;
let berHits = [];

function fmtP(p) {
    if (p === null || p === undefined) return "–";
    if (p === 0) return "0";
    return p.toExponential(2);
}

function fmtBits(n) {
    if (n >= 1e9) return (n / 1e9).toFixed(2) + " G";
    if (n >= 1e6) return (n / 1e6).toFixed(2) + " M";
    if (n >= 1e3) return (n / 1e3).toFixed(1) + " k";
    return String(n);
}

function berMeasured() {
    if (!berData) return null;
    return berData.live || berData.measured || null;
}

async function fetchBer(k) {
    try {
        const resp = await fetch(API_BASE + `/api/ber?k=${k}`);
        const data = await resp.json();
        if (data.error) return;
        berData = data;
        renderBerAll();
        if (!data.fpga_mode) {
            berRunBtn.disabled = true;
            berStatus.textContent = "Server is in software mode — sweeps need the FPGA.";
        } else if (data.running) {
            watchBerJob(data.running.job_id);
        } else {
            berRunBtn.disabled = false;
            berStatus.textContent = data.measured
                ? `Last hardware run: ${formatTimeAgo(data.measured.finished)}.`
                : `No hardware run yet for K=${k}. Takes about 25 s.`;
        }
    } catch (e) {
        berStatus.textContent = "Could not load BER data.";
    }
}

async function startBerSweep() {
    const k = parseInt(kSelect.value);
    berRunBtn.disabled = true;
    berStatus.textContent = "Queuing sweep…";
    try {
        const resp = await fetch(API_BASE + "/api/ber/sweep", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ k })
        });
        const data = await resp.json();
        if (data.error) {
            berStatus.textContent = data.error;
            berRunBtn.disabled = false;
            return;
        }
        watchBerJob(data.job_id);
    } catch (e) {
        berStatus.textContent = "Error: " + e.message;
        berRunBtn.disabled = false;
    }
}

function watchBerJob(jobId) {
    if (berPollId) clearTimeout(berPollId);
    berRunBtn.disabled = true;
    const tick = async () => {
        try {
            const resp = await fetch(API_BASE + "/api/job/" + jobId);
            const j = await resp.json();
            if (j.error && !j.status) {
                berPollId = null;
                berRunBtn.disabled = false;
                return;
            }
            const res = j.result || {};
            const mine = berData && res.k === berData.k;
            if (mine && Array.isArray(res.points)) { berData.live = res; renderBerAll(); }
            const other = berData && j.k !== berData.k ? ` (another visitor's K=${j.k} run)` : "";
            if (j.status === "queued") {
                berStatus.textContent = `Queued #${j.position} — waiting for the FPGA${other}`;
            } else if (j.status === "programming") {
                berStatus.textContent = `Programming FPGA for K=${j.k}…${other}`;
            } else if (j.status === "running") {
                const n = Array.isArray(res.points) ? res.points.length : 0;
                berStatus.textContent =
                    `Measuring on FPGA: point ${Math.min(n + 1, res.total || n + 1)} of ${res.total || "?"}${other}…`;
            } else if (j.status === "done" || j.status === "error") {
                berPollId = null;
                berRunBtn.disabled = false;
                if (j.status === "error") {
                    berStatus.textContent = "Sweep failed: " + (res.error || "unknown error");
                    if (berData) berData.live = null;
                } else {
                    berStatus.textContent = `Sweep finished (K=${j.k}).`;
                    if (mine) { berData.measured = res; berData.live = null; }
                }
                renderBerAll();
                fetchActivity();
                return;
            }
        } catch (e) { /* network blip: keep polling */ }
        berPollId = setTimeout(tick, 1000);
    };
    tick();
}

function berSwatch(color, dash, dot) {
    const line = `<line x1="1" y1="6" x2="23" y2="6" stroke="${color}" stroke-width="2"` +
        (dash ? ` stroke-dasharray="${dash}"` : "") + "/>";
    const marker = dot ? `<circle cx="12" cy="6" r="4" fill="${color}" stroke="#fff" stroke-width="2"/>` : "";
    return `<svg width="24" height="12" aria-hidden="true">${dot ? "" : line}${marker}</svg>`;
}

function renderBerLegend() {
    const items = [
        [berSwatch(C_DEC, null, true), "Decoded BER — measured on FPGA"],
        [berSwatch(C_DEC, "6 4"), "Hard-decision union bound"],
        [berSwatch(C_CH, null, true), "Channel bit flips — measured"],
        [berSwatch(C_CH, "6 4"), "Channel p (target)"],
        [berSwatch(C_REF, null), "Uncoded BPSK"],
        [berSwatch(C_REF, "2 4"), "Soft-decision bound (not implemented yet)"],
    ];
    berLegend.innerHTML = items.map(([sw, label]) =>
        `<span class="ber-legend-item">${sw}${label}</span>`).join("");
}

function renderBerChart() {
    if (!berData) return;
    const T = berData.theory;
    const meas = berMeasured();
    const dpr = window.devicePixelRatio || 1;
    const W = Math.max(280, berWrap.clientWidth);
    const H = Math.round(Math.min(400, Math.max(260, W * 0.5)));
    const narrow = W < 620;
    const pad = { l: 58, r: narrow ? 14 : 132, t: 14, b: 42 };

    berCanvas.width = W * dpr;
    berCanvas.height = H * dpr;
    berCanvas.style.width = W + "px";
    berCanvas.style.height = H + "px";
    const ctx = berCanvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);

    const pw = W - pad.l - pad.r, ph = H - pad.t - pad.b;
    const x = v => pad.l + (v - BER_X0) / (BER_X1 - BER_X0) * pw;
    const y = p => pad.t + (BER_Y1 - Math.log10(Math.max(p, 1e-12))) / (BER_Y1 - BER_Y0) * ph;

    // Grid + axes (recessive)
    ctx.lineWidth = 1;
    ctx.font = "11px -apple-system, Segoe UI, sans-serif";
    ctx.fillStyle = C_MUTED;
    ctx.textAlign = "right";
    for (let e = BER_Y0; e <= BER_Y1; e++) {
        const yy = Math.round(y(Math.pow(10, e))) + 0.5;
        ctx.strokeStyle = C_GRID;
        ctx.beginPath(); ctx.moveTo(pad.l, yy); ctx.lineTo(pad.l + pw, yy); ctx.stroke();
        ctx.fillText(e === 0 ? "1" : `1e${e}`, pad.l - 6, yy + 4);
    }
    ctx.textAlign = "center";
    for (let v = BER_X0; v <= BER_X1; v++) {
        const xx = Math.round(x(v)) + 0.5;
        ctx.strokeStyle = C_GRID;
        ctx.beginPath(); ctx.moveTo(xx, pad.t); ctx.lineTo(xx, pad.t + ph); ctx.stroke();
        ctx.fillText(String(v), xx, pad.t + ph + 16);
    }
    ctx.fillText("Eb/N0 (dB)", pad.l + pw / 2, H - 6);
    ctx.save();
    ctx.translate(14, pad.t + ph / 2);
    ctx.rotate(-Math.PI / 2);
    ctx.fillText("bit error rate", 0, 0);
    ctx.restore();

    // Clip to plot area for curves
    ctx.save();
    ctx.beginPath();
    ctx.rect(pad.l, pad.t, pw, ph);
    ctx.clip();

    const labels = [];
    function curve(ys, color, dash, width, maxP, label) {
        ctx.strokeStyle = color;
        ctx.lineWidth = width;
        ctx.setLineDash(dash || []);
        ctx.beginPath();
        let started = false, last = null;
        for (let i = 0; i < T.ebn0_db.length; i++) {
            const xv = T.ebn0_db[i], p = ys[i];
            if (xv > BER_X1 || p > maxP || p < 1e-9) { if (started) break; continue; }
            const px = x(xv), py = y(p);
            if (!started) { ctx.moveTo(px, py); started = true; } else ctx.lineTo(px, py);
            if (p >= Math.pow(10, BER_Y0)) last = [px, py];   // last point inside the plot
        }
        ctx.stroke();
        ctx.setLineDash([]);
        if (label && last) {
            const atRight = last[0] >= pad.l + pw - 2;
            labels.push({ label, y: last[1], x: last[0], color, atRight });
        }
    }
    curve(T.uncoded, C_REF, null, 1.5, 1, "uncoded");
    curve(T.soft_bound, C_REF, [2, 4], 1.5, 0.05, "soft bound");
    curve(T.channel_p, C_CH, [6, 4], 1.5, 1, "channel p");
    curve(T.hard_bound, C_DEC, [6, 4], 2, 0.05, "hard bound");

    // Measured points
    berHits = [];
    const pts = meas && Array.isArray(meas.points) ? meas.points : [];
    const dot = (px, py, color) => {
        ctx.beginPath(); ctx.arc(px, py, 6, 0, Math.PI * 2); ctx.fillStyle = "#fff"; ctx.fill();
        ctx.beginPath(); ctx.arc(px, py, 4, 0, Math.PI * 2); ctx.fillStyle = color; ctx.fill();
    };
    // channel flips
    for (const pt of pts) {
        if (pt.channel_ber) {
            const px = x(pt.ebn0_db), py = y(pt.channel_ber);
            dot(px, py, C_CH);
            berHits.push({ px, py, pt, series: "channel" });
        }
    }
    // decoded: line through points that have errors
    ctx.strokeStyle = C_DEC;
    ctx.lineWidth = 2;
    ctx.beginPath();
    let first = true;
    for (const pt of pts) {
        if (!pt.errors) continue;
        const px = x(pt.ebn0_db), py = y(pt.ber);
        if (first) { ctx.moveTo(px, py); first = false; } else ctx.lineTo(px, py);
    }
    ctx.stroke();
    for (const pt of pts) {
        const px = x(pt.ebn0_db);
        if (pt.errors) {
            const py = y(pt.ber);
            dot(px, py, C_DEC);
            berHits.push({ px, py, pt, series: "decoded" });
        } else if (pt.bits) {
            // Zero errors: upper limit at 1/N, hollow down-triangle
            const py = y(1 / pt.bits);
            ctx.beginPath();
            ctx.moveTo(px - 5, py - 4); ctx.lineTo(px + 5, py - 4); ctx.lineTo(px, py + 5);
            ctx.closePath();
            ctx.fillStyle = "#fff"; ctx.fill();
            ctx.strokeStyle = C_DEC; ctx.lineWidth = 2; ctx.stroke();
            berHits.push({ px, py, pt, series: "limit" });
        }
    }
    ctx.restore();

    // Direct labels (ink text). Curves reaching the right edge are labelled
    // in the margin (de-collided); curves leaving through the bottom are
    // labelled inline where they exit.
    if (!narrow) {
        ctx.font = "11px -apple-system, Segoe UI, sans-serif";
        ctx.textAlign = "left";
        const margin = labels.filter(l => l.atRight).sort((a, b) => a.y - b.y);
        let prevY = -Infinity;
        for (const lb of margin) {
            const ly = Math.min(pad.t + ph, Math.max(lb.y, prevY + 14));
            prevY = ly;
            ctx.strokeStyle = lb.color;
            ctx.lineWidth = 1;
            ctx.beginPath(); ctx.moveTo(lb.x + 3, lb.y); ctx.lineTo(pad.l + pw + 8, ly); ctx.stroke();
            ctx.fillStyle = C_MUTED;
            ctx.fillText(lb.label, pad.l + pw + 12, ly + 4);
        }
        for (const lb of labels.filter(l => !l.atRight)) {
            const tw = ctx.measureText(lb.label).width;
            const lx = Math.min(lb.x + 8, pad.l + pw - tw - 4);
            const ly = Math.min(lb.y - 6, pad.t + ph - 6);
            ctx.fillStyle = "rgba(252,252,251,0.9)";
            ctx.fillRect(lx - 2, ly - 10, tw + 4, 13);
            ctx.fillStyle = C_MUTED;
            ctx.fillText(lb.label, lx, ly);
        }
    }

    if (!pts.length) {
        ctx.fillStyle = C_MUTED;
        ctx.textAlign = "center";
        ctx.font = "13px -apple-system, Segoe UI, sans-serif";
        ctx.fillText("No hardware measurements yet — press “Run sweep on FPGA”",
                     pad.l + pw / 2, pad.t + ph / 2);
    }
}

function renderBerStats() {
    const meas = berMeasured();
    const T = berData ? berData.theory : null;
    const pts = meas && Array.isArray(meas.points) ? meas.points : [];
    const totalBits = pts.reduce((a, p) => a + p.bits, 0);
    const totalSec = pts.reduce((a, p) => a + p.seconds, 0);
    const mbps = totalSec > 0 ? totalBits / totalSec / 1e6 : 0;
    const lanes = meas && meas.lanes ? meas.lanes : null;
    document.getElementById("ber-lanes").textContent = lanes || "N";
    const tiles = [
        ["Bits decoded on FPGA", pts.length ? fmtBits(totalBits) : "–"],
        ["Decoder throughput", pts.length ? `${mbps.toFixed(2)} Mbit/s` : "–"],
        ["Parallel lanes @ 50 MHz", lanes ? String(lanes) : "–"],
        ["Free distance d_free", T ? String(T.d_free) : "–"],
    ];
    berStats.innerHTML = tiles.map(([l, v]) =>
        `<div class="result-card"><div class="result-label">${l}</div>` +
        `<div class="result-value">${v}</div></div>`).join("");
}

function renderBerTable() {
    const meas = berMeasured();
    const T = berData ? berData.theory : null;
    const pts = meas && Array.isArray(meas.points) ? meas.points : [];
    const head = "<tr><th>Eb/N0 (dB)</th><th>channel p target</th><th>channel measured</th>" +
        "<th>decoded errors / bits</th><th>decoded BER</th><th>hard bound</th><th>Mbit/s</th></tr>";
    const rows = pts.map(pt => {
        const idx = T ? T.ebn0_db.indexOf(pt.ebn0_db) : -1;
        const hb = idx >= 0 ? T.hard_bound[idx] : null;
        const ber = pt.errors ? fmtP(pt.ber) : (pt.bits ? `< ${fmtP(1 / pt.bits)}` : "–");
        return `<tr><td>${pt.ebn0_db}</td><td>${fmtP(pt.p_target)}</td><td>${fmtP(pt.channel_ber)}</td>` +
            `<td>${pt.errors} / ${fmtBits(pt.bits)}</td><td>${ber}</td>` +
            `<td>${hb !== null && hb < 0.05 ? fmtP(hb) : "–"}</td><td>${pt.mbps}</td></tr>`;
    }).join("");
    berTable.innerHTML = head + (rows || `<tr><td colspan="7">No measurements yet.</td></tr>`);
}

function renderBerAll() {
    renderBerLegend();
    renderBerChart();
    renderBerStats();
    renderBerTable();
}

berCanvas.addEventListener("mousemove", (e) => {
    const rect = berCanvas.getBoundingClientRect();
    const mx = e.clientX - rect.left, my = e.clientY - rect.top;
    let best = null, bd = 14 * 14;
    for (const h of berHits) {
        const d = (h.px - mx) ** 2 + (h.py - my) ** 2;
        if (d < bd) { bd = d; best = h; }
    }
    if (!best) { berTooltip.style.display = "none"; return; }
    const pt = best.pt;
    const dec = pt.errors ? `${fmtP(pt.ber)} (${pt.errors} errors / ${fmtBits(pt.bits)} bits)`
        : `< ${fmtP(1 / pt.bits)} (0 errors in ${fmtBits(pt.bits)} bits)`;
    berTooltip.innerHTML =
        `<b>Eb/N0 ${pt.ebn0_db} dB</b><br>decoded BER ${dec}<br>` +
        `channel ${fmtP(pt.channel_ber)} (target ${fmtP(pt.p_target)})<br>` +
        `${pt.mbps} Mbit/s for ${pt.seconds.toFixed(2)} s`;
    berTooltip.style.display = "block";
    berTooltip.style.left = (e.clientX + 12) + "px";
    berTooltip.style.top = (e.clientY - 8) + "px";
});
berCanvas.addEventListener("mouseleave", () => { berTooltip.style.display = "none"; });

let berResizeId = null;
window.addEventListener("resize", () => {
    if (berResizeId) clearTimeout(berResizeId);
    berResizeId = setTimeout(renderBerChart, 120);
});

berRunBtn.addEventListener("click", startBerSweep);
kSelect.addEventListener("change", () => fetchBer(parseInt(kSelect.value)));

// =========================================================================
// Initialize — wire up event listeners (no inline onclick)
// =========================================================================
sendBtn.addEventListener("click", runDecode);
document.getElementById("run-once-btn").addEventListener("click", runDecode);
document.getElementById("program-btn").addEventListener("click", programFPGA);
modeToggleBtn.addEventListener("click", toggleMode);

checkStatus().then(() => fetchBer(parseInt(kSelect.value)));
fetchActivity();
setInterval(fetchActivity, 5000);
