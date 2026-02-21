const slides = Array.from(document.querySelectorAll(".slide"));
const prevBtn = document.getElementById("prev-btn");
const nextBtn = document.getElementById("next-btn");
const meta = document.getElementById("meta");

let currentIndex = 0;

function clampIndex(index) {
  if (index < 0) return 0;
  if (index >= slides.length) return slides.length - 1;
  return index;
}

function renderSlide(index) {
  currentIndex = clampIndex(index);

  slides.forEach((slide, idx) => {
    slide.classList.toggle("is-active", idx === currentIndex);
  });

  meta.textContent = `${currentIndex + 1} / ${slides.length}`;
  document.title = `PLANKA — ${slides[currentIndex].dataset.title || "Слайд"}`;
}

function nextSlide() {
  renderSlide(currentIndex + 1);
}

function prevSlide() {
  renderSlide(currentIndex - 1);
}

prevBtn.addEventListener("click", prevSlide);
nextBtn.addEventListener("click", nextSlide);

document.addEventListener("keydown", (event) => {
  if (event.key === "ArrowRight" || event.key === "PageDown" || event.key === " ") {
    event.preventDefault();
    nextSlide();
    return;
  }

  if (event.key === "ArrowLeft" || event.key === "PageUp") {
    event.preventDefault();
    prevSlide();
  }
});

renderSlide(0);

