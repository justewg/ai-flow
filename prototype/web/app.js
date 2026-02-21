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

const displayTextEl = document.getElementById("display-text");
const keyboardEl = document.getElementById("keyboard");
const langToggleEl = document.getElementById("lang-toggle");
const clearButtonEl = document.getElementById("clear-btn");

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
}

function backspace() {
  if (!state.text) {
    return;
  }
  state.text = state.text.slice(0, -1);
  renderDisplay();
  disarmClear();
}

function handleClear() {
  if (!state.clearArmed) {
    armClear();
    return;
  }

  state.text = "";
  renderDisplay();
  disarmClear();
}

function switchLanguage() {
  state.lang = state.lang === "RU" ? "EN" : "RU";
  langToggleEl.textContent = state.lang;
  renderKeyboard();
  disarmClear();
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

langToggleEl.addEventListener("click", switchLanguage);
clearButtonEl.addEventListener("click", handleClear);

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

renderDisplay();
renderKeyboard();

