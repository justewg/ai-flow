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
  clearArmed: false,
  clearTimerId: null,
};

const STORAGE_KEY = "planka-prototype-state-v1";

const displayTextEl = document.getElementById("display-text");
const keyboardEl = document.getElementById("keyboard");
const langToggleEl = document.getElementById("lang-toggle");
const clearButtonEl = document.getElementById("clear-btn");
const orientationStateEl = document.getElementById("orientation-state");
const retryOrientationBtn = document.getElementById("retry-orientation-btn");

function renderDisplay() {
  displayTextEl.textContent = state.text;
  displayTextEl.classList.toggle("empty", state.text.length === 0);
}

function disarmClear() {
  state.clearArmed = false;
  clearButtonEl.textContent = "Очистить";
  if (state.clearTimerId) {
    window.clearTimeout(state.clearTimerId);
    state.clearTimerId = null;
  }
}

function armClear() {
  state.clearArmed = true;
  clearButtonEl.textContent = "Подтвердить";
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
  keyEl.textContent = symbol;
  keyEl.addEventListener("click", () => appendText(symbol));
  return keyEl;
}

function createControlKey(label, className, onClick) {
  const keyEl = document.createElement("button");
  keyEl.type = "button";
  keyEl.className = `key ${className}`;
  keyEl.textContent = label;
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
    createControlKey("Язык", "lang", switchLanguage),
  );
  keyboardEl.appendChild(
    createControlKey("Пробел", "space", () => appendText(" ")),
  );
  keyboardEl.appendChild(
    createControlKey("Backspace", "backspace", backspace),
  );
}

function persistState() {
  const snapshot = {
    text: state.text,
    lang: state.lang,
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
  } catch {
    state.text = "";
    state.lang = "RU";
  }
}

function applyOrientationClass() {
  const isLandscape = window.matchMedia("(orientation: landscape)").matches;
  document.body.classList.toggle("is-portrait", !isLandscape);
}

function setOrientationStateLabel(label) {
  orientationStateEl.textContent = label;
}

async function tryLockLandscape() {
  applyOrientationClass();

  if (!window.screen.orientation || !window.screen.orientation.lock) {
    setOrientationStateLabel("landscape lock: not supported");
    return;
  }

  try {
    await window.screen.orientation.lock("landscape");
    setOrientationStateLabel("landscape lock: active");
  } catch {
    setOrientationStateLabel("landscape lock: blocked");
  } finally {
    applyOrientationClass();
  }
}

langToggleEl.addEventListener("click", switchLanguage);
clearButtonEl.addEventListener("click", handleClear);
retryOrientationBtn.addEventListener("click", () => {
  tryLockLandscape();
});

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
langToggleEl.textContent = state.lang;
renderDisplay();
renderKeyboard();
tryLockLandscape();
