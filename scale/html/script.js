'use strict';

const BASE_IN = 72;

function nuiFetch(endpoint, data) {
    let name;
    try {
        name = GetParentResourceName();
    } catch (_) {
        name = 'scale';
        console.warn('[ScaleM] GetParentResourceName unavailable, using fallback: scale');
    }
    const url = `https://${name}/${endpoint}`;
    return fetch(url, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(data ?? {}),
    }).catch(err => {
        console.error(`[ScaleM] fetch failed for "${endpoint}":`, err.message);
    });
}

let minScale     = 0.806;
let maxScale     = 1.194;
let defaultScale = 1.0;
let currentScale = 1.0;

const menu      = document.getElementById('scale-menu');
const slider    = document.getElementById('height-slider');
const impEl     = document.getElementById('height-imperial');
const metEl     = document.getElementById('height-metric');
const scaleEl   = document.getElementById('stat-scale');
const diffEl    = document.getElementById('stat-diff');
const tickMinEl = document.getElementById('tick-min');
const tickMidEl = document.getElementById('tick-mid');
const tickMaxEl = document.getElementById('tick-max');
const rangeEl   = document.getElementById('slider-range');
const defTick   = document.getElementById('def-tick');

function toInches(scale)   { return scale * BASE_IN; }
function toCm(totalIn)     { return Math.round(totalIn * 2.54); }

function fmtImperial(totalIn) {
    const ft   = Math.floor(totalIn / 12);
    let   inch = Math.round(totalIn % 12);
    if (inch === 12) return `${ft + 1}'0"`;
    return `${ft}'${inch}"`;
}

function scaleToSlider(s) { return ((s - minScale) / (maxScale - minScale)) * 1000; }
function sliderToScale(v) { return minScale + (v / 1000) * (maxScale - minScale); }

function updateDisplay(scale) {
    currentScale = scale;

    const inches   = toInches(scale);
    const defIn    = toInches(defaultScale);
    const diffIn   = Math.round(inches - defIn);
    const progress = ((scale - minScale) / (maxScale - minScale)) * 100;

    impEl.textContent   = fmtImperial(inches);
    metEl.textContent   = toCm(inches) + ' cm';
    scaleEl.textContent = scale.toFixed(2) + '×';
    diffEl.textContent  = (diffIn >= 0 ? '+' : '') + diffIn + '"';

    slider.style.setProperty('--fill', progress.toFixed(2) + '%');
    slider.value = Math.round(scaleToSlider(scale));

    impEl.classList.remove('glow');
    void impEl.offsetWidth;
    impEl.classList.add('glow');
    setTimeout(() => impEl.classList.remove('glow'), 200);
}

function applyTheme(hex) {
    if (!hex) return;
    // Theme is locked to Love Street Stories pink, but allow overrides
    document.documentElement.style.setProperty('--hot-pink', hex);
    document.documentElement.style.setProperty('--neon-pink', hex);
}

function openMenu(data) {
    // Keep LSS pink as default, apply server override if provided
    if (data.themeColor) applyTheme(data.themeColor);

    minScale     = data.minScale     ?? 0.806;
    maxScale     = data.maxScale     ?? 1.194;
    defaultScale = data.defaultScale ?? 1.0;

    const minIn = toInches(minScale);
    const defIn = toInches(defaultScale);
    const maxIn = toInches(maxScale);

    tickMinEl.textContent = fmtImperial(minIn);
    tickMidEl.textContent = fmtImperial(defIn);
    tickMaxEl.textContent = fmtImperial(maxIn);
    rangeEl.textContent   = fmtImperial(minIn) + ' — ' + fmtImperial(maxIn);

    const defPct = ((defaultScale - minScale) / (maxScale - minScale)) * 100;
    defTick.style.left = defPct.toFixed(2) + '%';

    updateDisplay(data.scale ?? defaultScale);

    menu.classList.remove('hidden');
    requestAnimationFrame(() =>
        requestAnimationFrame(() => menu.classList.add('visible'))
    );
}

function closeMenu() {
    menu.classList.remove('visible');
    setTimeout(() => menu.classList.add('hidden'), 380);
}

slider.addEventListener('input', function () {
    const scale = sliderToScale(parseFloat(this.value));
    updateDisplay(scale);
    nuiFetch('preview', { scale: scale });
});

document.getElementById('btn-confirm').addEventListener('click', () => {
    nuiFetch('confirm', { scale: currentScale });
    closeMenu();
});

document.getElementById('btn-reset').addEventListener('click', () => {
    nuiFetch('reset');
    closeMenu();
});

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data?.type) return;
    if (data.type === 'openMenu')  openMenu(data);
    if (data.type === 'closeMenu') closeMenu();
});

window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        nuiFetch('close');
        closeMenu();
    }
});
