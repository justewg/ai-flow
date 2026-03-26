package com.planka.quicktest

import android.content.Context
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File

data class ResolvedUiShellConfig(
    val payload: String,
    val diagnosticsPayload: String,
)

object UiShellConfigResolver {
    const val ACTIVE_CONFIG_FILE_NAME = "ui-shell-config.active.json"

    private const val DEFAULT_ASSET_NAME = "ui-shell-config.default.json"
    private const val CONTRACT_NAME = "planka.ui-shell"
    private const val CONTRACT_VERSION = 1
    private val shellVersion: Int
        get() = BuildConfig.VERSION_CODE

    private val allowedRootKeys = setOf(
        "compatibility",
        "configVersion",
        "contractName",
        "contractVersion",
        "keyboard",
        "labels",
        "layout",
        "shell",
    )
    private val allowedCompatibilityKeys = setOf("maxShellVersion", "minShellVersion")
    private val allowedLayoutKeys = setOf(
        "appPaddingPx",
        "keyGapPx",
        "keyboardRatio",
        "keyboardRowGapPx",
        "keySizeMultiplier",
        "sectionGapPx",
        "textRatio",
        "textSizeMultiplier",
    )
    private val allowedKeyboardKeys = setOf("defaultLocale", "locales")
    private val allowedLocaleKeys = setOf("displayName", "rows")
    private val allowedRowKeys = setOf("id", "keys", "template")
    private val allowedTemplateKeys = setOf("columns")
    private val allowedShellKeys = setOf("featureFlags", "serviceButtonOrder")
    private val allowedFeatureFlagKeys = setOf("showClearButton", "showExitButton", "showLocaleButton")
    private val allowedLabelsKeys = setOf("placeholder", "serviceButtons", "specialKeys")
    private val allowedServiceButtonsKeys = setOf("clear", "exit", "locale")
    private val allowedStaticServiceLabelKeys = setOf("label", "titles")
    private val allowedDynamicServiceLabelKeys = setOf("titles")
    private val allowedSpecialKeys = setOf("backspace", "enter", "space")
    private val allowedInputKeyKeys = setOf("kind", "value")
    private val allowedSpecialKeyKeys = setOf("kind")
    private val supportedServiceButtonIds = setOf("clear", "exit", "locale")

    fun resolve(context: Context): ResolvedUiShellConfig {
        val defaults = loadBundledDefaults(context)
        val activeConfigPath = File(context.filesDir, ACTIVE_CONFIG_FILE_NAME)

        if (!activeConfigPath.isFile) {
            return buildResolvedConfig(
                validated = defaults,
                requestedSource = "built_in_defaults",
                resolvedSource = "built_in_defaults",
                fallbackReason = null,
                activeConfigPath = activeConfigPath,
            )
        }

        val activePayload = try {
            activeConfigPath.readText(Charsets.UTF_8)
        } catch (error: Exception) {
            return buildResolvedConfig(
                validated = defaults,
                requestedSource = "active_file",
                resolvedSource = "built_in_defaults",
                fallbackReason = "Не удалось прочитать active config: ${error.message ?: "unknown"}",
                activeConfigPath = activeConfigPath,
            )
        }

        val activeConfig = try {
            validateConfig(activePayload)
        } catch (error: IllegalArgumentException) {
            return buildResolvedConfig(
                validated = defaults,
                requestedSource = "active_file",
                resolvedSource = "built_in_defaults",
                fallbackReason = error.message ?: "Active config validation failed",
                activeConfigPath = activeConfigPath,
            )
        }

        return buildResolvedConfig(
            validated = activeConfig,
            requestedSource = "active_file",
            resolvedSource = "active_file",
            fallbackReason = null,
            activeConfigPath = activeConfigPath,
        )
    }

    internal fun validatePayload(payload: String): String = validateConfig(payload).payload

    private fun loadBundledDefaults(context: Context): ValidatedConfig {
        val payload = try {
            context.assets.open(DEFAULT_ASSET_NAME).bufferedReader(Charsets.UTF_8).use { it.readText() }
        } catch (_: Exception) {
            EMERGENCY_DEFAULT_CONFIG_JSON
        }

        return try {
            validateConfig(payload)
        } catch (_: IllegalArgumentException) {
            validateConfig(EMERGENCY_DEFAULT_CONFIG_JSON)
        }
    }

    private fun buildResolvedConfig(
        validated: ValidatedConfig,
        requestedSource: String,
        resolvedSource: String,
        fallbackReason: String?,
        activeConfigPath: File,
    ): ResolvedUiShellConfig {
        val diagnostics = JSONObject()
            .put("activeConfigPath", activeConfigPath.absolutePath)
            .put("configVersion", validated.configVersion)
            .put("contractVersion", CONTRACT_VERSION)
            .put("fallbackReason", fallbackReason ?: JSONObject.NULL)
            .put("requestedSource", requestedSource)
            .put("resolvedSource", resolvedSource)
            .put("shellVersion", shellVersion)
            .toString()

        return ResolvedUiShellConfig(
            payload = validated.payload,
            diagnosticsPayload = diagnostics,
        )
    }

    private fun validateConfig(payload: String): ValidatedConfig {
        val root = try {
            JSONObject(payload)
        } catch (error: JSONException) {
            throw IllegalArgumentException("Config не является валидным JSON: ${error.message}")
        }

        requireExactKeys(root, allowedRootKeys, "root")
        requireString(root, "contractName", "root", exactValue = CONTRACT_NAME)
        requireInt(root, "contractVersion", "root", min = CONTRACT_VERSION, max = CONTRACT_VERSION)
        val configVersion = requireInt(root, "configVersion", "root", min = 1)

        val compatibility = requireObject(root, "compatibility", "root")
        requireExactKeys(compatibility, allowedCompatibilityKeys, "compatibility")
        val minShellVersion = requireInt(compatibility, "minShellVersion", "compatibility", min = 1)
        val maxShellVersion = requireInt(compatibility, "maxShellVersion", "compatibility", min = minShellVersion)
        if (shellVersion !in minShellVersion..maxShellVersion) {
            throw IllegalArgumentException(
                "Shell version $shellVersion несовместима с config-диапазоном $minShellVersion..$maxShellVersion",
            )
        }

        val layout = requireObject(root, "layout", "root")
        requireExactKeys(layout, allowedLayoutKeys, "layout")
        requireDouble(layout, "textRatio", "layout", min = 0.1, max = 4.0)
        requireDouble(layout, "keyboardRatio", "layout", min = 0.1, max = 4.0)
        requireInt(layout, "appPaddingPx", "layout", min = 0, max = 64)
        requireInt(layout, "sectionGapPx", "layout", min = 0, max = 64)
        requireInt(layout, "keyGapPx", "layout", min = 0, max = 64)
        requireInt(layout, "keyboardRowGapPx", "layout", min = 0, max = 64)
        requireDouble(layout, "textSizeMultiplier", "layout", min = 0.5, max = 2.0)
        requireDouble(layout, "keySizeMultiplier", "layout", min = 0.5, max = 2.0)

        val keyboard = requireObject(root, "keyboard", "root")
        requireExactKeys(keyboard, allowedKeyboardKeys, "keyboard")
        val defaultLocale = requireString(keyboard, "defaultLocale", "keyboard")
        val locales = requireObject(keyboard, "locales", "keyboard")
        val localeKeys = locales.keySetCompat()
        if (localeKeys.isEmpty()) {
            throw IllegalArgumentException("keyboard.locales не может быть пустым")
        }
        if (defaultLocale !in localeKeys) {
            throw IllegalArgumentException("keyboard.defaultLocale должен ссылаться на существующий locale")
        }
        localeKeys.forEach { localeKey ->
            validateLocale(requireObject(locales, localeKey, "keyboard.locales"), localeKey)
        }

        val shell = requireObject(root, "shell", "root")
        requireExactKeys(shell, allowedShellKeys, "shell")
        val featureFlags = requireObject(shell, "featureFlags", "shell")
        requireExactKeys(featureFlags, allowedFeatureFlagKeys, "shell.featureFlags")
        allowedFeatureFlagKeys.forEach { flagKey ->
            requireBoolean(featureFlags, flagKey, "shell.featureFlags")
        }
        val serviceButtonOrder = requireArray(shell, "serviceButtonOrder", "shell")
        validateServiceButtonOrder(serviceButtonOrder)

        val labels = requireObject(root, "labels", "root")
        requireExactKeys(labels, allowedLabelsKeys, "labels")
        validateLocalizedTextMap(requireObject(labels, "placeholder", "labels"), "labels.placeholder", localeKeys)

        val serviceButtons = requireObject(labels, "serviceButtons", "labels")
        requireExactKeys(serviceButtons, allowedServiceButtonsKeys, "labels.serviceButtons")
        validateStaticServiceButtonLabel(
            requireObject(serviceButtons, "clear", "labels.serviceButtons"),
            "labels.serviceButtons.clear",
            localeKeys,
        )
        validateDynamicServiceButtonLabel(
            requireObject(serviceButtons, "locale", "labels.serviceButtons"),
            "labels.serviceButtons.locale",
            localeKeys,
        )
        validateStaticServiceButtonLabel(
            requireObject(serviceButtons, "exit", "labels.serviceButtons"),
            "labels.serviceButtons.exit",
            localeKeys,
        )

        val specialKeys = requireObject(labels, "specialKeys", "labels")
        requireExactKeys(specialKeys, allowedSpecialKeys, "labels.specialKeys")
        allowedSpecialKeys.forEach { keyId ->
            validateLocalizedTextMap(
                requireObject(specialKeys, keyId, "labels.specialKeys"),
                "labels.specialKeys.$keyId",
                localeKeys,
            )
        }

        return ValidatedConfig(
            configVersion = configVersion,
            payload = root.toString(),
        )
    }

    private fun validateLocale(localeConfig: JSONObject, localeKey: String) {
        requireExactKeys(localeConfig, allowedLocaleKeys, "keyboard.locales.$localeKey")
        requireString(localeConfig, "displayName", "keyboard.locales.$localeKey", minLength = 1, maxLength = 8)
        val rows = requireArray(localeConfig, "rows", "keyboard.locales.$localeKey")
        if (rows.length() == 0) {
            throw IllegalArgumentException("keyboard.locales.$localeKey.rows не может быть пустым")
        }
        for (index in 0 until rows.length()) {
            val row = rows.optJSONObject(index)
                ?: throw IllegalArgumentException("keyboard.locales.$localeKey.rows[$index] должен быть объектом")
            validateRow(row, "keyboard.locales.$localeKey.rows[$index]")
        }
    }

    private fun validateRow(row: JSONObject, path: String) {
        requireExactKeys(row, allowedRowKeys, path)
        requireString(row, "id", path, minLength = 1, maxLength = 48)
        val template = requireObject(row, "template", path)
        requireExactKeys(template, allowedTemplateKeys, "$path.template")
        val columns = requireArray(template, "columns", "$path.template")
        val keys = requireArray(row, "keys", path)
        if (columns.length() != keys.length()) {
            throw IllegalArgumentException("$path.template.columns должен совпадать по длине с keys")
        }
        if (keys.length() == 0) {
            throw IllegalArgumentException("$path.keys не может быть пустым")
        }
        for (index in 0 until columns.length()) {
            val weight = columns.opt(index).asStrictDouble()
            if (weight == null || weight <= 0.0) {
                throw IllegalArgumentException("$path.template.columns[$index] должен быть положительным числом")
            }
        }
        for (index in 0 until keys.length()) {
            val key = keys.optJSONObject(index)
                ?: throw IllegalArgumentException("$path.keys[$index] должен быть объектом")
            validateKey(key, "$path.keys[$index]")
        }
    }

    private fun validateKey(key: JSONObject, path: String) {
        val kind = requireString(key, "kind", path)
        when (kind) {
            "input" -> {
                requireExactKeys(key, allowedInputKeyKeys, path)
                requireString(key, "value", path, minLength = 1, maxLength = 8)
            }

            "space", "backspace", "enter" -> {
                requireExactKeys(key, allowedSpecialKeyKeys, path)
            }

            else -> throw IllegalArgumentException("$path.kind имеет неподдерживаемое значение: $kind")
        }
    }

    private fun validateServiceButtonOrder(buttonOrder: JSONArray) {
        if (buttonOrder.length() == 0) {
            throw IllegalArgumentException("shell.serviceButtonOrder не может быть пустым")
        }
        val seen = linkedSetOf<String>()
        for (index in 0 until buttonOrder.length()) {
            val buttonId = buttonOrder.opt(index) as? String
                ?: throw IllegalArgumentException("shell.serviceButtonOrder[$index] должен быть строкой")
            if (buttonId !in supportedServiceButtonIds) {
                throw IllegalArgumentException("shell.serviceButtonOrder[$index] содержит неподдерживаемый id: $buttonId")
            }
            if (!seen.add(buttonId)) {
                throw IllegalArgumentException("shell.serviceButtonOrder содержит duplicate id: $buttonId")
            }
        }
    }

    private fun validateStaticServiceButtonLabel(buttonConfig: JSONObject, path: String, localeKeys: Set<String>) {
        requireExactKeys(buttonConfig, allowedStaticServiceLabelKeys, path)
        requireString(buttonConfig, "label", path, minLength = 1, maxLength = 8)
        validateLocalizedTextMap(requireObject(buttonConfig, "titles", path), "$path.titles", localeKeys)
    }

    private fun validateDynamicServiceButtonLabel(buttonConfig: JSONObject, path: String, localeKeys: Set<String>) {
        requireExactKeys(buttonConfig, allowedDynamicServiceLabelKeys, path)
        validateLocalizedTextMap(requireObject(buttonConfig, "titles", path), "$path.titles", localeKeys)
    }

    private fun validateLocalizedTextMap(textMap: JSONObject, path: String, localeKeys: Set<String>) {
        val actualKeys = textMap.keySetCompat()
        if (actualKeys != localeKeys) {
            throw IllegalArgumentException("$path должен содержать ровно локали ${localeKeys.sorted()}")
        }
        actualKeys.forEach { localeKey ->
            requireString(textMap, localeKey, path, minLength = 0, maxLength = 120)
        }
    }

    private fun requireExactKeys(jsonObject: JSONObject, allowedKeys: Set<String>, path: String) {
        val actualKeys = jsonObject.keySetCompat()
        if (actualKeys != allowedKeys) {
            throw IllegalArgumentException(
                "$path должен содержать ровно поля ${allowedKeys.sorted()}, получено ${actualKeys.sorted()}",
            )
        }
    }

    private fun requireObject(parent: JSONObject, key: String, path: String): JSONObject {
        return parent.optJSONObject(key)
            ?: throw IllegalArgumentException("$path.$key должен быть объектом")
    }

    private fun requireArray(parent: JSONObject, key: String, path: String): JSONArray {
        return parent.optJSONArray(key)
            ?: throw IllegalArgumentException("$path.$key должен быть массивом")
    }

    private fun requireString(
        parent: JSONObject,
        key: String,
        path: String,
        minLength: Int = 1,
        maxLength: Int = 256,
        exactValue: String? = null,
    ): String {
        if (!parent.has(key) || parent.isNull(key)) {
            throw IllegalArgumentException("$path.$key должен быть строкой")
        }
        val value = parent.opt(key) as? String
            ?: throw IllegalArgumentException("$path.$key должен быть строкой")
        if (value.length !in minLength..maxLength) {
            throw IllegalArgumentException("$path.$key должен иметь длину в диапазоне $minLength..$maxLength")
        }
        if (exactValue != null && value != exactValue) {
            throw IllegalArgumentException("$path.$key должен быть равен $exactValue")
        }
        return value
    }

    private fun requireInt(
        parent: JSONObject,
        key: String,
        path: String,
        min: Int,
        max: Int = Int.MAX_VALUE,
    ): Int {
        if (!parent.has(key) || parent.isNull(key)) {
            throw IllegalArgumentException("$path.$key должен быть целым числом")
        }
        val value = parent.opt(key).asStrictInt()
            ?: throw IllegalArgumentException("$path.$key должен быть целым числом")
        if (value !in min..max) {
            throw IllegalArgumentException("$path.$key должен быть в диапазоне $min..$max")
        }
        return value
    }

    private fun requireDouble(
        parent: JSONObject,
        key: String,
        path: String,
        min: Double,
        max: Double,
    ): Double {
        if (!parent.has(key) || parent.isNull(key)) {
            throw IllegalArgumentException("$path.$key должен быть числом")
        }
        val value = parent.opt(key).asStrictDouble()
            ?: throw IllegalArgumentException("$path.$key должен быть числом")
        if (value < min || value > max) {
            throw IllegalArgumentException("$path.$key должен быть в диапазоне $min..$max")
        }
        return value
    }

    private fun requireBoolean(parent: JSONObject, key: String, path: String): Boolean {
        if (!parent.has(key) || parent.isNull(key)) {
            throw IllegalArgumentException("$path.$key должен быть boolean")
        }
        val value = parent.opt(key)
        if (value !is Boolean) {
            throw IllegalArgumentException("$path.$key должен быть boolean")
        }
        return value
    }

    private fun JSONObject.keySetCompat(): Set<String> = keys().asSequence().toSet()

    private fun Any?.asStrictInt(): Int? {
        val number = this as? Number ?: return null
        val doubleValue = number.toDouble()
        if (!doubleValue.isFinite() || doubleValue % 1.0 != 0.0) {
            return null
        }
        val longValue = number.toLong()
        if (longValue !in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) {
            return null
        }
        return longValue.toInt()
    }

    private fun Any?.asStrictDouble(): Double? {
        val number = this as? Number ?: return null
        val doubleValue = number.toDouble()
        return doubleValue.takeIf { it.isFinite() }
    }

    private data class ValidatedConfig(
        val configVersion: Int,
        val payload: String,
    )

    private const val EMERGENCY_DEFAULT_CONFIG_JSON = """
        {
          "contractName": "planka.ui-shell",
          "contractVersion": 1,
          "configVersion": 1,
          "compatibility": {
            "minShellVersion": 1,
            "maxShellVersion": 2147483647
          },
          "layout": {
            "textRatio": 1.0,
            "keyboardRatio": 0.95,
            "appPaddingPx": 8,
            "sectionGapPx": 10,
            "keyGapPx": 8,
            "keyboardRowGapPx": 8,
            "textSizeMultiplier": 1.0,
            "keySizeMultiplier": 1.0
          },
          "keyboard": {
            "defaultLocale": "ru",
            "locales": {
              "ru": {
                "displayName": "RU",
                "rows": [
                  {
                    "id": "numbers",
                    "template": { "columns": [1,1,1,1,1,1,1,1,1,1] },
                    "keys": [
                      { "kind": "input", "value": "1" },
                      { "kind": "input", "value": "2" },
                      { "kind": "input", "value": "3" },
                      { "kind": "input", "value": "4" },
                      { "kind": "input", "value": "5" },
                      { "kind": "input", "value": "6" },
                      { "kind": "input", "value": "7" },
                      { "kind": "input", "value": "8" },
                      { "kind": "input", "value": "9" },
                      { "kind": "input", "value": "0" }
                    ]
                  },
                  {
                    "id": "letters-1",
                    "template": { "columns": [1,1,1,1,1,1,1,1,1,1,1,1] },
                    "keys": [
                      { "kind": "input", "value": "Й" },
                      { "kind": "input", "value": "Ц" },
                      { "kind": "input", "value": "У" },
                      { "kind": "input", "value": "К" },
                      { "kind": "input", "value": "Е" },
                      { "kind": "input", "value": "Н" },
                      { "kind": "input", "value": "Г" },
                      { "kind": "input", "value": "Ш" },
                      { "kind": "input", "value": "Щ" },
                      { "kind": "input", "value": "З" },
                      { "kind": "input", "value": "Х" },
                      { "kind": "input", "value": "Ъ" }
                    ]
                  },
                  {
                    "id": "letters-2",
                    "template": { "columns": [1,1,1,1,1,1,1,1,1,1,1] },
                    "keys": [
                      { "kind": "input", "value": "Ф" },
                      { "kind": "input", "value": "Ы" },
                      { "kind": "input", "value": "В" },
                      { "kind": "input", "value": "А" },
                      { "kind": "input", "value": "П" },
                      { "kind": "input", "value": "Р" },
                      { "kind": "input", "value": "О" },
                      { "kind": "input", "value": "Л" },
                      { "kind": "input", "value": "Д" },
                      { "kind": "input", "value": "Ж" },
                      { "kind": "input", "value": "Э" }
                    ]
                  },
                  {
                    "id": "letters-3",
                    "template": { "columns": [1,1,1,1,1,1,1,1,1,1] },
                    "keys": [
                      { "kind": "input", "value": "Я" },
                      { "kind": "input", "value": "Ч" },
                      { "kind": "input", "value": "С" },
                      { "kind": "input", "value": "М" },
                      { "kind": "input", "value": "И" },
                      { "kind": "input", "value": "Т" },
                      { "kind": "input", "value": "Ь" },
                      { "kind": "input", "value": "Б" },
                      { "kind": "input", "value": "Ю" },
                      { "kind": "enter" }
                    ]
                  },
                  {
                    "id": "actions",
                    "template": { "columns": [2,1] },
                    "keys": [
                      { "kind": "space" },
                      { "kind": "backspace" }
                    ]
                  }
                ]
              },
              "en": {
                "displayName": "EN",
                "rows": [
                  {
                    "id": "numbers",
                    "template": { "columns": [1,1,1,1,1,1,1,1,1,1] },
                    "keys": [
                      { "kind": "input", "value": "1" },
                      { "kind": "input", "value": "2" },
                      { "kind": "input", "value": "3" },
                      { "kind": "input", "value": "4" },
                      { "kind": "input", "value": "5" },
                      { "kind": "input", "value": "6" },
                      { "kind": "input", "value": "7" },
                      { "kind": "input", "value": "8" },
                      { "kind": "input", "value": "9" },
                      { "kind": "input", "value": "0" }
                    ]
                  },
                  {
                    "id": "letters-1",
                    "template": { "columns": [1,1,1,1,1,1,1,1,1,1] },
                    "keys": [
                      { "kind": "input", "value": "Q" },
                      { "kind": "input", "value": "W" },
                      { "kind": "input", "value": "E" },
                      { "kind": "input", "value": "R" },
                      { "kind": "input", "value": "T" },
                      { "kind": "input", "value": "Y" },
                      { "kind": "input", "value": "U" },
                      { "kind": "input", "value": "I" },
                      { "kind": "input", "value": "O" },
                      { "kind": "input", "value": "P" }
                    ]
                  },
                  {
                    "id": "letters-2",
                    "template": { "columns": [1,1,1,1,1,1,1,1,1] },
                    "keys": [
                      { "kind": "input", "value": "A" },
                      { "kind": "input", "value": "S" },
                      { "kind": "input", "value": "D" },
                      { "kind": "input", "value": "F" },
                      { "kind": "input", "value": "G" },
                      { "kind": "input", "value": "H" },
                      { "kind": "input", "value": "J" },
                      { "kind": "input", "value": "K" },
                      { "kind": "input", "value": "L" }
                    ]
                  },
                  {
                    "id": "letters-3",
                    "template": { "columns": [1,1,1,1,1,1,1,1] },
                    "keys": [
                      { "kind": "input", "value": "Z" },
                      { "kind": "input", "value": "X" },
                      { "kind": "input", "value": "C" },
                      { "kind": "input", "value": "V" },
                      { "kind": "input", "value": "B" },
                      { "kind": "input", "value": "N" },
                      { "kind": "input", "value": "M" },
                      { "kind": "enter" }
                    ]
                  },
                  {
                    "id": "actions",
                    "template": { "columns": [2,1] },
                    "keys": [
                      { "kind": "space" },
                      { "kind": "backspace" }
                    ]
                  }
                ]
              }
            }
          },
          "shell": {
            "featureFlags": {
              "showClearButton": true,
              "showLocaleButton": true,
              "showExitButton": true
            },
            "serviceButtonOrder": ["clear", "locale", "exit"]
          },
          "labels": {
            "placeholder": {
              "ru": "Текст появится здесь",
              "en": "Text appears here"
            },
            "serviceButtons": {
              "clear": {
                "label": "⌫",
                "titles": {
                  "ru": "Очистить",
                  "en": "Clear"
                }
              },
              "locale": {
                "titles": {
                  "ru": "Язык",
                  "en": "Language"
                }
              },
              "exit": {
                "label": "×",
                "titles": {
                  "ru": "Выход",
                  "en": "Exit"
                }
              }
            },
            "specialKeys": {
              "space": {
                "ru": "ПРОБЕЛ",
                "en": "SPACE"
              },
              "backspace": {
                "ru": "←",
                "en": "←"
              },
              "enter": {
                "ru": "↵",
                "en": "↵"
              }
            }
          }
        }
    """
}
