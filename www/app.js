Shiny.addCustomMessageHandler("set-preferences", function (preferences) {
  var theme = preferences.theme === "dark" ? "dark" : "light";
  var language = preferences.language === "nl" ? "nl" : "en";
  document.documentElement.dataset.theme = theme;
  document.documentElement.lang = language;
  document.body.dataset.theme = theme;
});
