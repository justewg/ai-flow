const LAYOUTS = {
  RU: [
    ["Й", "Ц", "У", "К", "Е", "Н", "Г", "Ш", "Щ", "З", "Х", "Ъ"],
    ["Ф", "Ы", "В", "А", "П", "Р", "О", "Л", "Д", "Ж", "Э"],
    ["Я", "Ч", "С", "М", "И", "Т", "Ь", "Б", "Ю"],
  ],
  EN: [
    ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
    ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
    ["Z", "X", "C", "V", "B", "N", "M"],
  ],
};

const NUMBER_ROW = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"];
const PARENT_TRIGGER_SYMBOL = "Р";
const PARENT_ENTRY_PIN = "2580";
const SYSTEM_EXIT_PIN = "9000";
const PIN_LENGTH = 4;
const PIN_LOCKOUT_MS = 10_000;
const PARENT_TRIGGER_WINDOW_MS = 2_000;
const PARENT_TRIGGER_MODE_QUERY_KEYS = ["parentTriggerMode", "parent_mode"];
const PARENT_TRIGGER_MODE = Object.freeze({
  PROD: "prod",
  DEV: "dev",
});

const state = {
  lang: "RU",
  text: "",
  theme: "light",
  clearArmed: false,
  clearTimerId: null,
  parentTrigger: {
    rHoldActive: false,
    windowActive: false,
    comboMatched: false,
    windowTimerId: null,
    volumeUpPressed: false,
    volumeDownPressed: false,
  },
  parentControl: {
    gateOpen: false,
    panelOpen: false,
    pinMode: "parent",
    pinInput: "",
    pinError: "",
    pinBlockUntil: 0,
    pinBlockTimerId: null,
    statusMessage: "",
  },
};

const STORAGE_KEY = "planka-prototype-state-v1";
let orientationLockState = "pending";

const displayTextEl = document.getElementById("display-text");
const keyboardEl = document.getElementById("keyboard");
const langToggleEl = document.getElementById("lang-toggle");
const clearButtonEl = document.getElementById("clear-btn");
const themeToggleEl = document.getElementById("theme-toggle");
const themeIconEl = document.getElementById("theme-icon");
const parentTriggerDevControlsEl = document.getElementById("parent-trigger-dev-controls");
const parentVolumeUpDevEl = document.getElementById("parent-volume-up-dev");
const parentVolumeDownDevEl = document.getElementById("parent-volume-down-dev");
const parentPinOverlayEl = document.getElementById("parent-pin-overlay");
const parentPinSubtitleEl = document.getElementById("parent-pin-subtitle");
const parentPinDotsEl = document.getElementById("parent-pin-dots");
const parentPinErrorEl = document.getElementById("parent-pin-error");
const parentPinCancelEl = document.getElementById("parent-pin-cancel");
const pinDigitEls = Array.from(document.querySelectorAll("[data-pin-digit]"));
const pinBackspaceEl = document.querySelector("[data-pin-action='backspace']");
const parentPanelEl = document.getElementById("parent-panel");
const parentPanelStatusEl = document.getElementById("parent-panel-status");
const parentSystemBtnEl = document.getElementById("parent-system-btn");
const parentCloseBtnEl = document.getElementById("parent-close-btn");
const parentActionEls = Array.from(document.querySelectorAll("[data-parent-action]"));
const parentTriggerMode = detectParentTriggerMode();

function isAppleMobileTouchDevice() {
  const ua = String(window.navigator.userAgent || "");
  const platform = String(window.navigator.platform || "");
  const touchPoints = Number(window.navigator.maxTouchPoints || 0);
  return (
    /iPad|iPhone|iPod/i.test(ua) ||
    (platform === "MacIntel" && touchPoints > 1)
  );
}

function detectParentTriggerMode() {
  const params = new URLSearchParams(window.location.search);
  for (const key of PARENT_TRIGGER_MODE_QUERY_KEYS) {
    const mode = String(params.get(key) || "")
      .trim()
      .toLowerCase();
    if (mode === PARENT_TRIGGER_MODE.PROD || mode === PARENT_TRIGGER_MODE.DEV) {
      return mode;
    }
  }
  return isAppleMobileTouchDevice() ? PARENT_TRIGGER_MODE.DEV : PARENT_TRIGGER_MODE.PROD;
}

function isParentTriggerDevMode() {
  return parentTriggerMode === PARENT_TRIGGER_MODE.DEV;
}

function isParentUiOpen() {
  return state.parentControl.gateOpen || state.parentControl.panelOpen;
}

function applyParentTriggerModeUi() {
  const isDevMode = isParentTriggerDevMode();
  if (parentTriggerDevControlsEl) {
    parentTriggerDevControlsEl.hidden = !isDevMode;
  }
}

function setKeyLabel(keyEl, label) {
  const labelEl = document.createElement("span");
  labelEl.className = "key-label";
  labelEl.textContent = label;
  keyEl.replaceChildren(labelEl);
}

function renderClearButtonState() {
  clearButtonEl.classList.toggle("is-armed", state.clearArmed);
  clearButtonEl.setAttribute(
    "aria-label",
    state.clearArmed ? "Подтвердить очистку" : "Очистить текст",
  );
}

function renderDisplay() {
  displayTextEl.textContent = state.text;
  displayTextEl.classList.toggle("empty", state.text.length === 0);
}

function disarmClear() {
  state.clearArmed = false;
  renderClearButtonState();
  if (state.clearTimerId) {
    window.clearTimeout(state.clearTimerId);
    state.clearTimerId = null;
  }
}

function armClear() {
  state.clearArmed = true;
  renderClearButtonState();
  state.clearTimerId = window.setTimeout(disarmClear, 1800);
}

function appendText(symbol) {
  if (isParentUiOpen()) {
    return;
  }
  state.text += symbol;
  renderDisplay();
  disarmClear();
  persistState();
}

function backspace() {
  if (isParentUiOpen()) {
    return;
  }
  if (!state.text) {
    return;
  }
  state.text = state.text.slice(0, -1);
  renderDisplay();
  disarmClear();
  persistState();
}

function handleClear() {
  if (isParentUiOpen()) {
    return;
  }
  if (!state.clearArmed) {
    armClear();
    return;
  }

  state.text = "";
  renderDisplay();
  disarmClear();
  persistState();
}

function switchLanguage() {
  if (isParentUiOpen()) {
    return;
  }
  state.lang = state.lang === "RU" ? "EN" : "RU";
  langToggleEl.textContent = state.lang;
  renderKeyboard();
  disarmClear();
  persistState();
}

function createLetterKey(symbol) {
  const keyEl = document.createElement("button");
  keyEl.type = "button";
  keyEl.className = "key letter";
  setKeyLabel(keyEl, symbol);

  if (symbol === PARENT_TRIGGER_SYMBOL) {
    keyEl.addEventListener("pointerdown", (event) => {
      event.preventDefault();
      startParentTriggerHold();
    });

    const release = () => {
      finishParentTriggerHold();
    };
    keyEl.addEventListener("pointerup", release);
    keyEl.addEventListener("pointercancel", release);
    keyEl.addEventListener("pointerleave", (event) => {
      if (event.buttons === 0) {
        release();
      }
    });

    return keyEl;
  }

  keyEl.addEventListener("click", () => appendText(symbol));
  return keyEl;
}

function createControlKey(label, className, onClick, ariaLabel = label) {
  const keyEl = document.createElement("button");
  keyEl.type = "button";
  keyEl.className = `key ${className}`;
  keyEl.setAttribute("aria-label", ariaLabel);
  setKeyLabel(keyEl, label);
  keyEl.addEventListener("click", onClick);
  return keyEl;
}

function fillRowToGridSize(rowLength, totalColumns = 12) {
  return Math.max(0, totalColumns - rowLength);
}

function appendSpacers(count) {
  for (let i = 0; i < count; i += 1) {
    const spacer = document.createElement("div");
    keyboardEl.appendChild(spacer);
  }
}

function renderKeyboard() {
  keyboardEl.innerHTML = "";

  for (const symbol of NUMBER_ROW) {
    keyboardEl.appendChild(createLetterKey(symbol));
  }
  appendSpacers(fillRowToGridSize(NUMBER_ROW.length));

  for (const [rowIndex, row] of LAYOUTS[state.lang].entries()) {
    for (const symbol of row) {
      keyboardEl.appendChild(createLetterKey(symbol));
    }

    if (rowIndex === 2) {
      appendSpacers(fillRowToGridSize(row.length + 1));
      keyboardEl.appendChild(
        createControlKey("↵", "enter", () => appendText("\n"), "Новая строка"),
      );
      continue;
    }

    appendSpacers(fillRowToGridSize(row.length));
  }

  keyboardEl.appendChild(
    createControlKey("⎵", "space", () => appendText(" "), "Пробел"),
  );
  keyboardEl.appendChild(
    createControlKey("←", "backspace", backspace, "Удалить символ"),
  );
}

function clearParentTriggerWindowTimer() {
  if (state.parentTrigger.windowTimerId) {
    window.clearTimeout(state.parentTrigger.windowTimerId);
    state.parentTrigger.windowTimerId = null;
  }
}

function resetParentTriggerState() {
  clearParentTriggerWindowTimer();
  state.parentTrigger.rHoldActive = false;
  state.parentTrigger.windowActive = false;
  state.parentTrigger.comboMatched = false;
}

function resetParentTriggerHardwareState() {
  state.parentTrigger.volumeUpPressed = false;
  state.parentTrigger.volumeDownPressed = false;
}

function startParentTriggerHold() {
  if (isParentUiOpen() || state.lang !== "RU") {
    return;
  }

  clearParentTriggerWindowTimer();
  state.parentTrigger.rHoldActive = true;
  state.parentTrigger.comboMatched = false;
  state.parentTrigger.windowActive = true;
  state.parentTrigger.windowTimerId = window.setTimeout(() => {
    state.parentTrigger.windowActive = false;
    state.parentTrigger.windowTimerId = null;
  }, PARENT_TRIGGER_WINDOW_MS);
}

function finishParentTriggerHold() {
  if (!state.parentTrigger.rHoldActive) {
    return;
  }

  const shouldTypeSymbol = !state.parentTrigger.comboMatched && !isParentUiOpen();
  resetParentTriggerState();
  if (shouldTypeSymbol) {
    appendText(PARENT_TRIGGER_SYMBOL);
  }
}

function getVolumeKeyType(event) {
  const key = String(event.key || "");
  const code = String(event.code || "");

  if (key === "AudioVolumeUp" || code === "AudioVolumeUp" || key === "F9" || code === "F9") {
    return "up";
  }
  if (
    key === "AudioVolumeDown" ||
    code === "AudioVolumeDown" ||
    key === "F10" ||
    code === "F10"
  ) {
    return "down";
  }

  return null;
}

function setVolumeKeyPressed(volumeKeyType, isPressed) {
  if (volumeKeyType === "up") {
    state.parentTrigger.volumeUpPressed = isPressed;
    return;
  }
  state.parentTrigger.volumeDownPressed = isPressed;
}

function onVolumeKeyPressed(volumeKeyType) {
  setVolumeKeyPressed(volumeKeyType, true);
  tryOpenParentPinGateFromTrigger();
}

function onVolumeKeyReleased(volumeKeyType) {
  setVolumeKeyPressed(volumeKeyType, false);
}

function bindDevVolumeControl(buttonEl, volumeKeyType) {
  if (!buttonEl) {
    return;
  }

  buttonEl.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    onVolumeKeyPressed(volumeKeyType);
  });

  const release = (event) => {
    if (event) {
      event.preventDefault();
    }
    onVolumeKeyReleased(volumeKeyType);
  };

  buttonEl.addEventListener("pointerup", release);
  buttonEl.addEventListener("pointercancel", release);
  buttonEl.addEventListener("pointerleave", (event) => {
    if (event.buttons === 0) {
      release(event);
    }
  });
}

function tryOpenParentPinGateFromTrigger() {
  const triggerReady =
    state.parentTrigger.rHoldActive &&
    state.parentTrigger.windowActive &&
    state.parentTrigger.volumeUpPressed &&
    state.parentTrigger.volumeDownPressed;

  if (!triggerReady) {
    return false;
  }

  state.parentTrigger.comboMatched = true;
  openPinGate("parent", false);
  resetParentTriggerState();
  resetParentTriggerHardwareState();
  return true;
}

function isPinBlocked() {
  return Date.now() < state.parentControl.pinBlockUntil;
}

function clearPinBlockTimer() {
  if (state.parentControl.pinBlockTimerId) {
    window.clearTimeout(state.parentControl.pinBlockTimerId);
    state.parentControl.pinBlockTimerId = null;
  }
}

function buildPinDots() {
  parentPinDotsEl.innerHTML = "";
  for (let i = 0; i < PIN_LENGTH; i += 1) {
    const dotEl = document.createElement("span");
    dotEl.className = "pin-dot";
    if (i < state.parentControl.pinInput.length) {
      dotEl.classList.add("filled");
    }
    parentPinDotsEl.appendChild(dotEl);
  }
}

function renderParentControlUi() {
  parentPinOverlayEl.hidden = !state.parentControl.gateOpen;
  parentPanelEl.hidden = !state.parentControl.panelOpen;

  if (state.parentControl.gateOpen) {
    parentPinSubtitleEl.textContent =
      state.parentControl.pinMode === "system"
        ? "Уровень 2: подтверждение выхода в системный режим"
        : isParentTriggerDevMode()
          ? "Dev-режим: удерживай Р + VOL+/VOL- на экране (или F9/F10), затем введи PIN"
          : "Удерживай Р + обе громкости (или F9/F10), затем введи PIN";
    buildPinDots();

    const blocked = isPinBlocked();
    const hasError = state.parentControl.pinError.length > 0;
    parentPinErrorEl.textContent = hasError ? state.parentControl.pinError : "";
    parentPinErrorEl.hidden = !hasError;

    const controlsDisabled = blocked;
    for (const pinDigitEl of pinDigitEls) {
      pinDigitEl.disabled = controlsDisabled;
    }
    pinBackspaceEl.disabled = controlsDisabled;
  }

  parentPanelStatusEl.textContent = state.parentControl.statusMessage;
}

function openPinGate(mode, keepParentPanelOpen) {
  state.parentControl.pinMode = mode;
  state.parentControl.pinInput = "";
  state.parentControl.pinError = isPinBlocked()
    ? "Слишком много попыток. Подожди 10 секунд."
    : "";
  state.parentControl.gateOpen = true;
  state.parentControl.panelOpen = keepParentPanelOpen;
  renderParentControlUi();
}

function closePinGate(keepParentPanelOpen) {
  state.parentControl.gateOpen = false;
  state.parentControl.pinInput = "";
  state.parentControl.pinError = "";
  state.parentControl.panelOpen = keepParentPanelOpen;
  renderParentControlUi();
}

function openParentPanel(statusMessage = "Режим родителя активирован.") {
  state.parentControl.gateOpen = false;
  state.parentControl.panelOpen = true;
  state.parentControl.pinInput = "";
  state.parentControl.pinError = "";
  state.parentControl.statusMessage = statusMessage;
  renderParentControlUi();
}

function closeParentPanel() {
  state.parentControl.gateOpen = false;
  state.parentControl.panelOpen = false;
  state.parentControl.pinInput = "";
  state.parentControl.pinError = "";
  state.parentControl.statusMessage = "";
  renderParentControlUi();
}

function lockPinInputWithDelay() {
  state.parentControl.pinInput = "";
  state.parentControl.pinBlockUntil = Date.now() + PIN_LOCKOUT_MS;
  state.parentControl.pinError = "Неверный PIN. Повтори через 10 секунд.";
  clearPinBlockTimer();
  state.parentControl.pinBlockTimerId = window.setTimeout(() => {
    state.parentControl.pinBlockUntil = 0;
    state.parentControl.pinError = "";
    state.parentControl.pinBlockTimerId = null;
    renderParentControlUi();
  }, PIN_LOCKOUT_MS);
}

function validatePin() {
  const expectedPin =
    state.parentControl.pinMode === "system" ? SYSTEM_EXIT_PIN : PARENT_ENTRY_PIN;
  if (state.parentControl.pinInput !== expectedPin) {
    lockPinInputWithDelay();
    renderParentControlUi();
    return;
  }

  if (state.parentControl.pinMode === "system") {
    openParentPanel(
      "Уровень 2 подтверждён. В native-shell здесь будет переход в Android.",
    );
    return;
  }

  openParentPanel();
}

function appendPinDigit(digit) {
  if (!state.parentControl.gateOpen || isPinBlocked()) {
    return;
  }

  if (state.parentControl.pinInput.length >= PIN_LENGTH) {
    return;
  }

  state.parentControl.pinError = "";
  state.parentControl.pinInput += digit;
  renderParentControlUi();

  if (state.parentControl.pinInput.length === PIN_LENGTH) {
    validatePin();
  }
}

function removePinDigit() {
  if (!state.parentControl.gateOpen || isPinBlocked()) {
    return;
  }

  state.parentControl.pinInput = state.parentControl.pinInput.slice(0, -1);
  state.parentControl.pinError = "";
  renderParentControlUi();
}

function handleParentAction(action) {
  const messages = {
    sync: "История помечена к выгрузке в бэкенд (демо-интерфейс).",
    stats: "Сегодня: 47 минут использования, 136 символов (демо).",
    wifi: "Сетевые настройки доступны после PIN уровня 2.",
  };
  state.parentControl.statusMessage = messages[action] || "";
  renderParentControlUi();
}

function persistState() {
  const snapshot = {
    text: state.text,
    lang: state.lang,
    theme: state.theme,
  };
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot));
}

function restoreState() {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      return;
    }

    const saved = JSON.parse(raw);
    if (typeof saved.text === "string") {
      state.text = saved.text;
    }
    if (saved.lang === "RU" || saved.lang === "EN") {
      state.lang = saved.lang;
    }
    if (saved.theme === "light" || saved.theme === "dark") {
      state.theme = saved.theme;
    }
  } catch {
    state.text = "";
    state.lang = "RU";
    state.theme = "light";
  }
}

function renderTheme() {
  const isDark = state.theme === "dark";
  document.body.classList.toggle("theme-dark", isDark);
  themeIconEl.textContent = isDark ? "☀" : "☾";
}

function toggleTheme() {
  if (isParentUiOpen()) {
    return;
  }
  state.theme = state.theme === "dark" ? "light" : "dark";
  renderTheme();
  persistState();
}

function applyOrientationClass() {
  const isLandscape = window.matchMedia("(orientation: landscape)").matches;
  document.body.classList.toggle("is-portrait", !isLandscape);
  updateOrientationHint();
}

function updateOrientationHint() {
  const isPortrait = window.matchMedia("(orientation: portrait)").matches;
  const needHint = isPortrait && orientationLockState !== "active";
  document.body.classList.toggle("needs-orientation-hint", needHint);
}

async function tryLockLandscape() {
  if (!window.screen.orientation || !window.screen.orientation.lock) {
    orientationLockState = "not-supported";
    applyOrientationClass();
    return;
  }

  try {
    await window.screen.orientation.lock("landscape");
    orientationLockState = "active";
  } catch {
    orientationLockState = "blocked";
  } finally {
    applyOrientationClass();
  }
}

langToggleEl.addEventListener("click", switchLanguage);
clearButtonEl.addEventListener("click", handleClear);
themeToggleEl.addEventListener("click", toggleTheme);
parentPinCancelEl.addEventListener("click", () => {
  closePinGate(state.parentControl.pinMode === "system");
});

for (const pinDigitEl of pinDigitEls) {
  pinDigitEl.addEventListener("click", () => {
    appendPinDigit(pinDigitEl.dataset.pinDigit);
  });
}

pinBackspaceEl.addEventListener("click", removePinDigit);
parentSystemBtnEl.addEventListener("click", () => openPinGate("system", true));
parentCloseBtnEl.addEventListener("click", closeParentPanel);

for (const parentActionEl of parentActionEls) {
  parentActionEl.addEventListener("click", () => {
    handleParentAction(parentActionEl.dataset.parentAction);
  });
}

if (isParentTriggerDevMode()) {
  bindDevVolumeControl(parentVolumeUpDevEl, "up");
  bindDevVolumeControl(parentVolumeDownDevEl, "down");
}

document.addEventListener("keydown", (event) => {
  const volumeKeyType = getVolumeKeyType(event);
  if (volumeKeyType) {
    event.preventDefault();
    onVolumeKeyPressed(volumeKeyType);
    return;
  }

  if (isParentUiOpen()) {
    return;
  }

  if (event.key === "Backspace") {
    event.preventDefault();
    backspace();
    return;
  }

  if (event.key === " ") {
    event.preventDefault();
    appendText(" ");
    return;
  }

  if (event.key === "Enter") {
    event.preventDefault();
    appendText("\n");
  }
});

document.addEventListener("keyup", (event) => {
  const volumeKeyType = getVolumeKeyType(event);
  if (!volumeKeyType) {
    return;
  }
  event.preventDefault();
  onVolumeKeyReleased(volumeKeyType);
});

window.addEventListener("resize", applyOrientationClass);
window.addEventListener("orientationchange", applyOrientationClass);
window.addEventListener("blur", resetParentTriggerHardwareState);
document.addEventListener("visibilitychange", () => {
  if (document.hidden) {
    resetParentTriggerHardwareState();
  }
});

applyParentTriggerModeUi();
restoreState();
renderTheme();
renderClearButtonState();
renderParentControlUi();
langToggleEl.textContent = state.lang;
renderDisplay();
renderKeyboard();
tryLockLandscape();
