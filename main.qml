import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.qfield
import org.qgis
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
    property int maxChanges: 50000
    property bool loadingProjects: false
    property string projectLookupMessage: ""
    property string serverUrl: "https://app.qfield.cloud/api/v1/"
    property string projectId: ""
    property string projectLabel: ""
    property int pageSize: 200
    property var selectedDelta: null
    property var patchTargetLayer: null
    property var patchTargetFeature: null
    property var patchRows: []
    property var lastAppliedPatch: null
    property string patchMessage: ""
    property string patchMatchExplanation: ""
    property var movementOldPoint: null
    property var movementNewPoint: null
    property point movementOldScreen: Qt.point(0, 0)
    property point movementNewScreen: Qt.point(0, 0)
    property string movementInfo: ""
    property bool movementVisible: false

    function normalizedServerUrl(value) {
        var url = String(value || "").trim()
        if (!url)
            url = "https://app.qfield.cloud/api/v1/"
        if (url.charAt(url.length - 1) !== "/")
            url += "/"
        return url
    }

    function activeToken() {
        return sessionToken
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
        var fromText = fromDateField ? String(fromDateField.text || "").trim() : ""
        var toText = toDateField ? String(toDateField.text || "").trim() : ""

        for (var i = 0; i < allChanges.length; ++i) {
            var item = allChanges[i]
            var status = changeStatus(item)
            var day = String(item.created_at || "").slice(0, 10)
            if (fromText && day && day < fromText) continue
            if (toText && day && day > toText) continue
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

    function qgisLayerName(layer) {
        if (!layer) return ""
        try { return String(typeof layer.name === "function" ? layer.name() : layer.name) }
        catch (e) { return "" }
    }

    function sameValue(a, b) {
        if ((a === null || a === undefined) && (b === null || b === undefined)) return true
        if (a === null || a === undefined || b === null || b === undefined) return false
        if (typeof a === "object" || typeof b === "object") {
            try { return JSON.stringify(a) === JSON.stringify(b) } catch (e) {}
        }
        return String(a) === String(b)
    }

    function findLayerForDelta(item) {
        var c = changeContent(item)
        var names = [String(c.localLayerName || ""), String(c.sourceLayerName || "")]
        var matches = []
        try {
            var layers = ProjectUtils.mapLayers(qgisProject)
            for (var key in layers) {
                var n = qgisLayerName(layers[key])
                for (var i = 0; i < names.length; ++i)
                    if (names[i] && n === names[i]) { matches.push(layers[key]); break }
            }
        } catch (e) { patchMessage = qsTr("Lecture des couches impossible : %1").arg(String(e)) }
        return matches.length === 1 ? matches[0] : null
    }

    function candidateIdentifiers(item) {
        var c = changeContent(item)
        var oldA = c.old && c.old.attributes ? c.old.attributes : ({})
        var newA = c.new && c.new.attributes ? c.new.attributes : ({})
        var preferred = ["id_unique_inv", "uuid", "guid"]
        var out = []
        for (var i = 0; i < preferred.length; ++i) {
            var k = preferred[i]
            var v = newA[k] !== undefined ? newA[k] : oldA[k]
            if (v !== undefined && v !== null && String(v).length > 0)
                out.push({ "field": k, "value": v })
        }
        return out
    }

    function nonEmptyIdentity(value) {
        return value !== undefined && value !== null && String(value).length > 0
    }

    function sameLayerContent(a, b) {
        var an = String(a.localLayerName || a.sourceLayerName || a.localLayerId || "")
        var bn = String(b.localLayerName || b.sourceLayerName || b.localLayerId || "")
        return an.length > 0 && an === bn
    }

    function sameHistoricalEntity(targetContent, otherContent) {
        if (!sameLayerContent(targetContent, otherContent)) return false
        if (nonEmptyIdentity(targetContent.sourcePk) && nonEmptyIdentity(otherContent.sourcePk) &&
                sameValue(targetContent.sourcePk, otherContent.sourcePk)) return true
        if (nonEmptyIdentity(targetContent.localPk) && nonEmptyIdentity(otherContent.localPk) &&
                sameValue(targetContent.localPk, otherContent.localPk)) return true
        return false
    }

    function resolveIdentifiers(item) {
        var direct = candidateIdentifiers(item)
        if (direct.length > 0)
            return { "identifiers": direct, "source": qsTr("identifiant durable présent dans ce delta"),
                     "relatedCount": 0, "ambiguous": false }

        var target = changeContent(item)
        var unique = ({})
        var inferred = []
        var related = 0
        for (var i = 0; i < allChanges.length; ++i) {
            var other = allChanges[i]
            if (String(other.id || "") === String(item.id || "")) continue
            var oc = changeContent(other)
            if (!sameHistoricalEntity(target, oc)) continue
            related++
            var ids = candidateIdentifiers(other)
            for (var j = 0; j < ids.length; ++j) {
                var token = ids[j].field + "\u0000" + String(ids[j].value)
                if (!unique[token]) {
                    unique[token] = true
                    inferred.push(ids[j])
                }
            }
        }
        return {
            "identifiers": inferred.length === 1 ? inferred : [],
            "source": inferred.length === 1
                    ? qsTr("identifiant retrouvé dans %1 delta(s) lié(s)").arg(related)
                    : "",
            "relatedCount": related,
            "ambiguous": inferred.length > 1,
            "candidateCount": inferred.length
        }
    }

    function locateFeature(item, layer, resolution) {
        var resolved = resolution || resolveIdentifiers(item)
        var ids = resolved.identifiers || []
        var matches = []
        var matchKey = ""
        var originalSubset = ""
        var subsetChanged = false
        try {
            try {
                originalSubset = String(typeof layer.subsetString === "function"
                                        ? layer.subsetString() : layer.subsetString || "")
                if (originalSubset && typeof layer.setSubsetString === "function") {
                    layer.setSubsetString("")
                    subsetChanged = true
                }
            } catch (subsetReadError) {}
            var iterator = LayerUtils.createFeatureIterator(layer)
            while (iterator && iterator.hasNext()) {
                var f = iterator.next()
                var matched = false
                for (var i = 0; i < ids.length; ++i) {
                    var current
                    try { current = f.attribute(ids[i].field) } catch (e1) { current = undefined }
                    if (current !== undefined && sameValue(current, ids[i].value)) {
                        matched = true; matchKey = ids[i].field; break
                    }
                }
                if (!matched && ids.length === 0) {
                    var c = changeContent(item)
                    if (sameValue(f.id, c.localPk) || sameValue(f.id, c.sourcePk)) {
                        matched = true; matchKey = "__feature_id__"
                    }
                }
                if (matched) matches.push(f)
            }
        } catch (e2) { patchMessage = qsTr("Recherche de l’entité impossible : %1").arg(String(e2)) }
        finally {
            if (subsetChanged) {
                try { layer.setSubsetString(originalSubset); layer.triggerRepaint() }
                catch (subsetRestoreError) {}
            }
        }
        return matches.length === 1
                ? { "feature": matches[0], "key": matchKey, "matchCount": 1,
                    "resolution": resolved }
                : { "feature": null, "key": matchKey, "matchCount": matches.length,
                    "resolution": resolved }
    }

    function preparePatch(rawJson) {
        patchMessage = ""
        var item
        try { item = JSON.parse(rawJson) } catch (e) { patchMessage = qsTr("Delta illisible."); return }
        var c = changeContent(item)
        if (String(c.method || "").toLowerCase() !== "patch") {
            patchMessage = qsTr("La v0.3.0 applique uniquement les opérations PATCH.")
            patchErrorDialog.open(); return
        }
        var layer = findLayerForDelta(item)
        if (!layer) {
            patchMessage = qsTr("Couche introuvable ou correspondance ambiguë : %1").arg(layerName(item))
            patchErrorDialog.open(); return
        }
        var resolution = resolveIdentifiers(item)
        var located = locateFeature(item, layer, resolution)
        if (!located.feature) {
            if (resolution.ambiguous)
                patchMessage = qsTr("Plusieurs identifiants durables contradictoires ont été retrouvés dans l’historique (%1 candidats). Aucune écriture n’est autorisée.").arg(resolution.candidateCount)
            else if ((resolution.identifiers || []).length === 0)
                patchMessage = qsTr("Aucun id_unique_inv n’a été retrouvé dans ce delta ni dans ses %1 delta(s) lié(s). Le fid historique ne correspond pas de façon unique à la base actuelle.").arg(resolution.relatedCount)
            else
                patchMessage = qsTr("L’identifiant durable a été retrouvé, mais il correspond à %1 bâtiment(s) dans la base actuelle. Aucune écriture n’est autorisée.").arg(located.matchCount)
            patchErrorDialog.open(); return
        }
        var oldA = c.old && c.old.attributes ? c.old.attributes : ({})
        var newA = c.new && c.new.attributes ? c.new.attributes : ({})
        var rows = []
        for (var field in newA) {
            if (!(field in oldA) || !sameValue(oldA[field], newA[field])) {
                var current
                try { current = located.feature.attribute(field) } catch (e3) { current = undefined }
                var blocked = field === located.key || field === "fid" || current === undefined
                rows.push({ "field": field, "oldValue": oldA[field], "newValue": newA[field],
                            "currentValue": current, "blocked": blocked })
            }
        }
        if (rows.length === 0) {
            patchMessage = qsTr("Ce PATCH ne contient aucun attribut modifié exploitable.")
            patchErrorDialog.open(); return
        }
        var writableCount = 0
        for (var w = 0; w < rows.length; ++w)
            if (!rows[w].blocked) writableCount++
        if (writableCount === 0) {
            patchMessage = qsTr("Tous les champs modifiés sont protégés ou absents de l’entité locale.")
            patchErrorDialog.open(); return
        }
        selectedDelta = item
        patchTargetLayer = layer
        patchTargetFeature = located.feature
        patchRows = rows
        var matchedIdentifier = resolution.identifiers && resolution.identifiers.length > 0
                ? resolution.identifiers[0].field + " = " + readable(resolution.identifiers[0].value)
                : qsTr("fid historique = %1").arg(readable(c.sourcePk || c.localPk))
        patchMatchExplanation = matchedIdentifier + " — " +
                (resolution.source || qsTr("correspondance directe avec le fid local"))
        var lines = [qsTr("Couche : %1").arg(qgisLayerName(layer)),
                     qsTr("Entité : %1").arg(entityId(item)), ""]
        lines.push(qsTr("Correspondance : %1").arg(patchMatchExplanation))
        lines.push("")
        for (var r = 0; r < rows.length; ++r) {
            var x = rows[r]
            lines.push((x.blocked ? "🔒 " : "") + x.field)
            lines.push("  " + qsTr("ancienne : ") + readable(x.oldValue))
            lines.push("  " + qsTr("demandée : ") + readable(x.newValue))
            lines.push("  " + qsTr("actuelle : ") + readable(x.currentValue))
        }
        patchComparison.text = lines.join("\n")
        patchReviewDialog.open()
    }

    function writePatchValues(useOldValues, operation) {
        if (!patchTargetLayer || !patchTargetFeature) return false
        patchSaveModel.currentLayer = patchTargetLayer
        patchSaveModel.feature = patchTargetFeature
        var edited = patchSaveModel.feature
        for (var i = 0; i < patchRows.length; ++i) {
            var row = patchRows[i]
            if (row.blocked) continue
            if (useOldValues && !sameValue(edited.attribute(row.field), row.newValue)) {
                patchMessage = qsTr("Restauration bloquée : le champ « %1 » a changé depuis l’application.").arg(row.field)
                patchErrorDialog.open(); return false
            }
            var value = useOldValues ? row.oldValue : row.newValue
            if (!edited.setAttribute(row.field, value)) {
                patchMessage = qsTr("Écriture refusée pour le champ « %1 ».").arg(row.field)
                patchErrorDialog.open(); return false
            }
        }
        if (!patchSaveModel.updateAttributesFromFeature(edited) || !patchSaveModel.save(true)) {
            patchMessage = qsTr("QField n’a pas pu enregistrer la modification locale.")
            patchErrorDialog.open(); return false
        }
        patchTargetFeature = edited
        if (operation === "apply") {
            lastAppliedPatch = { "delta": selectedDelta, "layer": patchTargetLayer,
                                 "feature": edited, "rows": patchRows }
            patchMessage = qsTr("Modification appliquée localement. Synchronisez QField pour créer un nouveau delta.")
        } else {
            lastAppliedPatch = null
            patchMessage = qsTr("Valeurs antérieures restaurées localement.")
        }
        patchReviewDialog.close()
        patchResultDialog.open()
        return true
    }

    function restoreLastPatch() {
        if (!lastAppliedPatch) return
        selectedDelta = lastAppliedPatch.delta
        patchTargetLayer = lastAppliedPatch.layer
        patchRows = lastAppliedPatch.rows
        var fresh = locateFeature(selectedDelta, patchTargetLayer)
        if (!fresh.feature) {
            patchMessage = qsTr("Restauration impossible : l’entité n’est plus retrouvée de façon unique.")
            patchErrorDialog.open(); return
        }
        patchTargetFeature = fresh.feature
        restoreConfirmDialog.open()
    }

    function geometryText(item, side) {
        var c = changeContent(item)
        var part = side === "new" ? c.new : c.old
        return part && part.geometry ? String(part.geometry) : ""
    }

    function hasGeometryChange(item) {
        var oldWkt = geometryText(item, "old")
        var newWkt = geometryText(item, "new")
        return newWkt.length > 0 && newWkt !== oldWkt
    }

    function qgisStringLiteral(value) {
        return "'" + String(value || "").replace(/'/g, "''") + "'"
    }

    function mapPointForWkt(wkt, layer, feature) {
        if (!wkt || !layer || !feature) return null
        try {
            geometryEvaluator.layer = layer
            geometryEvaluator.feature = feature
            geometryEvaluator.expressionText = "geom_from_wkt(" + qgisStringLiteral(wkt) + ")"
            var geometry = geometryEvaluator.evaluate()
            if (!geometry) return null
            patchSaveModel.currentLayer = layer
            patchSaveModel.feature = feature
            var temporaryFeature = patchSaveModel.feature
            temporaryFeature.setGeometry(geometry)
            var canvas = iface.mapCanvas()
            return FeatureUtils.extent(canvas.mapSettings, layer, temporaryFeature).center
        } catch (e) {
            console.log("QFieldCloud Change Inspector geometry preview: " + e)
            return null
        }
    }

    function updateMovementScreen() {
        if (!movementVisible) return
        try {
            var settings = iface.mapCanvas().mapSettings
            movementOldScreen = settings.coordinateToScreen(movementOldPoint)
            movementNewScreen = settings.coordinateToScreen(movementNewPoint)
            movementLine.requestPaint()
        } catch (e) {}
    }

    function closeMovementPreview() {
        movementVisible = false
        movementOldPoint = null
        movementNewPoint = null
    }

    function openMovementPreview(rawJson) {
        var item
        try { item = JSON.parse(rawJson) } catch (e) { return }
        if (!hasGeometryChange(item)) {
            patchMessage = qsTr("Ce delta ne contient pas deux emplacements différents.")
            patchErrorDialog.open(); return
        }
        var layer = findLayerForDelta(item)
        if (!layer) {
            patchMessage = qsTr("La couche du déplacement est introuvable.")
            patchErrorDialog.open(); return
        }
        var located = locateFeature(item, layer)
        if (!located.feature) {
            patchMessage = qsTr("Le bâtiment servant à transformer les coordonnées est introuvable.")
            patchErrorDialog.open(); return
        }
        var oldPoint = mapPointForWkt(geometryText(item, "old"), layer, located.feature)
        var newPoint = mapPointForWkt(geometryText(item, "new"), layer, located.feature)
        if (!oldPoint || !newPoint) {
            patchMessage = qsTr("QField n’a pas pu convertir les géométries du delta vers la carte.")
            patchErrorDialog.open(); return
        }
        movementOldPoint = oldPoint
        movementNewPoint = newPoint
        var dx = Number(newPoint.x) - Number(oldPoint.x)
        var dy = Number(newPoint.y) - Number(oldPoint.y)
        movementInfo = qsTr("Distance cartographique : %1 unité(s)").arg(Math.sqrt(dx * dx + dy * dy).toFixed(2))
        movementVisible = true
        inspectorDialog.close()
        historyDialog.close()
        try { iface.mapCanvas().mapSettings.setExtentFromPoints([oldPoint, newPoint], 1000, true) }
        catch (zoomError) {}
        Qt.callLater(updateMovementScreen)
    }

    function identifierToken(identifier) {
        return identifier ? identifier.field + "\u0000" + String(identifier.value) : ""
    }

    function deltaHasIdentifier(item, token) {
        var ids = candidateIdentifiers(item)
        for (var i = 0; i < ids.length; ++i)
            if (identifierToken(ids[i]) === token) return true
        return false
    }

    function historySummary(item) {
        var c = changeContent(item)
        var method = String(c.method || "").toUpperCase()
        if (method === "PATCH") {
            var oldA = c.old && c.old.attributes ? c.old.attributes : ({})
            var newA = c.new && c.new.attributes ? c.new.attributes : ({})
            var parts = []
            for (var field in newA)
                if (!(field in oldA) || !sameValue(oldA[field], newA[field]))
                    parts.push(field + " : " + readable(oldA[field]) + " → " + readable(newA[field]))
            if (hasGeometryChange(item)) parts.push(qsTr("géométrie déplacée"))
            return parts.length ? parts.join("\n") : qsTr("PATCH sans différence lisible")
        }
        if (method === "CREATE") return qsTr("Création de l’enregistrement")
        if (method === "DELETE") return qsTr("Suppression de l’enregistrement")
        return method
    }

    function openEntityHistory(rawJson) {
        var target
        try { target = JSON.parse(rawJson) } catch (e) { return }
        var tc = changeContent(target)
        var resolution = resolveIdentifiers(target)
        var token = resolution.identifiers && resolution.identifiers.length === 1
                ? identifierToken(resolution.identifiers[0]) : ""
        var rows = []
        for (var i = 0; i < allChanges.length; ++i) {
            var other = allChanges[i]
            var related = token ? deltaHasIdentifier(other, token) : false
            if (!related) related = sameHistoricalEntity(tc, changeContent(other))
            if (related) rows.push(other)
        }
        rows.sort(function(a, b) { return String(a.created_at || "").localeCompare(String(b.created_at || "")) })
        historyModel.clear()
        for (var r = 0; r < rows.length; ++r) {
            var x = rows[r]
            var xs = changeStatus(x)
            historyModel.append({
                "dateText": String(x.created_at || ""), "userText": createdBy(x),
                "statusText": statusLabel(xs), "statusTint": statusColor(xs),
                "methodText": methodName(x), "summaryText": historySummary(x),
                "rawJson": JSON.stringify(x, null, 2),
                "canValidate": methodName(x) === "PATCH" && (xs === "STATUS_ERROR" || xs === "STATUS_CONFLICT" || xs === "STATUS_NOT_APPLIED"),
                "hasMovement": hasGeometryChange(x)
            })
        }
        historyTitle.text = qsTr("Historique — %1").arg(token ? token.split("\u0000")[1] : entityId(target))
        historyMessage.text = qsTr("%1 delta(s), du plus ancien au plus récent. Une erreur représente une tentative, pas nécessairement une modification présente dans la base.").arg(rows.length)
        historyDialog.open()
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

    function requestPage(baseUrl, offset, accumulated) {
        var url = baseUrl + "?limit=" + pageSize + "&offset=" + offset +
                  "&ordering=-created_at"
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

            if (rows.length === pageSize && accumulated.length < maxChanges) {
                requestPage(baseUrl, offset + rows.length, accumulated)
                return
            }

            allChanges = accumulated
            loading = false
            resetCounts()
            rebuildDisplay()
            message = accumulated.length >= maxChanges
                    ? qsTr("%1 changement(s) récupéré(s) — limite atteinte.").arg(totalCount)
                    : qsTr("%1 changement(s) récupéré(s).").arg(totalCount)
        }
        xhr.onerror = function() {
            loading = false
            message = qsTr("Connexion impossible au serveur QFieldCloud.")
        }
        xhr.send()
    }

    function normalizedProjectName(value) {
        return String(value || "")
                .toLowerCase()
                .replace(/[àáâäãå]/g, "a")
                .replace(/[ç]/g, "c")
                .replace(/[èéêë]/g, "e")
                .replace(/[ìíîï]/g, "i")
                .replace(/[ñ]/g, "n")
                .replace(/[òóôöõ]/g, "o")
                .replace(/[ùúûü]/g, "u")
                .replace(/[ýÿ]/g, "y")
                .replace(/\.(qgs|qgz)$/i, "")
                .replace(/[^a-z0-9]/g, "")
    }

    function currentProjectHints() {
        var hints = []
        try {
            var path = typeof qgisProject.fileName === "function"
                    ? qgisProject.fileName() : qgisProject.fileName
            path = String(path || "")
            if (path) {
                hints.push(path)
                var bits = path.replace(/\\/g, "/").split("/")
                if (bits.length > 0) hints.push(bits[bits.length - 1])
                if (bits.length > 1) hints.push(bits[bits.length - 2])
            }
        } catch (e1) {}
        try {
            var title = typeof qgisProject.title === "function"
                    ? qgisProject.title() : qgisProject.title
            if (title) hints.push(String(title))
        } catch (e2) {}
        return hints
    }

    function chooseProject(index, automatic) {
        if (index < 0 || index >= projectModel.count)
            return false
        projectCombo.currentIndex = index
        var chosen = projectModel.get(index)
        projectField.text = chosen.projectId
        plugin.projectId = chosen.projectId
        plugin.projectLabel = chosen.label
        if (automatic)
            projectLookupMessage = qsTr("Projet ouvert reconnu automatiquement : %1").arg(chosen.label)
        return true
    }

    function autoDetectCurrentProject() {
        if (projectModel.count === 0)
            return false
        if (projectModel.count === 1)
            return chooseProject(0, true)

        var hints = currentProjectHints()
        var bestIndex = -1
        var bestScore = 0
        var bestCount = 0
        for (var i = 0; i < projectModel.count; ++i) {
            var entry = projectModel.get(i)
            var score = 0
            for (var h = 0; h < hints.length; ++h) {
                var rawHint = String(hints[h] || "")
                if (rawHint.indexOf(entry.projectId) >= 0)
                    score = Math.max(score, 120)
                var hint = normalizedProjectName(rawHint)
                var cloudName = normalizedProjectName(entry.cloudName)
                if (hint && cloudName && hint === cloudName)
                    score = Math.max(score, 100)
                else if (hint.length >= 5 && cloudName.length >= 5 &&
                         (hint.indexOf(cloudName) >= 0 || cloudName.indexOf(hint) >= 0))
                    score = Math.max(score, 70)
            }
            if (score > bestScore) {
                bestScore = score
                bestIndex = i
                bestCount = 1
            } else if (score > 0 && score === bestScore) {
                bestCount++
            }
        }
        return bestScore >= 70 && bestCount === 1
                ? chooseProject(bestIndex, true) : false
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
                    "projectId": String(p.id || ""),
                    "cloudName": name
                })
            }

            if (!autoDetectCurrentProject()) {
                projectLookupMessage = rows.length > 0
                        ? qsTr("%1 projet(s) trouvé(s). Sélectionnez le bon projet.").arg(rows.length)
                        : qsTr("Aucun projet accessible avec ce jeton.")
            }
        }
        xhr.onerror = function() {
            loadingProjects = false
            projectLookupMessage = qsTr("Connexion impossible pendant la recherche des projets.")
        }
        xhr.send()
    }

    function refreshChanges() {
        var activeProjectId = String(plugin.projectId || "").trim()
        if (!activeProjectId || !activeToken()) {
            configDialog.open()
            message = qsTr("Renseignez l'identifiant du projet et le jeton.")
            return
        }

        loading = true
        message = qsTr("Chargement des changements…")
        loadedPages = 0
        allChanges = []
        changeModel.clear()
        var url = normalizedServerUrl(plugin.serverUrl) +
                  "deltas/" + encodeURIComponent(activeProjectId) + "/"
        requestPage(url, 0, [])
    }

    function saveConfiguration() {
        plugin.serverUrl = normalizedServerUrl(serverField.text)
        plugin.projectId = String(projectField.text || "").trim()
        sessionToken = String(tokenField.text || "").trim()
        configDialog.close()
        refreshChanges()
    }

    function openInspector() {
        inspectorDialog.open()
        if (allChanges.length === 0 && activeToken() && plugin.projectId)
            refreshChanges()
        else if (!activeToken() || !plugin.projectId)
            configDialog.open()
    }

    Component.onCompleted: {
        iface.addItemToPluginsToolbar(pluginButton)
        console.log("QFieldCloud Change Inspector v0.3.0 chargé")
    }

    ListModel { id: changeModel }
    ListModel { id: projectModel }
    ListModel { id: historyModel }

    FeatureModel {
        id: patchSaveModel
        project: qgisProject
        currentLayer: plugin.patchTargetLayer
        modelMode: FeatureModel.SingleFeatureModel
    }

    ExpressionEvaluator {
        id: geometryEvaluator
        project: qgisProject
        mapSettings: iface.mapCanvas().mapSettings
        mode: ExpressionEvaluator.ExpressionMode
    }

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
        title: qsTr("Deltas QFieldCloud — validation contrôlée")
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
                Label { visible: plugin.projectLabel.length > 0; text: plugin.projectLabel; font.bold: true }
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

            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Du") }
                TextField { id: fromDateField; placeholderText: "AAAA-MM-JJ"; onTextChanged: dateTimer.restart() }
                Label { text: qsTr("au") }
                TextField { id: toDateField; placeholderText: "AAAA-MM-JJ"; onTextChanged: dateTimer.restart() }
                Button { text: qsTr("Effacer les dates"); onClicked: { fromDateField.text = ""; toDateField.text = "" } }
                Item { Layout.fillWidth: true }
                Button { text: qsTr("Restaurer la dernière application"); enabled: plugin.lastAppliedPatch !== null; onClicked: plugin.restoreLastPatch() }
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
                            Button {
                                text: qsTr("Valider…")
                                visible: methodText === "PATCH" && (statusCode === "STATUS_ERROR" || statusCode === "STATUS_CONFLICT" || statusCode === "STATUS_NOT_APPLIED")
                                onClicked: plugin.preparePatch(rawJson)
                            }
                            Button { text: qsTr("Historique"); onClicked: plugin.openEntityHistory(rawJson) }
                            Button {
                                text: qsTr("Voir déplacement")
                                visible: plugin.hasGeometryChange(JSON.parse(rawJson))
                                onClicked: plugin.openMovementPreview(rawJson)
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
            TextField { id: serverField; Layout.fillWidth: true; text: plugin.serverUrl }
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
            }
            Label { text: qsTr("Identifiant UUID du projet QFieldCloud"); font.bold: true }
            RowLayout {
                Layout.fillWidth: true
                TextField { id: projectField; Layout.fillWidth: true; text: plugin.projectId; placeholderText: qsTr("Rempli automatiquement après sélection") }
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
                        plugin.chooseProject(currentIndex, false)
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
                text: qsTr("Le jeton sert uniquement à lire QFieldCloud et reste en mémoire jusqu'à la fermeture de QField. Les changements validés sont écrits dans le projet local, puis envoyés comme nouveaux deltas lors de la synchronisation.")
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
        id: historyDialog
        parent: mainWindow.contentItem
        modal: true
        title: historyTitle.text
        standardButtons: Dialog.Close
        width: Math.min(parent.width * 0.94, 1200)
        height: Math.min(parent.height * 0.9, 820)
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        contentItem: ColumnLayout {
            Label { id: historyTitle; visible: false }
            Label { id: historyMessage; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: historyModel
                delegate: Rectangle {
                    width: ListView.view.width
                    height: historyRow.implicitHeight + 16
                    radius: 5
                    color: index % 2 ? "#ffffff" : "#f5f5f5"
                    border.color: statusTint
                    border.width: 2
                    ColumnLayout {
                        id: historyRow
                        anchors.fill: parent
                        anchors.margins: 8
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: dateText; font.bold: true }
                            Label { text: userText || "—" }
                            Label { text: methodText; font.bold: true }
                            Label { text: statusText; color: statusTint; font.bold: true }
                            Item { Layout.fillWidth: true }
                            Button { text: qsTr("Détails"); onClicked: { detailTitle.text = statusText; detailText.text = rawJson; detailDialog.open() } }
                            Button { text: qsTr("Voir déplacement"); visible: hasMovement; onClicked: plugin.openMovementPreview(rawJson) }
                            Button { text: qsTr("Valider…"); visible: canValidate; onClicked: plugin.preparePatch(rawJson) }
                        }
                        Label { Layout.fillWidth: true; text: summaryText; wrapMode: Text.WordWrap }
                    }
                }
            }
        }
    }

    Dialog {
        id: patchReviewDialog
        parent: mainWindow.contentItem
        modal: true
        title: qsTr("Vérifier le PATCH avant application")
        standardButtons: Dialog.NoButton
        width: Math.min(parent.width * 0.9, 900)
        height: Math.min(parent.height * 0.85, 720)
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        contentItem: ColumnLayout {
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: qsTr("Les champs marqués 🔒 sont des identifiants ou sont absents de l’entité locale; ils ne seront pas écrits.") }
            ScrollView { Layout.fillWidth: true; Layout.fillHeight: true
                TextArea { id: patchComparison; readOnly: true; wrapMode: TextEdit.Wrap; font.family: "monospace"; selectByMouse: true }
            }
            CheckBox { id: validationCheck; text: qsTr("J’ai vérifié les valeurs demandées et j’autorise cette modification locale.") }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true }
                Button { text: qsTr("Annuler"); onClicked: { validationCheck.checked = false; patchReviewDialog.close() } }
                Button { text: qsTr("Appliquer"); font.bold: true; enabled: validationCheck.checked; onClicked: { validationCheck.checked = false; applyConfirmDialog.open() } }
            }
        }
    }

    Dialog {
        id: applyConfirmDialog
        parent: mainWindow.contentItem
        modal: true
        title: qsTr("Confirmation finale")
        standardButtons: Dialog.NoButton
        contentItem: ColumnLayout {
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: qsTr("Appliquer maintenant ce PATCH à l’entité locale ? Cette action sera synchronisée comme un nouveau delta.") }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true }
                Button { text: qsTr("Non"); onClicked: applyConfirmDialog.close() }
                Button { text: qsTr("Oui, appliquer"); font.bold: true; onClicked: { applyConfirmDialog.close(); plugin.writePatchValues(false, "apply") } }
            }
        }
    }

    Dialog {
        id: restoreConfirmDialog
        parent: mainWindow.contentItem
        modal: true
        title: qsTr("Restaurer les valeurs antérieures")
        standardButtons: Dialog.NoButton
        contentItem: ColumnLayout {
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: qsTr("La restauration sera refusée si une valeur actuelle ne correspond plus à la valeur appliquée.") }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true }
                Button { text: qsTr("Annuler"); onClicked: restoreConfirmDialog.close() }
                Button { text: qsTr("Restaurer"); font.bold: true; onClicked: { restoreConfirmDialog.close(); plugin.writePatchValues(true, "restore") } }
            }
        }
    }

    Dialog {
        id: patchResultDialog
        parent: mainWindow.contentItem
        modal: true
        title: qsTr("Modification locale")
        standardButtons: Dialog.Close
        contentItem: Label { width: 520; wrapMode: Text.WordWrap; text: plugin.patchMessage }
    }

    Dialog {
        id: patchErrorDialog
        parent: mainWindow.contentItem
        modal: true
        title: qsTr("Modification impossible")
        standardButtons: Dialog.Close
        contentItem: Label { width: 520; wrapMode: Text.WordWrap; text: plugin.patchMessage }
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
    Timer { id: dateTimer; interval: 250; repeat: false; onTriggered: plugin.rebuildDisplay() }
    Timer { id: movementTimer; interval: 100; repeat: true; running: plugin.movementVisible; onTriggered: plugin.updateMovementScreen() }

    Item {
        id: movementOverlay
        parent: iface.mapCanvas()
        anchors.fill: parent
        z: 999999
        visible: plugin.movementVisible
        Canvas {
            id: movementLine
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = "#ffb300"
                ctx.lineWidth = 5
                ctx.beginPath()
                ctx.moveTo(plugin.movementOldScreen.x, plugin.movementOldScreen.y)
                ctx.lineTo(plugin.movementNewScreen.x, plugin.movementNewScreen.y)
                ctx.stroke()
            }
        }
        Rectangle {
            width: 30; height: 30; radius: 15
            color: "#d32f2f"; border.color: "white"; border.width: 4
            x: plugin.movementOldScreen.x - width / 2
            y: plugin.movementOldScreen.y - height / 2
            Label { anchors.centerIn: parent; text: "A"; color: "white"; font.bold: true }
        }
        Rectangle {
            width: 30; height: 30; radius: 15
            color: "#2e7d32"; border.color: "white"; border.width: 4
            x: plugin.movementNewScreen.x - width / 2
            y: plugin.movementNewScreen.y - height / 2
            Label { anchors.centerIn: parent; text: "N"; color: "white"; font.bold: true }
        }
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 16
            width: movementPanel.implicitWidth + 24
            height: movementPanel.implicitHeight + 16
            radius: 8
            color: "#eeffffff"
            border.color: "#666666"
            RowLayout {
                id: movementPanel
                anchors.centerIn: parent
                Rectangle { width: 14; height: 14; radius: 7; color: "#d32f2f" }
                Label { text: qsTr("Ancien") }
                Rectangle { width: 14; height: 14; radius: 7; color: "#2e7d32" }
                Label { text: qsTr("Nouveau") }
                Label { text: plugin.movementInfo; font.bold: true }
                Button {
                    text: qsTr("Fermer l’aperçu")
                    onClicked: { plugin.closeMovementPreview(); inspectorDialog.open() }
                }
            }
        }
    }
}
