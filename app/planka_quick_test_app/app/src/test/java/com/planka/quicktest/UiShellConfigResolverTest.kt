package com.planka.quicktest

import org.junit.Assert.assertTrue
import org.junit.Test

class UiShellConfigResolverTest {

    @Test
    fun `accepts valid config payload`() {
        val payload = """
            {
              "contractName": "planka.ui-shell",
              "contractVersion": 1,
              "configVersion": 3,
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
                        "template": { "columns": [1, 1] },
                        "keys": [
                          { "kind": "input", "value": "1" },
                          { "kind": "input", "value": "2" }
                        ]
                      },
                      {
                        "id": "actions",
                        "template": { "columns": [2, 1] },
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
                  "showLocaleButton": false,
                  "showExitButton": true
                },
                "serviceButtonOrder": ["clear", "exit"]
              },
              "labels": {
                "placeholder": {
                  "ru": "Текст появится здесь"
                },
                "serviceButtons": {
                  "clear": {
                    "label": "⌫",
                    "titles": {
                      "ru": "Очистить"
                    }
                  },
                  "locale": {
                    "titles": {
                      "ru": "Язык"
                    }
                  },
                  "exit": {
                    "label": "×",
                    "titles": {
                      "ru": "Выход"
                    }
                  }
                },
                "specialKeys": {
                  "space": {
                    "ru": "ПРОБЕЛ"
                  },
                  "backspace": {
                    "ru": "←"
                  },
                  "enter": {
                    "ru": "↵"
                  }
                }
              }
            }
        """.trimIndent()

        val normalizedPayload = UiShellConfigResolver.validatePayload(payload)

        assertTrue(normalizedPayload.contains("\"configVersion\":3"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `rejects config when locale labels are incomplete`() {
        val payload = """
            {
              "contractName": "planka.ui-shell",
              "contractVersion": 1,
              "configVersion": 2,
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
                        "template": { "columns": [1] },
                        "keys": [
                          { "kind": "input", "value": "1" }
                        ]
                      }
                    ]
                  },
                  "en": {
                    "displayName": "EN",
                    "rows": [
                      {
                        "id": "numbers",
                        "template": { "columns": [1] },
                        "keys": [
                          { "kind": "input", "value": "1" }
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
                  "ru": "Текст появится здесь"
                },
                "serviceButtons": {
                  "clear": {
                    "label": "⌫",
                    "titles": {
                      "ru": "Очистить"
                    }
                  },
                  "locale": {
                    "titles": {
                      "ru": "Язык"
                    }
                  },
                  "exit": {
                    "label": "×",
                    "titles": {
                      "ru": "Выход"
                    }
                  }
                },
                "specialKeys": {
                  "space": {
                    "ru": "ПРОБЕЛ"
                  },
                  "backspace": {
                    "ru": "←"
                  },
                  "enter": {
                    "ru": "↵"
                  }
                }
              }
            }
        """.trimIndent()

        UiShellConfigResolver.validatePayload(payload)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `rejects config when shell compatibility window excludes current shell`() {
        val payload = """
            {
              "contractName": "planka.ui-shell",
              "contractVersion": 1,
              "configVersion": 4,
              "compatibility": {
                "minShellVersion": ${BuildConfig.VERSION_CODE + 1},
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
                        "template": { "columns": [1] },
                        "keys": [
                          { "kind": "input", "value": "1" }
                        ]
                      }
                    ]
                  }
                }
              },
              "shell": {
                "featureFlags": {
                  "showClearButton": true,
                  "showLocaleButton": false,
                  "showExitButton": true
                },
                "serviceButtonOrder": ["clear", "exit"]
              },
              "labels": {
                "placeholder": {
                  "ru": "Текст появится здесь"
                },
                "serviceButtons": {
                  "clear": {
                    "label": "⌫",
                    "titles": {
                      "ru": "Очистить"
                    }
                  },
                  "locale": {
                    "titles": {
                      "ru": "Язык"
                    }
                  },
                  "exit": {
                    "label": "×",
                    "titles": {
                      "ru": "Выход"
                    }
                  }
                },
                "specialKeys": {
                  "space": {
                    "ru": "ПРОБЕЛ"
                  },
                  "backspace": {
                    "ru": "←"
                  },
                  "enter": {
                    "ru": "↵"
                  }
                }
              }
            }
        """.trimIndent()

        UiShellConfigResolver.validatePayload(payload)
    }
}
