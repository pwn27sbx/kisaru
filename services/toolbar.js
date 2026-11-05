// The folder toolbar's pure rules: the switch says the state and the
// three-dot menu owns rename and delete. The QML maps the keys through I18n,
// so labels and action order live here instead of in three views.
function hideKey(checked) {
    return checked === true ? "folder.hiddenMark" : "folder.hide";
}

function menuActions() {
    return [
        { value: "rename", key: "folder.renameShort", danger: false },
        { value: "delete", key: "folder.deleteShort", danger: true }
    ];
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        hideKey: hideKey,
        menuActions: menuActions
    };
}
