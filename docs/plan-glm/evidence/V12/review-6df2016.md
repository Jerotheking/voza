# Evidencia y Revisión Formal — V12 (Keychain + Frontera de Proveedores Cloud)

- **Commit verificado:** `6df20168f76b00f8a04a6ff9c45c8d2573a7c6ba` (`V12: cloud credentials in the Keychain + hardened provider boundary (151 tests, smoke 61)`)
- **Commit base:** `e6e4684afa361d968d20818da23af29292517774`
- **Sesión de cierre:** `sessions/2026-09-25T1800Z-V12-buffy.md`
- **Suite de pruebas:** `Tests/VozaTests/ProviderPrivacyTests.swift`

## Criterios de Aceptación Verificados

- **V12-AC01 (PASS):** En modo `plain` (o cualquier modo no-`cloud`), `Cleaner.clean` realiza cero llamadas de red aunque existan llaves configuradas en Keychain o `.env` (`testPlainModeMakesZeroCloudRequestsEvenWithKeys`).
- **V12-AC02 (PASS):** `SecureCleanupTransport` rechaza endpoints HTTP remotos (solo permite HTTPS o loopback explícito `127.0.0.1`/`localhost`/`::1`) y `NoRedirectDelegate` cancela toda redirección HTTP antes de reenviar encabezados `Authorization` / `x-api-key` (`testInsecureRemoteEndpointRefusedWithoutSendingCredential`, `testRedirectProducesNoSecondRequest`).
- **V12-AC03 (PASS):** `SecItemKeychainStore` persiste credenciales bajo `com.jerotherey.voza.credentials` (con namespace aislado para rutas QA) y `Config.migrateEnvKeyToKeychain` verifica la lectura en Keychain antes de eliminar la línea en texto plano de `~/.config/voza/.env` (`testFailedKeychainWriteKeepsEnvFileIntact`, `testMigrationStripsFileOnlyAfterKeychainVerifies`).
- **V12-AC04 (PASS):** Las solicitudes autorizadas en modo `cloud` envían únicamente texto ya transcrito al proveedor seleccionado en orden (`openai` → `anthropic`) (`testCloudRequestCarriesTextOnlyToChosenProvider`, `testAnthropicFallbackOnlyAfterOpenAIFails`).
- **V12-AC05 (PASS):** Ninguna llave aparece en query strings, URLs ni logs (`testSecretsNeverAppearInURLQueryOrHostRecords`).
