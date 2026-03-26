package com.planka.quicktest

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

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
