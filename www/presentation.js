document.addEventListener("DOMContentLoaded", function () {
  var page = document.querySelector(".presentation-page");
  if (page) {
    document.documentElement.dataset.theme = page.dataset.theme || "light";
    document.documentElement.lang = page.dataset.language || "en";
  }
  var slides = Array.from(document.querySelectorAll(".result-slide"));
  var counter = document.getElementById("slide-counter");
  var previous = document.getElementById("previous_slide");
  var next = document.getElementById("next_slide");
  var current = 0;

  if (slides.length === 0) return;

  function showSlide(index) {
    current = Math.max(0, Math.min(slides.length - 1, index));
    slides.forEach(function (slide, slideIndex) {
      slide.classList.toggle("active", slideIndex === current);
    });
    if (counter) counter.textContent = (current + 1) + " / " + slides.length;
    if (previous) previous.disabled = current === 0;
    if (next) next.disabled = current === slides.length - 1;
  }

  if (previous) previous.addEventListener("click", function () {
    showSlide(current - 1);
  });
  if (next) next.addEventListener("click", function () {
    showSlide(current + 1);
  });

  document.addEventListener("keydown", function (event) {
    if (["ArrowRight", "ArrowDown", "PageDown", " "].includes(event.key)) {
      event.preventDefault();
      showSlide(current + 1);
    }
    if (["ArrowLeft", "ArrowUp", "PageUp"].includes(event.key)) {
      event.preventDefault();
      showSlide(current - 1);
    }
    if (event.key === "Home") showSlide(0);
    if (event.key === "End") showSlide(slides.length - 1);
  });

  showSlide(0);
});
