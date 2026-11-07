// Bar widget strings, pure JS so `node --test` covers them.
//
// The widget runs inside Omarchy's Quickshell config and cannot import Kisaru's
// services/I18n.qml, so it carries this small table and resolver instead. Only
// English and Spanish exist: the app ships those two, and the bar must not
// grow a third language the panels cannot show.
//
// Language precedence matches services/I18n.qml: QS_LANG (env) -> the app's
// settings.json -> LANG -> English. Normalization matches services/prefs.js:
// anything that starts with "es" is Spanish, everything else English.
//
// The settings file belongs to the app (services/UiPrefs.qml is its only
// writer), so it is read here and never written. The folder rule is the one in
// services/app_paths.js: `kisaru`, or the inherited `qs-novelmangareader`
// while only that one exists.
//
// Top-level functions only: Panel.qml imports this file with
// `import "strings.js" as Strings`, while `node --test` reads the guarded
// `module.exports` at the bottom.

var CONFIG_DIR = "kisaru";
var LEGACY_CONFIG_DIR = "qs-novelmangareader";
var SETTINGS_FILE = "settings.json";

var tables = {
    en: {
        "entry.anime": "Anime",
        "entry.manga": "Manga",
        "entry.novel": "Novels",
        "menu.title": "Reader",
        "menu.tooltip": "Reader — Anime / Manga / Novels"
    },
    es: {
        "entry.anime": "Anime",
        "entry.manga": "Manga",
        "entry.novel": "Novelas",
        "menu.title": "Lector",
        "menu.tooltip": "Lector — Anime / Manga / Novelas"
    }
};

// Same rule as services/prefs.js: Spanish-ish becomes "es", the rest "en".
function normalizeLanguage(value) {
    return String(value || "").trim().toLowerCase().indexOf("es") === 0 ? "es" : "en";
}

// "es" | "en" from settings.json text, "" when the file is missing, broken, or
// holds something else (the app writes only those two).
function languageFromSettings(text) {
    try {
        var data = JSON.parse(String(text || ""));
        if (!data || typeof data !== "object")
            return "";
        var value = data.language;
        return (value === "es" || value === "en") ? value : "";
    } catch (error) {
        return "";
    }
}

function resolveLanguage(envLang, settingsLang, systemLang) {
    var env = String(envLang || "").trim();
    if (env)
        return normalizeLanguage(env);
    var settings = String(settingsLang || "").trim();
    if (settings)
        return normalizeLanguage(settings);
    return normalizeLanguage(systemLang);
}

// The app's settings file inside a config root (`$XDG_CONFIG_HOME` or
// `$HOME/.config`); `legacy` asks for the inherited folder.
function settingsFile(baseDir, legacy) {
    return String(baseDir || "") + "/" + (legacy ? LEGACY_CONFIG_DIR : CONFIG_DIR) + "/" + SETTINGS_FILE;
}

// The new file when it exists, the inherited one while it is the only one that
// does, and the new one when neither does — one ordered list, never two
// probes racing: the caller tries [0], and only a failed load moves it to [1].
function settingsCandidates(baseDir) {
    return [settingsFile(baseDir, false), settingsFile(baseDir, true)];
}

// A missing key falls back to English, then to the key itself, so a typo shows
// up instead of rendering an empty label.
function t(lang, key) {
    var table = tables[normalizeLanguage(lang)] || tables.en;
    if (Object.prototype.hasOwnProperty.call(table, key))
        return table[key];
    if (Object.prototype.hasOwnProperty.call(tables.en, key))
        return tables.en[key];
    return String(key);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        CONFIG_DIR: CONFIG_DIR,
        LEGACY_CONFIG_DIR: LEGACY_CONFIG_DIR,
        tables: tables,
        normalizeLanguage: normalizeLanguage,
        languageFromSettings: languageFromSettings,
        resolveLanguage: resolveLanguage,
        settingsFile: settingsFile,
        settingsCandidates: settingsCandidates,
        t: t
    };
}
