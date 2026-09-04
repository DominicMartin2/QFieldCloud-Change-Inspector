import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.settings

import org.qfield
import Theme

Item {
    id: plugin
    objectName: "qfieldCloudChangeInspector"

    property var mainWindow: iface.mainWindow()
    property string sessionToken: ""
    property var allChanges: []
    property bool loading: false
    property string message: ""
    property int totalCount: 0
    property int errorCount: 0
    property int conflictCount: 0
    property int notAppliedCount: 0
    property int appliedCount: 0
    property int loadedPages: 0
    property int maxChanges: 5000
    property bool loadingProjects: false
    property string projectLookupMessage: ""

    Settings {
        id: localSettings
        category: "QFieldCloudChangeInspector"
        property string serverUrl: "https://app.qfield.cloud/api/v1/"
        property string projectId: ""
        property string savedToken: ""
        property bool rememberToken: false
    }

    function normalizedServerUrl(value) {
        var url = String(value || "").trim()
        if (!url)
            url = "https://app.qfield.cloud/api/v1/"
        if (url.charAt(url.length - 1) !== "/")
            url += "/"
        return url
    }

    function activeToken() {
        if (sessionToken.length > 0)
            return sessionToken
        return localSettings.rememberToken ? localSettings.savedToken : ""
    }

    function readable(value) {
        if (value === null || value === undefined)
            return ""
        if (typeof value === "string")
            return value
        try { return JSON.stringify(value) } catch (e) { return String(value) }
    }

    function asObject(value) {
        if (value === null || value === undefined)
            return ({})
        if (typeof value === "object")
            return value
        try { return JSON.parse(String(value)) } catch (e) { return ({ "msg": String(value) }) }
    }

    function changeStatus(item) {
        return String(item && item.status ? item.status : "STATUS_INCONNU")
    }

    function changeContent(item) {
        return asObject(item ? item.content : null)
    }

    function feedbackObject(item) {
        var value = item ? item.last_feedback : null
        if (value === null || value === undefined || value === "")
            value = item ? item.output : null
        return asObject(value)
    }

    function feedbackText(item) {
        var f = feedbackObject(item)
        var parts = []
        if (f.msg) parts.push(readable(f.msg))
        if (f.provider_errors) parts.push("Erreurs fournisseur : " + readable(f.provider_errors))
        if (f.conflicts) parts.push("Conflits : " + readable(f.conflicts))
        if (f.status) parts.push("Retour : " + readable(f.status))
        if (parts.length === 0 && Object.keys(f).length > 0)
            parts.push(readable(f))
        return parts.join("\n")
    }

    function layerName(item) {
        var c = changeContent(item)
        return String(c.localLayerName || c.sourceLayerName || c.localLayerId || "Couche inconnue")
    }

    function methodName(item) {
        var c = changeContent(item)
        return String(c.method || "").toUpperCase()
    }

    function entityId(item) {
        var c = changeContent(item)
        var attrs = c.new && c.new.attributes ? c.new.attributes : ({})
        return String(attrs.id_unique_inv || c.sourcePk || c.localPk || "")
    }

    function createdBy(item) {
        if (!item) return ""
        if (typeof item.created_by === "object")
            return String(item.created_by.username || item.created_by.name || readable(item.created_by))
        return String(item.created_by || "")
    }

    function statusColor(status) {
        if (status === "STATUS_ERROR" || status === "STATUS_UNPERMITTED") return "#b71c1c"
        if (status === "STATUS_CONFLICT") return "#ef6c00"
        if (status === "STATUS_NOT_APPLIED") return "#6a1b9a"
        if (status === "STATUS_APPLIED") return "#2e7d32"
        if (status === "STATUS_PENDING" || status === "STATUS_BUSY") return "#1565c0"
        return "#616161"
    }

    function statusLabel(status) {
        if (status === "STATUS_ERROR") return qsTr("Erreur")
        if (status === "STATUS_CONFLICT") return qsTr("Conflit")
        if (status === "STATUS_NOT_APPLIED") return qsTr("Non appliqué")
        if (status === "STATUS_APPLIED") return qsTr("Appliqué")
        if (status === "STATUS_PENDING") return qsTr("En attente")
        if (status === "STATUS_BUSY") return qsTr("Traitement")
        if (status === "STATUS_IGNORED") return qsTr("Ignoré")
        if (status === "STATUS_UNPERMITTED") return qsTr("Non autorisé")
        return status
    }

    function resetCounts() {
        totalCount = allChanges.length
        errorCount = 0
        conflictCount = 0
        notAppliedCount = 0
        appliedCount = 0
        for (var i = 0; i < allChanges.length; ++i) {
            var s = changeStatus(allChanges[i])
            if (s === "STATUS_ERROR" || s === "STATUS_UNPERMITTED") errorCount++
            else if (s === "STATUS_CONFLICT") conflictCount++
            else if (s === "STATUS_NOT_APPLIED") notAppliedCount++
            else if (s === "STATUS_APPLIED") appliedCount++
        }
    }

    function selectedStatusCode() {
        var i = statusCombo.currentIndex
        if (i === 1) return "STATUS_ERROR"
        if (i === 2) return "STATUS_CONFLICT"
        if (i === 3) return "STATUS_NOT_APPLIED"
        if (i === 4) return "STATUS_APPLIED"
        if (i === 5) return "STATUS_PENDING"
        if (i === 6) return "STATUS_IGNORED"
        return ""
    }

    function rebuildDisplay() {
        changeModel.clear()
        var wantedStatus = selectedStatusCode()
        var needle = searchField ? String(searchField.text || "").toLowerCase().trim() : ""

        for (var i = 0; i < allChanges.length; ++i) {
            var item = allChanges[i]
            var status = changeStatus(item)
            if (wantedStatus && status !== wantedStatus &&
                    !(wantedStatus === "STATUS_ERROR" && status === "STATUS_UNPERMITTED"))
                continue

            var searchable = [status, layerName(item), methodName(item), entityId(item),
                              createdBy(item), item.created_at || "", item.deltafile_id || "",
                              feedbackText(item), readable(item.content)].join(" ").toLowerCase()
            if (needle && searchable.indexOf(needle) < 0)
                continue

            changeModel.append({
                "statusCode": status,
                "statusText": statusLabel(status),
                "statusTint": statusColor(status),
                "layerText": layerName(item),
                "methodText": methodName(item),
                "entityText": entityId(item),
                "userText": createdBy(item),
                "dateText": String(item.created_at || ""),
                "feedback": feedbackText(item),
                "deltaId": String(item.id || ""),
                "deltafileId": String(item.deltafile_id || ""),
                "rawJson": JSON.stringify(item, null, 2)
            })
        }
    }

    function extractResults(payload) {
        if (Array.isArray(payload))
            return payload
        if (payload && Array.isArray(payload.results))
            return payload.results
        return []
    }

    function nextUrl(payload) {
        if (payload && payload.next)
            return String(payload.next)
        return ""
    }

    function requestPage(url, accumulated) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.setRequestHeader("Authorization", "Token " + activeToken())
        xhr.setRequestHeader("Accept", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            if (xhr.status < 200 || xhr.status >= 300) {
                loading = false
                message = qsTr("Erreur HTTP %1 : %2").arg(xhr.status).arg(String(xhr.responseText || ""))
                return
            }

            var payload = null
            try { payload = JSON.parse(xhr.responseText) }
            catch (e) {
                loading = false
                message = qsTr("Réponse JSON illisible : %1").arg(String(e))
                return
            }

            var rows = extractResults(payload)
            for (var i = 0; i < rows.length && accumulated.length < maxChanges; ++i)
                accumulated.push(rows[i])
            loadedPages++

            var next = nextUrl(payload)
            if (next && accumulated.length < maxChanges) {
                requestPage(next, accumulated)
                return
            }

            allChanges = accumulated
            loading = false
            resetCounts()
            rebuildDisplay()
            message = qsTr("%1 changement(s) récupéré(s).").arg(totalCount)
        }
        xhr.onerror = function() {
            loading = false
            message = qsTr("Connexion impossible au serveur QFieldCloud.")
        }
        xhr.send()
    }

    function fetchProjects() {
        var token = String(tokenField.text || "").trim()
        if (!token) {
            projectLookupMessage = qsTr("Collez d'abord votre jeton API.")
            return
        }

        loadingProjects = true
        projectLookupMessage = qsTr("Recherche des projets…")
        projectModel.clear()

        var url = normalizedServerUrl(serverField.text) +
                  "projects/?limit=200&offset=0&ordering=name"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.setRequestHeader("Accept", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            loadingProjects = false
            if (xhr.status < 200 || xhr.status >= 300) {
                projectLookupMessage = qsTr("Erreur HTTP %1 pendant la recherche des projets.").arg(xhr.status)
                return
            }

            var payload = null
            try { payload = JSON.parse(xhr.responseText) }
            catch (e) {
                projectLookupMessage = qsTr("Réponse des projets illisible : %1").arg(String(e))
                return
            }

            var rows = extractResults(payload)
            for (var i = 0; i < rows.length; ++i) {
                var p = rows[i]
                var owner = ""
                if (typeof p.owner === "object" && p.owner)
                    owner = String(p.owner.username || p.owner.name || "")
                else
                    owner = String(p.owner || "")
                var name = String(p.name || p.title || p.id || "Projet")
                projectModel.append({
                    "label": owner ? owner + " / " + name : name,
                    "projectId": String(p.id || "")
                })
            }

            projectLookupMessage = rows.length > 0
                    ? qsTr("%1 projet(s) trouvé(s).").arg(rows.length)
                    : qsTr("Aucun projet accessible avec ce jeton.")
            if (projectModel.count > 0) {
                projectCombo.currentIndex = 0
                projectField.text = projectModel.get(0).projectId
            }
        }
        xhr.onerror = function() {
            loadingProjects = false
            projectLookupMessage = qsTr("Connexion impossible pendant la recherche des projets.")
        }
        xhr.send()
    }

    function refreshChanges() {
        var projectId = String(localSettings.projectId || "").trim()
        if (!projectId || !activeToken()) {
            configDialog.open()
            message = qsTr("Renseignez l'identifiant du projet et le jeton.")
            return
        }

        loading = true
        message = qsTr("Chargement des changements…")
        loadedPages = 0
        allChanges = []
        changeModel.clear()
        var url = normalizedServerUrl(localSettings.serverUrl) +
                  "deltas/" + encodeURIComponent(projectId) +
                  "/?limit=200&offset=0&ordering=-created_at"
        requestPage(url, [])
    }

    function saveConfiguration() {
        localSettings.serverUrl = normalizedServerUrl(serverField.text)
        localSettings.projectId = String(projectField.text || "").trim()
        sessionToken = String(tokenField.text || "").trim()
        localSettings.rememberToken = rememberCheck.checked
        localSettings.savedToken = rememberCheck.checked ? sessionToken : ""
        configDialog.close()
        refreshChanges()
    }

    function openInspector() {
        inspectorDialog.open()
        if (allChanges.length === 0 && activeToken() && localSettings.projectId)
            refreshChanges()
        else if (!activeToken() || !localSettings.projectId)
            configDialog.open()
    }

    Component.onCompleted: {
        if (localSettings.rememberToken)
            sessionToken = localSettings.savedToken
        iface.addItemToPluginsToolbar(pluginButton)
        console.log("QFieldCloud Change Inspector v0.1.1 chargé")
    }

    ListModel { id: changeModel }
    ListModel { id: projectModel }

    QfToolButton {
        id: pluginButton
        iconSource: "icon.svg"
        iconColor: Theme.mainColor
        bgcolor: Theme.darkGray
        round: true
        onClicked: plugin.openInspector()
    }

    QfDialog {
        id: inspectorDialog
        parent: mainWindow.contentItem
        modal: true
        title: qsTr("Deltas QFieldCloud — lecture seule")
        standardButtons: Dialog.Close
        width: parent ? Math.max(900, parent.width * 0.94) : 1300
        height: parent ? Math.max(650, parent.height * 0.92) : 850
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0

        contentItem: ColumnLayout {
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Button { text: qsTr("Configuration"); onClicked: configDialog.open() }
                Button {
                    text: plugin.loading ? qsTr("Chargement…") : qsTr("Actualiser")
                    enabled: !plugin.loading
                    onClicked: plugin.refreshChanges()
                }
                BusyIndicator { running: plugin.loading; visible: running; implicitWidth: 34; implicitHeight: 34 }
                Label { Layout.fillWidth: true; text: plugin.message; elide: Text.ElideRight }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Total : %1").arg(plugin.totalCount); font.bold: true }
                Label { text: qsTr("Erreurs : %1").arg(plugin.errorCount); color: "#b71c1c"; font.bold: true }
                Label { text: qsTr("Conflits : %1").arg(plugin.conflictCount); color: "#ef6c00"; font.bold: true }
                Label { text: qsTr("Non appliqués : %1").arg(plugin.notAppliedCount); color: "#6a1b9a" }
                Label { text: qsTr("Appliqués : %1").arg(plugin.appliedCount); color: "#2e7d32" }
                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                ComboBox {
                    id: statusCombo
                    model: [qsTr("Tous les statuts"), qsTr("Erreurs"), qsTr("Conflits"),
                            qsTr("Non appliqués"), qsTr("Appliqués"), qsTr("En attente"), qsTr("Ignorés")]
                    onCurrentIndexChanged: plugin.rebuildDisplay()
                }
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Rechercher : bâtiment, couche, utilisateur, deltafile…")
                    onTextChanged: searchTimer.restart()
                }
                Label { text: qsTr("%1 affiché(s)").arg(changeModel.count) }
            }

            ListView {
                id: changesList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: changeModel

                delegate: Rectangle {
                    width: changesList.width
                    height: cardLayout.implicitHeight + 18
                    radius: 6
                    color: index % 2 === 0 ? "#f5f5f5" : "#ffffff"
                    border.color: statusTint
                    border.width: 2

                    ColumnLayout {
                        id: cardLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 9
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                width: statusLabelItem.implicitWidth + 16
                                height: statusLabelItem.implicitHeight + 8
                                radius: 4
                                color: statusTint
                                Label { id: statusLabelItem; anchors.centerIn: parent; text: statusText; color: "white"; font.bold: true }
                            }
                            Label { text: methodText; font.bold: true }
                            Label { text: layerText; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                            Label { text: dateText }
                            Button {
                                text: qsTr("Détails")
                                onClicked: {
                                    detailTitle.text = statusText + " — " + (entityText || deltaId)
                                    detailText.text = rawJson
                                    detailDialog.open()
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Entité : %1     Utilisateur : %2     Deltafile : %3")
                                  .arg(entityText || "—").arg(userText || "—").arg(deltafileId || "—")
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: feedback.length > 0
                            text: feedback
                            color: statusTint
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: configDialog
        parent: mainWindow.contentItem
        modal: true
        title: qsTr("Connexion à QFieldCloud")
        standardButtons: Dialog.NoButton
        width: Math.min(parent.width * 0.85, 760)
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        contentItem: ColumnLayout {
            spacing: 10
            Label { text: qsTr("Serveur API"); font.bold: true }
            TextField { id: serverField; Layout.fillWidth: true; text: localSettings.serverUrl }
            Label { text: qsTr("Jeton API"); font.bold: true }
            TextField {
                id: tokenField
                Layout.fillWidth: true
                text: plugin.sessionToken
                echoMode: showTokenCheck.checked ? TextInput.Normal : TextInput.Password
                placeholderText: qsTr("Coller le jeton ici")
            }
            RowLayout {
                CheckBox { id: showTokenCheck; text: qsTr("Afficher le jeton") }
                CheckBox { id: rememberCheck; text: qsTr("Mémoriser sur cet appareil"); checked: localSettings.rememberToken }
            }
            Label { text: qsTr("Identifiant UUID du projet QFieldCloud"); font.bold: true }
            RowLayout {
                Layout.fillWidth: true
                TextField { id: projectField; Layout.fillWidth: true; text: localSettings.projectId; placeholderText: qsTr("Rempli automatiquement après sélection") }
                Button {
                    text: plugin.loadingProjects ? qsTr("Recherche…") : qsTr("Trouver mes projets")
                    enabled: !plugin.loadingProjects
                    onClicked: plugin.fetchProjects()
                }
            }
            ComboBox {
                id: projectCombo
                Layout.fillWidth: true
                visible: projectModel.count > 0
                model: projectModel
                textRole: "label"
                onActivated: {
                    if (currentIndex >= 0 && currentIndex < projectModel.count)
                        projectField.text = projectModel.get(currentIndex).projectId
                }
            }
            Label {
                Layout.fillWidth: true
                visible: plugin.projectLookupMessage.length > 0
                text: plugin.projectLookupMessage
                wrapMode: Text.WordWrap
                opacity: 0.75
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.72
                text: qsTr("Le jeton est utilisé uniquement pour des requêtes GET. S'il est mémorisé, il reste dans les paramètres locaux de QField et n'est pas ajouté au projet synchronisé.")
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: qsTr("Annuler"); onClicked: configDialog.close() }
                Button { text: qsTr("Enregistrer et actualiser"); font.bold: true; onClicked: plugin.saveConfiguration() }
            }
        }
    }

    Dialog {
        id: detailDialog
        parent: mainWindow.contentItem
        modal: true
        title: detailTitle.text
        standardButtons: Dialog.Close
        width: Math.min(parent.width * 0.9, 1000)
        height: Math.min(parent.height * 0.85, 760)
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        contentItem: ColumnLayout {
            Label { id: detailTitle; visible: false }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                TextArea {
                    id: detailText
                    readOnly: true
                    wrapMode: TextEdit.NoWrap
                    font.family: "monospace"
                    selectByMouse: true
                }
            }
        }
    }

    Timer {
        id: searchTimer
        interval: 250
        repeat: false
        onTriggered: plugin.rebuildDisplay()
    }
}
