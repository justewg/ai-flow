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
const PARENT_TRIGGER_KEYS = Object.freeze(["Р", "О", "Д"]);
const PARENT_TRIGGER_KEY_SET = new Set(PARENT_TRIGGER_KEYS);
const PARENT_ENTRY_PIN = "2580";
const SYSTEM_EXIT_PIN = "9000";
const PIN_LENGTH = 4;
const PIN_LOCKOUT_MS = 10_000;
const PARENT_TRIGGER_COLLECTION_MS = 3_000;
const PARENT_TRIGGER_HOLD_MS = 3_000;

const state = {
  lang: "RU",
  text: "",
  theme: "light",
  clearArmed: false,
  clearTimerId: null,
  parentTrigger: {
    active: false,
    collectionTimerId: null,
    holdTimerId: null,
    pressedCounts: {
      Р: 0,
      О: 0,
      Д: 0,
    },
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
const parentTriggerHintEl = document.getElementById("parent-trigger-hint");
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

function isParentUiOpen() {
  return state.parentControl.gateOpen || state.parentControl.panelOpen;
}

function renderParentTriggerHint() {
  if (parentTriggerHintEl) {
    parentTriggerHintEl.textContent =
      "Родительский вход: в течение 3 секунд зажми Р, О, Д и удерживай все три еще 3 секунды.";
  }
}

function isParentTriggerSymbol(symbol) {
  return PARENT_TRIGGER_KEY_SET.has(symbol);
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

  if (isParentTriggerSymbol(symbol)) {
    keyEl.addEventListener("pointerdown", () => {
      onParentTriggerKeyPressed(symbol);
    });

    const release = () => {
      onParentTriggerKeyReleased(symbol);
    };
    keyEl.addEventListener("pointerup", release);
    keyEl.addEventListener("pointercancel", release);
    keyEl.addEventListener("pointerleave", (event) => {
      if (event.buttons === 0) {
        release();
      }
    });

  } else {
    keyEl.addEventListener("pointerdown", cancelParentTriggerAttempt);
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
  keyEl.addEventListener("pointerdown", cancelParentTriggerAttempt);
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

function clearParentTriggerCollectionTimer() {
  if (state.parentTrigger.collectionTimerId) {
    window.clearTimeout(state.parentTrigger.collectionTimerId);
    state.parentTrigger.collectionTimerId = null;
  }
}

function clearParentTriggerHoldTimer() {
  if (state.parentTrigger.holdTimerId) {
    window.clearTimeout(state.parentTrigger.holdTimerId);
    state.parentTrigger.holdTimerId = null;
  }
}

function resetParentTriggerPressedCounts() {
  for (const symbol of PARENT_TRIGGER_KEYS) {
    state.parentTrigger.pressedCounts[symbol] = 0;
  }
}

function resetParentTriggerState() {
  clearParentTriggerCollectionTimer();
  clearParentTriggerHoldTimer();
  state.parentTrigger.active = false;
  resetParentTriggerPressedCounts();
}

function isAnyParentTriggerKeyPressed() {
  return PARENT_TRIGGER_KEYS.some(
    (symbol) => state.parentTrigger.pressedCounts[symbol] > 0,
  );
}

function areAllParentTriggerKeysPressed() {
  return PARENT_TRIGGER_KEYS.every(
    (symbol) => state.parentTrigger.pressedCounts[symbol] > 0,
  );
}

function startParentTriggerAttempt() {
  state.parentTrigger.active = true;
  clearParentTriggerCollectionTimer();
  state.parentTrigger.collectionTimerId = window.setTimeout(() => {
    resetParentTriggerState();
  }, PARENT_TRIGGER_COLLECTION_MS);
}

function tryOpenParentPinGateFromTrigger() {
  if (!state.parentTrigger.active || !areAllParentTriggerKeysPressed()) {
    return false;
  }
  openPinGate("parent", false);
  resetParentTriggerState();
  return true;
}

function updateParentTriggerProgress() {
  if (!state.parentTrigger.active) {
    return;
  }

  if (areAllParentTriggerKeysPressed()) {
    clearParentTriggerCollectionTimer();
    if (!state.parentTrigger.holdTimerId) {
      state.parentTrigger.holdTimerId = window.setTimeout(() => {
        tryOpenParentPinGateFromTrigger();
      }, PARENT_TRIGGER_HOLD_MS);
    }
    return;
  }

  if (state.parentTrigger.holdTimerId) {
    resetParentTriggerState();
    return;
  }

  if (!isAnyParentTriggerKeyPressed() && !state.parentTrigger.collectionTimerId) {
    resetParentTriggerState();
  }
}

function onParentTriggerKeyPressed(symbol) {
  if (
    !isParentTriggerSymbol(symbol) ||
    isParentUiOpen() ||
    state.lang !== "RU"
  ) {
    return false;
  }

  if (!state.parentTrigger.active) {
    startParentTriggerAttempt();
  }

  state.parentTrigger.pressedCounts[symbol] += 1;
  updateParentTriggerProgress();
  return true;
}

function onParentTriggerKeyReleased(symbol) {
  if (!isParentTriggerSymbol(symbol) || !state.parentTrigger.active) {
    return false;
  }

  if (state.parentTrigger.pressedCounts[symbol] > 0) {
    state.parentTrigger.pressedCounts[symbol] -= 1;
  }
  updateParentTriggerProgress();
  return true;
}

function cancelParentTriggerAttempt() {
  if (!state.parentTrigger.active) {
    return;
  }
  resetParentTriggerState();
}

function getParentTriggerSymbolFromKeyboardKey(keyValue) {
  const key = String(keyValue || "");
  if (key === "р" || key === "Р" || key === "r" || key === "R") {
    return "Р";
  }
  if (key === "о" || key === "О" || key === "o" || key === "O") {
    return "О";
  }
  if (key === "д" || key === "Д" || key === "d" || key === "D") {
    return "Д";
  }
  return null;
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
        : "Комбинация Р+О+Д подтверждена. Введи PIN для входа в родительский режим.";
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
langToggleEl.addEventListener("pointerdown", cancelParentTriggerAttempt);
clearButtonEl.addEventListener("pointerdown", cancelParentTriggerAttempt);
themeToggleEl.addEventListener("pointerdown", cancelParentTriggerAttempt);
parentPinCancelEl.addEventListener("click", () => {
  closePinGate(state.parentControl.pinMode === "system");
});
parentPinOverlayEl.addEventListener("click", (event) => {
  if (event.target !== parentPinOverlayEl || !state.parentControl.gateOpen) {
    return;
  }
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

document.addEventListener("keydown", (event) => {
  const triggerSymbol = getParentTriggerSymbolFromKeyboardKey(event.key);
  if (triggerSymbol && !event.repeat) {
    event.preventDefault();
    onParentTriggerKeyPressed(triggerSymbol);
    return;
  }

  if (state.parentTrigger.active && !event.repeat) {
    event.preventDefault();
    cancelParentTriggerAttempt();
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
  const triggerSymbol = getParentTriggerSymbolFromKeyboardKey(event.key);
  if (!triggerSymbol) {
    return;
  }
  event.preventDefault();
  onParentTriggerKeyReleased(triggerSymbol);
});

window.addEventListener("resize", applyOrientationClass);
window.addEventListener("orientationchange", applyOrientationClass);
window.addEventListener("blur", resetParentTriggerState);
document.addEventListener("visibilitychange", () => {
  if (document.hidden) {
    resetParentTriggerState();
  }
});

renderParentTriggerHint();
restoreState();
renderTheme();
renderClearButtonState();
renderParentControlUi();
langToggleEl.textContent = state.lang;
renderDisplay();
renderKeyboard();
tryLockLandscape();
