Shiny.addCustomMessageHandler("set-preferences", function (preferences) {
  var theme = preferences.theme === "dark" ? "dark" : "light";
  var language = preferences.language === "nl" ? "nl" : "en";
  document.documentElement.dataset.theme = theme;
  document.documentElement.lang = language;
  document.body.dataset.theme = theme;
});

(function () {
  "use strict";

  var storageKey = "eshpm-staff-round-timer";
  var ticker = null;
  var audioContext = null;

  function defaultState() {
    return {
      running: false,
      elapsedMs: 0,
      startedAt: null,
      beepEnabled: false,
      beepMinutes: 10,
      beepedAt: null
    };
  }

  function loadState() {
    try {
      var saved = JSON.parse(window.sessionStorage.getItem(storageKey));
      if (!saved || typeof saved !== "object") return defaultState();
      return {
        running: Boolean(saved.running),
        elapsedMs: Math.max(0, Number(saved.elapsedMs) || 0),
        startedAt: Number(saved.startedAt) || null,
        beepEnabled: Boolean(saved.beepEnabled),
        beepMinutes: Math.min(180, Math.max(1, Number(saved.beepMinutes) || 10)),
        beepedAt: Number(saved.beepedAt) || null
      };
    } catch (error) {
      return defaultState();
    }
  }

  var state = loadState();
  if (state.running && state.startedAt === null) state.running = false;

  function saveState() {
    try {
      window.sessionStorage.setItem(storageKey, JSON.stringify(state));
    } catch (error) {
      // The timer still works when a browser blocks session storage.
    }
  }

  function currentElapsedMs() {
    if (!state.running) return state.elapsedMs;
    return state.elapsedMs + Math.max(0, Date.now() - state.startedAt);
  }

  function formatElapsed(milliseconds) {
    var totalSeconds = Math.floor(milliseconds / 1000);
    var minutes = Math.floor(totalSeconds / 60);
    var seconds = totalSeconds % 60;
    return String(minutes).padStart(2, "0") + ":" + String(seconds).padStart(2, "0");
  }

  function prepareAudio() {
    var AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return null;
    if (audioContext === null) audioContext = new AudioContext();
    if (audioContext.state === "suspended") audioContext.resume();
    return audioContext;
  }

  function playBeep() {
    var context = prepareAudio();
    if (context === null) return;
    [0, 0.24].forEach(function (offset) {
      var oscillator = context.createOscillator();
      var gain = context.createGain();
      oscillator.type = "sine";
      oscillator.frequency.value = 880;
      gain.gain.setValueAtTime(0.0001, context.currentTime + offset);
      gain.gain.exponentialRampToValueAtTime(0.18, context.currentTime + offset + 0.015);
      gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + offset + 0.16);
      oscillator.connect(gain);
      gain.connect(context.destination);
      oscillator.start(context.currentTime + offset);
      oscillator.stop(context.currentTime + offset + 0.17);
    });
  }

  function updateTimer() {
    var timer = document.getElementById("staff-round-timer");
    if (timer === null) return;

    var elapsed = currentElapsedMs();
    var readout = document.getElementById("timer-elapsed");
    var startStop = document.getElementById("timer-start-stop");
    var beepEnabled = document.getElementById("timer-beep-enabled");
    var beepMinutes = document.getElementById("timer-beep-minutes");

    if (readout !== null) readout.textContent = formatElapsed(elapsed);
    if (startStop !== null) {
      startStop.textContent = state.running ? startStop.dataset.labelStop : startStop.dataset.labelStart;
      startStop.setAttribute("aria-pressed", state.running ? "true" : "false");
    }
    if (beepEnabled !== null && document.activeElement !== beepEnabled) beepEnabled.checked = state.beepEnabled;
    if (beepMinutes !== null && document.activeElement !== beepMinutes) beepMinutes.value = state.beepMinutes;
    timer.dataset.running = state.running ? "true" : "false";

    var threshold = state.beepMinutes * 60 * 1000;
    if (state.running && state.beepEnabled && elapsed >= threshold && state.beepedAt !== state.beepMinutes) {
      playBeep();
      state.beepedAt = state.beepMinutes;
      saveState();
    }
  }

  document.addEventListener("click", function (event) {
    var startStop = event.target.closest("#timer-start-stop");
    if (startStop !== null) {
      prepareAudio();
      if (state.running) {
        state.elapsedMs = currentElapsedMs();
        state.startedAt = null;
        state.running = false;
      } else {
        state.startedAt = Date.now();
        state.running = true;
      }
      saveState();
      updateTimer();
      return;
    }

    if (event.target.closest("#timer-reset") !== null) {
      state.elapsedMs = 0;
      state.startedAt = null;
      state.running = false;
      state.beepedAt = null;
      saveState();
      updateTimer();
    }
  });

  document.addEventListener("change", function (event) {
    if (event.target.id === "timer-beep-enabled") {
      state.beepEnabled = event.target.checked;
      if (!state.beepEnabled) state.beepedAt = null;
      prepareAudio();
      saveState();
      updateTimer();
    }

    if (event.target.id === "timer-beep-minutes") {
      state.beepMinutes = Math.min(180, Math.max(1, Number(event.target.value) || 10));
      state.beepedAt = null;
      saveState();
      updateTimer();
    }
  });

  ticker = window.setInterval(updateTimer, 250);
  updateTimer();
}());
