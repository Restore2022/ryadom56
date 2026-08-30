(function () {
  var KEY = "ryadom56.theme";

  function current() {
    return document.documentElement.getAttribute("data-theme") === "light" ? "light" : "dark";
  }

  function paint(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    try {
      localStorage.setItem(KEY, theme);
    } catch (err) {}
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", theme === "dark" ? "#101712" : "#eef3ea");
    document.querySelectorAll(".theme-btn").forEach(function (btn) {
      var dark = theme === "dark";
      btn.setAttribute("aria-pressed", String(dark));
      btn.setAttribute("aria-label", dark ? "Включить светлое оформление" : "Включить тёмное оформление");
      btn.title = dark ? "Светлая тема" : "Тёмная тема";
    });
  }

  document.querySelectorAll(".theme-btn").forEach(function (btn) {
    btn.addEventListener("click", function () {
      paint(current() === "dark" ? "light" : "dark");
    });
  });

  paint(current());
})();
