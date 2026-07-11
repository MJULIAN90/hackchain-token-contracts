# HackChain Smart Contract Security Audit

Auditoría de seguridad y revisión de lógica de negocio de los contratos inteligentes del ecosistema **HackChain**, preparada sobre un entorno **Foundry-only**.

> **Importante:** los contratos ubicados en `src/` corresponden al código auditado.  
> Las pruebas incluidas reproducen comportamientos y vulnerabilidades observadas; **no representan contratos corregidos ni una remediación**.

---

## Auditor

**Julian Ruiz**  
Blockchain Engineer — Smart Contract Security Reviewer  
LinkedIn: https://www.linkedin.com/in/julian-ruiz-v/

---

## Objetivo de la auditoría

La revisión tuvo como objetivos:

- identificar vulnerabilidades técnicas en los contratos inteligentes;
- validar controles de acceso, transferencias, contabilidad y estados internos;
- revisar los flujos de staking, referidos, membresías, penalizaciones y bonificaciones;
- comparar el comportamiento del código con el whitepaper, el plan de negocios y los mecanismos del token HACK;
- crear pruebas reproducibles en Foundry;
- documentar el impacto, el flujo de explotación y las posibles remediaciones.

La auditoría combina:

1. revisión manual de Solidity;
2. pruebas unitarias de seguridad;
3. Proofs of Concept (PoC);
4. fuzz testing;
5. pruebas orientadas a invariantes;
6. revisión de lógica de negocio;
7. análisis de arquitectura y dependencias entre contratos.

---

## Alcance auditado

Los contratos revisados se encuentran en:

```text
src/
├── HackTokenERC20.sol
├── IncentivesPool.sol
├── StakingContract.sol
├── ReferralSystem.sol
├── MembershipSystem.sol
├── PenaltySystem.sol
├── TalentBonuses.sol
├── EducatorBonuses.sol
├── RecruiterBonuses.sol
├── EventRewards.sol
└── ReputationBunises.sol
```

El archivo `ReputationBunises.sol` conserva el nombre encontrado en el código auditado.

---

## Estructura del repositorio

```text
Hackchain_Foundry_Audit/
├── src/                        # Contratos Solidity auditados
├── test/
│   ├── security/               # PoC de vulnerabilidades técnicas
│   ├── business/               # PoC de brechas de lógica de negocio
│   ├── invariant/              # Fuzz e invariantes
│   └── utils/                  # Utilidades compartidas de pruebas
├── script/
│   ├── DeployHackchain.s.sol   # Despliegue y configuración de roles
│   └── FundIncentivesPool.s.sol
├── lib/                        # Dependencias Solidity
├── audit/
│   ├── reports/                # Informes finales
│   ├── findings/               # Hallazgos estructurados en CSV y JSON
│   ├── business-docs/          # Whitepaper y documentos funcionales
│   ├── diagrams/               # Diagramas de interacción
│   ├── evidence/               # Evidencia de compilación y ejecución
│   ├── FOUNDRY_TEST_MATRIX.md  # Relación entre pruebas y comportamientos
│   └── README.md
├── foundry.toml
├── remappings.txt
├── .env.example
├── AUDITOR.md
└── LICENSE
```

---

## Dónde encontrar cada detalle

### Contratos auditados

```text
src/
```

Contiene el snapshot de Solidity que fue objeto de la auditoría.

### Informe de auditoría en español

```text
audit/reports/INFORME_AUDITORIA_HACKCHAIN_ES.pdf
```

Incluye:

- resumen ejecutivo;
- alcance;
- clasificación por severidad;
- descripción de los hallazgos;
- impacto;
- recomendaciones;
- revisión de lógica de negocio;
- conclusión de seguridad.

### Audit report in English

```text
audit/reports/HACKCHAIN_SMART_CONTRACT_AUDIT_EN.pdf
```

Versión en inglés del informe final.

### Hallazgos estructurados

```text
audit/findings/findings.csv
audit/findings/findings.json
```

Permiten importar los hallazgos a herramientas internas, hojas de cálculo, dashboards o sistemas de seguimiento.

### Brechas de lógica de negocio

```text
audit/findings/business_gaps.csv
audit/findings/business_gaps.json
```

Contienen diferencias entre el comportamiento de los contratos y las reglas descritas por HackChain.

### Pruebas de vulnerabilidades técnicas

```text
test/security/SecurityPoC.t.sol
```

Incluye PoC relacionadas con:

- validación inmediata de recompensas por referido;
- bloqueo del principal cuando el pool de incentivos no tiene fondos;
- activación anticipada del beneficio sin comisiones;
- generación de visualizaciones por el propio educador;
- penalizaciones evitables mediante allowance;
- contabilidad del pool sin transferencia real de activos;
- límites de época en recompensas de reputación;
- recompensas repetidas por contratación;
- separación inconsistente entre ownership y AccessControl;
- acceso inválido a posiciones de staking.

### Pruebas de lógica de negocio

```text
test/business/BusinessLogicPoC.t.sol
```

Incluye escenarios relacionados con:

- penalización por suplantación sin bloqueo efectivo del perfil;
- reducción de la base de penalización mediante staking;
- cálculo de venta masiva con balance posterior a la venta;
- beneficio sin comisiones que continúa después de retirar el stake;
- financiación de proyectos con identificadores o destinos no restringidos;
- uso único del identificador de eventos promocionales.

### Fuzz e invariantes

```text
test/invariant/IncentivesPoolInvariant.t.sol
```

Busca contraejemplos donde el balance reportado por el pool sea superior a los tokens que realmente posee.

### Matriz de pruebas

```text
audit/FOUNDRY_TEST_MATRIX.md
```

Resume qué archivo de prueba cubre cada categoría de riesgo.

### Evidencia reproducible

```text
audit/evidence/
├── audited-commit.txt
├── forge-build.txt
├── forge-test.txt
├── forge-fmt.txt
└── contract-sha256.txt
```

- `audited-commit.txt`: referencia del snapshot auditado.
- `forge-build.txt`: salida guardada de compilación.
- `forge-test.txt`: salida guardada de las pruebas.
- `forge-fmt.txt`: resultado de formato.
- `contract-sha256.txt`: hashes de integridad de los contratos.

### Documentación de negocio

```text
audit/business-docs/
```

Contiene los documentos utilizados para contrastar el código con la lógica funcional:

- mecanismos del token HACK;
- plan de negocios;
- whitepaper;
- diagramas de mecanismos;
- presentación general del proyecto.

### Diagramas

```text
audit/diagrams/FLUJO_INTERACCION_HACKCHAIN.png
```

Muestra actores, componentes y recorridos funcionales del ecosistema.

> El diagrama funcional debe leerse junto con los informes. Algunos elementos representan la arquitectura esperada del negocio y no necesariamente contratos implementados uno a uno.

---

## Requisitos

Instalar Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Verificar la instalación:

```bash
forge --version
cast --version
anvil --version
```

La configuración del proyecto utiliza:

```text
Solidity: 0.8.24
EVM: Cancun
Optimizer: enabled
Optimizer runs: 200
```

---

## Instalación

Clonar o descomprimir el repositorio y entrar al directorio:

```bash
cd Hackchain_Foundry_Audit
```

Las dependencias requeridas ya están incluidas en `lib/`.

Validar que Foundry reconoce el proyecto:

```bash
forge config
```

---

## Compilar

```bash
forge build
```

Compilación con más información:

```bash
forge build -vvv
```

Limpiar artefactos y compilar nuevamente:

```bash
forge clean
forge build
```

---

## Ejecutar todas las pruebas

```bash
forge test -vv
```

Para obtener trazas completas:

```bash
forge test -vvvv
```

El repositorio incluye **17 pruebas reproducibles** entre PoC de seguridad, lógica de negocio, fuzzing e invariantes.

---

## Ejecutar solo las PoC de seguridad

```bash
forge test \
  --match-path "test/security/*.t.sol" \
  -vvvv
```

---

## Ejecutar solo las pruebas de lógica de negocio

```bash
forge test \
  --match-path "test/business/*.t.sol" \
  -vvvv
```

---

## Ejecutar fuzz e invariantes

```bash
forge test \
  --match-path "test/invariant/*.t.sol" \
  -vvvv
```

Perfil CI con más ejecuciones:

```bash
FOUNDRY_PROFILE=ci forge test -vv
```

El perfil `ci` incrementa los parámetros de fuzzing e invariantes definidos en `foundry.toml`.

---

## Ejecutar una vulnerabilidad específica

### H-01 — recompensa por referido validada inmediatamente

```bash
forge test \
  --match-test test_H01_ReferralRewardCanBeClaimedImmediately \
  -vvvv
```

### H-02 — falta de fondos del pool bloquea el retiro del principal

```bash
forge test \
  --match-test test_H02_EmptyRewardPoolBlocksPrincipalWithdrawal \
  -vvvv
```

### H-03 — el educador puede generar sus propias visualizaciones

```bash
forge test \
  --match-test test_H03_EducatorCanSelfGenerateViewsAndDrainPool \
  -vvvv
```

### H-04 — penalización evitable retirando o negando allowance

```bash
forge test \
  --match-test test_H04_PenaltyCanBeAvoidedByWithholdingAllowance \
  -vvvv
```

### M-01 — contabilidad del pool sin activos reales

```bash
forge test \
  --match-test testFuzz_M01_DepositInflatesAccountingWithoutTokens \
  -vvvv
```

### M-02 — beneficio sin comisiones activado inmediatamente

```bash
forge test \
  --match-test test_M02_NoCommissionCanBeActivatedImmediately \
  -vvvv
```

### M-03 — reclamo de reputación en límite de época

```bash
forge test \
  --match-test test_M03_ReputationClaimBreaksAcrossEpochBoundary \
  -vvvv
```

### M-04 — recompensa repetida por la misma contratación

```bash
forge test \
  --match-test test_M04_IdenticalHiringCanBeRewardedRepeatedly \
  -vvvv
```

### M-05 — transferencia de ownership no mueve el administrador de roles

```bash
forge test \
  --match-test test_M05_OwnershipTransferDoesNotMoveAccessControlAdmin \
  -vvvv
```

### L-02 — índice inválido produce panic antes del error personalizado

```bash
forge test \
  --match-test test_L02_InvalidStakeIndexPanicsBeforeCustomError \
  -vvvv
```

---

## Reporte de gas

```bash
forge test --gas-report
```

---

## Cobertura

```bash
forge coverage
```

Para generar un archivo LCOV:

```bash
forge coverage --report lcov
```

---

## Formato

Comprobar formato:

```bash
forge fmt --check
```

Aplicar formato:

```bash
forge fmt
```

> Aplicar `forge fmt` modifica archivos. No debe ejecutarse sobre el snapshot auditado si se desea conservar exactamente sus hashes.

---

## Despliegue local

Iniciar Anvil:

```bash
anvil
```

En otra terminal, configurar las variables necesarias:

```bash
cp .env.example .env
```

Cargar variables:

```bash
source .env
```

Ejecutar el script de despliegue:

```bash
forge script script/DeployHackchain.s.sol:DeployHackchain \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  -vvvv
```

El script:

- despliega el token HACK;
- despliega el pool de incentivos;
- despliega los módulos auditados;
- asigna `DISTRIBUTOR_ROLE`;
- asigna `DEPOSITOR_ROLE`;
- configura la dirección de tesorería.

> El script despliega el código auditado tal como fue recibido. No corrige las vulnerabilidades documentadas.

---

## Financiar el IncentivesPool

Después del despliegue, configurar en `.env` las direcciones requeridas y ejecutar:

```bash
forge script script/FundIncentivesPool.s.sol:FundIncentivesPool \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  -vvvv
```

---

## Cómo interpretar una PoC

Una PoC que termina en `PASS` significa que Foundry logró reproducir el comportamiento vulnerable esperado por la prueba.

Ejemplo:

```text
[PASS] test_H01_ReferralRewardCanBeClaimedImmediately()
```

No significa que el contrato sea seguro. Significa que la prueba confirmó que el escenario descrito puede ocurrir bajo las condiciones implementadas.

Después de aplicar una remediación, el equipo debe:

1. crear una rama separada;
2. modificar el contrato correspondiente;
3. convertir la PoC en una prueba de regresión;
4. comprobar que el ataque ya no produce el resultado vulnerable;
5. agregar pruebas del flujo legítimo;
6. ejecutar toda la suite;
7. revisar balances, eventos, roles y cambios de storage;
8. solicitar una reauditoría.

---

## Flujo recomendado de remediación

```text
Hallazgo
   ↓
Localizar contrato y función
   ↓
Ejecutar PoC individual
   ↓
Confirmar el estado vulnerable
   ↓
Aplicar corrección mínima y segura
   ↓
Agregar prueba de regresión
   ↓
Ejecutar todas las pruebas
   ↓
Ejecutar fuzz/invariantes
   ↓
Revisión de código
   ↓
Reauditoría
```

No se recomienda eliminar una PoC porque falle después de la corrección. Debe adaptarse para demostrar que la vulnerabilidad quedó bloqueada.

---

## Comandos rápidos

```bash
# Compilar
forge build

# Ejecutar toda la suite
forge test -vv

# Trazas completas
forge test -vvvv

# PoC técnicas
forge test --match-path "test/security/*.t.sol" -vvvv

# Lógica de negocio
forge test --match-path "test/business/*.t.sol" -vvvv

# Fuzz e invariantes
forge test --match-path "test/invariant/*.t.sol" -vvvv

# Perfil CI
FOUNDRY_PROFILE=ci forge test -vv

# Gas
forge test --gas-report

# Cobertura
forge coverage

# Formato
forge fmt --check
```

---

## Limitaciones

Esta auditoría:

- corresponde al snapshot entregado;
- no garantiza ausencia absoluta de vulnerabilidades;
- no cubre contratos o integraciones que no estén incluidos en `src/`;
- no audita la implementación externa de un DEX, el pool HACK/USDT, bridges, frontends, backend, oráculos, KYC ni infraestructura fuera del repositorio;
- no valida una remediación futura;
- no sustituye una reauditoría antes de desplegar fondos reales.

Cambios en contratos, roles, parámetros, dependencias, scripts o arquitectura pueden invalidar parcial o totalmente las conclusiones.

---

## Estado de seguridad

Los contratos incluidos corresponden al código auditado y contienen hallazgos pendientes documentados en los informes.

**No deben considerarse aptos para producción con fondos reales hasta que los hallazgos aplicables sean corregidos, probados y reauditorados.**

---

## Integridad del código

Para verificar los hashes del snapshot:

```bash
sha256sum -c audit/evidence/contract-sha256.txt
```

La verificación debe ejecutarse desde la raíz del repositorio.

---

## Contacto del auditor

**Julian Ruiz**  
Blockchain Engineer — Smart Contract Security Reviewer  
LinkedIn: https://www.linkedin.com/in/julian-ruiz-v/
