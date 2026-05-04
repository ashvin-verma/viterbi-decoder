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
// Trellis Diagram
// =========================================================================
const trellisSection = document.getElementById("trellis-section");
const trellisCanvas = document.getElementById("trellis-canvas");
const trellisContainer = document.getElementById("trellis-container");
const trellisTooltip = document.getElementById("trellis-tooltip");
const trellisInfo = document.getElementById("trellis-info");
const trellisSubtitle = document.getElementById("trellis-subtitle");

let trellisZoom = 1.0;
let lastTrellisData = null;
let lastTrellisK = 0;
let trellisAnimId = null;
let trellisBaseImage = null;  // cached background (edges + nodes)
let trellisBaseZoom = null;   // zoom level when base was rendered

function updateTrellis(data) {
    if (!data.trellis) {
        trellisSection.style.display = "none";
        return;
    }
    trellisSection.style.display = "";
    lastTrellisData = data.trellis;
    lastTrellisK = data.k;
    trellisBaseImage = null;  // invalidate cache on new data

    const T = data.trellis;
    trellisSubtitle.textContent = `(${T.n_states} states x ${T.n_timesteps} steps)`;
    trellisInfo.textContent = `K=${data.k}, ${T.n_states} states`;

    drawTrellis(T, data.k);
}

function getTrellisLayout(nStates, nTime) {
    let cellW, cellH;
    if (nStates <= 4) { cellW = 18; cellH = 40; }
    else if (nStates <= 16) { cellW = 14; cellH = 16; }
    else if (nStates <= 64) { cellW = 10; cellH = 6; }
    else { cellW = 8; cellH = 3; }
    cellW = Math.round(cellW * trellisZoom);
    cellH = Math.round(cellH * trellisZoom);
    const marginL = 45, marginR = 15, marginT = 20, marginB = 25;
    return {
        cellW, cellH, marginL, marginR, marginT, marginB,
        w: marginL + nTime * cellW + marginR,
        h: marginT + nStates * cellH + marginB,
        xFor: t => marginL + t * cellW,
        yFor: s => marginT + s * cellH,
    };
}

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

    // Axis labels
    ctx.fillStyle = "#5a6577";
    ctx.font = `${Math.max(8, Math.min(11, L.cellH))}px monospace`;
    ctx.textAlign = "right";
    const stateStep = nStates <= 16 ? 1 : nStates <= 64 ? 8 : 32;
    for (let s = 0; s < nStates; s += stateStep)
        ctx.fillText(s, L.marginL - 4, L.yFor(s) + 4);
    ctx.textAlign = "center";
    const timeStep = nTime <= 30 ? 5 : nTime <= 100 ? 10 : 20;
    for (let t = 0; t < nTime; t += timeStep)
        ctx.fillText(t, L.xFor(t), L.h - 5);

    // Max path metric for color scaling
    let pmMax = 1;
    if (T.path_metrics) {
        for (let t = 0; t < nTime; t++)
            for (let s = 0; s < nStates; s++)
                if (T.path_metrics[t][s] > pmMax) pmMax = T.path_metrics[t][s];
    }

    // Survivor edges
    ctx.lineWidth = nStates <= 16 ? 1 : 0.5;
    for (let t = 1; t < nTime; t++) {
        for (let s = 0; s < nStates; s++) {
            const b = T.survivors[t][s];
            const prev = ((s >> 1) | (b << (m - 1))) & (nStates - 1);
            let alpha = 0.12;
            if (T.path_metrics) {
                alpha = 0.05 + 0.2 * (1 - T.path_metrics[t][s] / pmMax);
            }
            ctx.strokeStyle = `rgba(13,124,62,${alpha})`;
            ctx.beginPath();
            ctx.moveTo(L.xFor(t - 1), L.yFor(prev));
            ctx.lineTo(L.xFor(t), L.yFor(s));
            ctx.stroke();
        }
    }

    // State nodes
    if (nStates <= 64) {
        for (let t = 0; t < nTime; t++) {
            for (let s = 0; s < nStates; s++) {
                let intensity = 0.15;
                if (T.path_metrics)
                    intensity = 0.1 + 0.6 * (1 - T.path_metrics[t][s] / pmMax);
                const r = nStates <= 16 ? 2 : 1.5;
                ctx.fillStyle = `rgba(13,124,62,${intensity})`;
                ctx.beginPath();
                ctx.arc(L.xFor(t), L.yFor(s), r, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }

    return offscreen;
}

function drawTrellis(T, k) {
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

    // Size the visible canvas
    trellisCanvas.width = L.w * dpr;
    trellisCanvas.height = L.h * dpr;
    trellisCanvas.style.width = L.w + "px";
    trellisCanvas.style.height = L.h + "px";

    const ctx = trellisCanvas.getContext("2d");
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    // Blit cached base
    ctx.drawImage(trellisBaseImage, 0, 0);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    // Draw traceback path on top
    const doAnimate = document.getElementById("trellis-animate").checked;
    if (doAnimate) {
        animateTraceback(ctx, T, L.xFor, L.yFor, nStates);
    } else {
        drawTracebackFull(ctx, T, L.xFor, L.yFor, nStates);
    }
}

function drawTracebackFull(ctx, T, xFor, yFor, nStates) {
    ctx.strokeStyle = "#0d7c3e";
    ctx.lineWidth = nStates <= 16 ? 3 : 2;
    ctx.shadowColor = "#0d7c3e";
    ctx.shadowBlur = 4;
    ctx.beginPath();
    ctx.moveTo(xFor(0), yFor(T.traceback_path[0]));
    for (let t = 1; t < T.n_timesteps; t++) {
        ctx.lineTo(xFor(t), yFor(T.traceback_path[t]));
    }
    ctx.stroke();
    ctx.shadowBlur = 0;

    // Highlight nodes
    const r = nStates <= 16 ? 3.5 : 2.5;
    ctx.fillStyle = "#0d7c3e";
    for (let t = 0; t < T.n_timesteps; t++) {
        ctx.beginPath();
        ctx.arc(xFor(t), yFor(T.traceback_path[t]), r, 0, Math.PI * 2);
        ctx.fill();
    }
}

function animateTraceback(ctx, T, xFor, yFor, nStates) {
    const path = T.traceback_path;
    const total = path.length;
    // Animate from right to left (traceback direction)
    let step = total - 1;
    const lineW = nStates <= 16 ? 3 : 2;
    const nodeR = nStates <= 16 ? 3.5 : 2.5;
    const speed = Math.max(10, Math.min(40, 1500 / total));

    function frame() {
        if (step <= 0) {
            trellisAnimId = null;
            return;
        }
        ctx.strokeStyle = "#0d7c3e";
        ctx.lineWidth = lineW;
        ctx.shadowColor = "#0d7c3e";
        ctx.shadowBlur = 4;
        ctx.beginPath();
        ctx.moveTo(xFor(step), yFor(path[step]));
        ctx.lineTo(xFor(step - 1), yFor(path[step - 1]));
        ctx.stroke();
        ctx.shadowBlur = 0;

        ctx.fillStyle = "#0d7c3e";
        ctx.beginPath();
        ctx.arc(xFor(step - 1), yFor(path[step - 1]), nodeR, 0, Math.PI * 2);
        ctx.fill();

        step--;
        trellisAnimId = setTimeout(frame, speed);
    }

    // Draw the rightmost node first
    ctx.fillStyle = "#0d7c3e";
    ctx.beginPath();
    ctx.arc(xFor(total - 1), yFor(path[total - 1]), nodeR, 0, Math.PI * 2);
    ctx.fill();

    frame();
}

// Zoom controls
document.getElementById("trellis-zoom-in").addEventListener("click", () => {
    trellisZoom = Math.min(3, trellisZoom * 1.3);
    if (lastTrellisData) drawTrellis(lastTrellisData, lastTrellisK);
});
document.getElementById("trellis-zoom-out").addEventListener("click", () => {
    trellisZoom = Math.max(0.3, trellisZoom / 1.3);
    if (lastTrellisData) drawTrellis(lastTrellisData, lastTrellisK);
});

// Tooltip on hover
trellisCanvas.addEventListener("mousemove", (e) => {
    if (!lastTrellisData) return;
    const T = lastTrellisData;
    const rect = trellisCanvas.getBoundingClientRect();
    const nStates = T.n_states;
    const L = getTrellisLayout(nStates, T.n_timesteps);

    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const t = Math.round((x - L.marginL) / L.cellW);
    const s = Math.round((y - L.marginT) / L.cellH);

    if (t >= 0 && t < T.n_timesteps && s >= 0 && s < nStates) {
        let pm = "";
        if (T.path_metrics && T.path_metrics[t]) {
            pm = ` PM=${T.path_metrics[t][s]}`;
        }
        const onPath = T.traceback_path[t] === s ? " [ML PATH]" : "";
        trellisTooltip.textContent = `t=${t} state=${s}${pm}${onPath}`;
        trellisTooltip.style.display = "block";
        trellisTooltip.style.left = (e.clientX + 12) + "px";
        trellisTooltip.style.top = (e.clientY - 8) + "px";
    } else {
        trellisTooltip.style.display = "none";
    }
});

trellisCanvas.addEventListener("mouseleave", () => {
    trellisTooltip.style.display = "none";
});

// =========================================================================
// Initialize — wire up event listeners (no inline onclick)
// =========================================================================
sendBtn.addEventListener("click", runDecode);
document.getElementById("run-once-btn").addEventListener("click", runDecode);
document.getElementById("program-btn").addEventListener("click", programFPGA);
modeToggleBtn.addEventListener("click", toggleMode);

checkStatus();
fetchActivity();
setInterval(fetchActivity, 5000);
