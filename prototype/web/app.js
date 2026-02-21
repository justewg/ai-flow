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

const state = {
  lang: "RU",
  text: "",
  theme: "light",
  clearArmed: false,
  clearTimerId: null,
};

const STORAGE_KEY = "planka-prototype-state-v1";
let orientationLockState = "pending";

const displayTextEl = document.getElementById("display-text");
const keyboardEl = document.getElementById("keyboard");
const langToggleEl = document.getElementById("lang-toggle");
const clearButtonEl = document.getElementById("clear-btn");
const themeToggleEl = document.getElementById("theme-toggle");
const themeIconEl = document.getElementById("theme-icon");

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
  state.text += symbol;
  renderDisplay();
  disarmClear();
  persistState();
}

function backspace() {
  if (!state.text) {
    return;
  }
  state.text = state.text.slice(0, -1);
  renderDisplay();
  disarmClear();
  persistState();
}

function handleClear() {
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

function renderKeyboard() {
  keyboardEl.innerHTML = "";

  for (const row of LAYOUTS[state.lang]) {
    for (const symbol of row) {
      keyboardEl.appendChild(createLetterKey(symbol));
    }

    const spacerCount = fillRowToGridSize(row.length);
    for (let i = 0; i < spacerCount; i += 1) {
      const spacer = document.createElement("div");
      keyboardEl.appendChild(spacer);
    }
  }

  keyboardEl.appendChild(
    createControlKey("⎵", "space", () => appendText(" "), "Пробел"),
  );
  keyboardEl.appendChild(
    createControlKey("←", "backspace", backspace, "Удалить символ"),
  );
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

document.addEventListener("keydown", (event) => {
  if (event.key === "Backspace") {
    event.preventDefault();
    backspace();
    return;
  }

  if (event.key === " ") {
    event.preventDefault();
    appendText(" ");
  }
});

window.addEventListener("resize", applyOrientationClass);
window.addEventListener("orientationchange", applyOrientationClass);

restoreState();
renderTheme();
renderClearButtonState();
langToggleEl.textContent = state.lang;
renderDisplay();
renderKeyboard();
tryLockLandscape();
