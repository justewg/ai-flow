package com.planka.quicktest

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class UiShellConfigResolverTest {

    @Test
    fun `validatePayload accepts config snapshot with row gaps`() {
        val normalized = UiShellConfigResolver.validatePayload(validConfigJson())
        val root = JSONObject(normalized)

        assertEquals(1, root.getInt("contractVersion"))
        assertEquals(8, root.getJSONObject("layout").getInt("keyboardRowGapPx"))
        assertEquals("ru", root.getJSONObject("keyboard").getString("defaultLocale"))
    }

    @Test
    fun `validatePayload rejects config without keyboardRowGapPx`() {
        val invalid = JSONObject(validConfigJson())
        invalid.getJSONObject("layout").remove("keyboardRowGapPx")

        val error = runCatching {
            UiShellConfigResolver.validatePayload(invalid.toString())
        }.exceptionOrNull()

        assertTrue(error is IllegalArgumentException)
        assertTrue(error?.message?.contains("keyboardRowGapPx") == true)
    }

    @Test
    fun `validatePayload rejects unknown top level field`() {
        val invalid = JSONObject(validConfigJson())
        invalid.put("unexpected", true)

        val error = runCatching {
            UiShellConfigResolver.validatePayload(invalid.toString())
        }.exceptionOrNull()

        assertTrue(error is IllegalArgumentException)
        assertTrue(error?.message?.contains("root") == true)
    }

    @Test
    fun `validatePayload rejects incomplete localized label map`() {
        val invalid = JSONObject(validConfigJson())
        invalid.getJSONObject("labels")
            .getJSONObject("placeholder")
            .remove("en")

        val error = validationError(invalid)

        assertTrue(error is IllegalArgumentException)
        assertTrue(error?.message?.contains("labels.placeholder") == true)
    }

    @Test
    fun `validatePayload rejects row when template columns length differs from keys`() {
        val invalid = JSONObject(validConfigJson())
        val row = invalid.getJSONObject("keyboard")
            .getJSONObject("locales")
            .getJSONObject("ru")
            .getJSONArray("rows")
            .getJSONObject(0)
        row.getJSONObject("template").put("columns", JSONArray("[1,1]"))

        val error = validationError(invalid)

        assertTrue(error is IllegalArgumentException)
        assertTrue(error?.message?.contains("template.columns должен совпадать по длине с keys") == true)
    }

    @Test
    fun `validatePayload rejects stringified numeric fields`() {
        val invalid = JSONObject(validConfigJson())
        invalid.getJSONObject("layout").put("appPaddingPx", "8")

        val error = validationError(invalid)

        assertTrue(error is IllegalArgumentException)
        assertTrue(error?.message?.contains("layout.appPaddingPx должен быть целым числом") == true)
    }

    @Test
    fun `schema declares runtime cross-field invariants`() {
        val schema = JSONObject(File("src/main/assets/ui-shell-config.schema.json").readText())

        val compatibilityInvariants = schema.getJSONObject("properties")
            .getJSONObject("compatibility")
            .getJSONArray("x-planka-invariants")
        val keyboardInvariants = schema.getJSONObject("properties")
            .getJSONObject("keyboard")
            .getJSONArray("x-planka-invariants")
        val localizedTextInvariants = schema.getJSONObject("\$defs")
            .getJSONObject("localizedTextMap")
            .getJSONArray("x-planka-invariants")
        val keyboardRowInvariants = schema.getJSONObject("\$defs")
            .getJSONObject("keyboardRow")
            .getJSONArray("x-planka-invariants")

        assertEquals("orderedProperties", compatibilityInvariants.getJSONObject(0).getString("rule"))
        assertEquals("propertyMatchesObjectKey", keyboardInvariants.getJSONObject(0).getString("rule"))
        assertEquals("exactObjectKeysFrom", localizedTextInvariants.getJSONObject(0).getString("rule"))
        assertEquals("equalArrayLengths", keyboardRowInvariants.getJSONObject(0).getString("rule"))
    }

    private fun validationError(config: JSONObject): Throwable? = runCatching {
        UiShellConfigResolver.validatePayload(config.toString())
    }.exceptionOrNull()

    private fun validConfigJson(): String = """
        {
          "contractName": "planka.ui-shell",
          "contractVersion": 1,
          "configVersion": 3,
          "compatibility": {
            "minShellVersion": 1,
            "maxShellVersion": ${BuildConfig.VERSION_CODE + 10}
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
                    "template": {
                      "columns": [1, 1, 1]
                    },
                    "keys": [
                      { "kind": "input", "value": "1" },
                      { "kind": "input", "value": "2" },
                      { "kind": "input", "value": "3" }
                    ]
                  },
                  {
                    "id": "actions",
                    "template": {
                      "columns": [2, 1]
                    },
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
                    "template": {
                      "columns": [1, 1, 1]
                    },
                    "keys": [
                      { "kind": "input", "value": "1" },
                      { "kind": "input", "value": "2" },
                      { "kind": "input", "value": "3" }
                    ]
                  },
                  {
                    "id": "actions",
                    "template": {
                      "columns": [2, 1]
                    },
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
              "showExitButton": true,
              "showLocaleButton": true
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
    """.trimIndent()
}
