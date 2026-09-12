import QtQuick
import qs.services
import qs.modules.common

StyledComboBox {
    id: root
    property string selectedLanguage: Config.options.language.ui ?? "auto"
    property bool includeAutomatic: true
    property var languageCodes: Translation.allAvailableLanguages
    signal languageSelected(string language)

    buttonIcon: "language"
    textRole: "displayName"
    valueRole: "value"
    model: {
        const codes = [...new Set(root.languageCodes.filter(code => code.length > 0))];
        if (root.selectedLanguage.length > 0 && root.selectedLanguage !== "auto" && !codes.includes(root.selectedLanguage))
            codes.push(root.selectedLanguage);
        return [...(root.includeAutomatic ? [{ displayName: Translation.tr("Auto (System)"), value: "auto" }] : []),
            ...codes.map(code => ({
                displayName: `${Qt.locale(code).nativeLanguageName || code} (${code})`,
                value: code
            })).sort((a, b) => a.displayName.localeCompare(b.displayName))];
    }
    currentIndex: Math.max(0, model.findIndex(item => item.value === root.selectedLanguage))
    onActivated: index => {
        const language = model[index]?.value;
        if (language !== undefined)
            root.languageSelected(language);
    }
}
