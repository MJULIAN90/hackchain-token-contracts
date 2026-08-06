## Objetivo

Este trabajo se enfocó en dos frentes:

1. Incorporar un mecanismo claro de asignación para la preventa de HACK.
2. Preparar el entorno de despliegue en Polygon, con soporte para Polygon Amoy como red de validación previa.

## Qué se hizo

### 1. Contrato de preventa

Se agregó `PresaleAllocation.sol` como contrato dedicado para la preventa.

Funcionalidades:

- Asignación individual con `allocate()`.
- Asignación masiva con `allocateBatch()`.
- Reclamo por parte del beneficiario con `claim()` desde un escrow prefundeado.
- Bloqueo de 1 mes y tres liberaciones mensuales iguales para la preventa pública.
- Cierre administrativo con `finalizePresale()`.
- Retiro único de tokens no vendidos con `withdrawUnallocated()` tras el cierre.
- Límite total de preventa con `presaleCap`.

### 2. Despliegue en Foundry

Se agregó una base completa de Foundry para poder desplegar y probar el stack:

- `foundry.toml`
- scripts en `script/`
- tests en `test/`
- remappings dentro de `foundry.toml`

### 3. Script de despliegue

Se creó `DeployCore.s.sol` para desplegar y enlazar los contratos principales:

- `HackToken`
- `IncentivesPool`
- `StakingContract`
- `ReferralSystem`
- `MembershipSystem`
- `PenaltySystem`
- `EventRewards`
- `EducatorBonuses`
- `RecruiterBonuses`
- `TalentBonuses`
- `CommissionSystem`
- `ReputationBonuses`
- `PresaleAllocation`

### 4. Script operativo de preventa

Se creó `PresaleOps.s.sol` para operar la preventa sin reescribir lógica manualmente:

- asignar beneficiarios
- asignar en lote
- finalizar la preventa
- retirar el cupo no vendido

### 5. Pruebas

Se agregaron pruebas unitarias para validar:

- asignación y reclamo exitosos
- control de acceso
- bloqueo de nuevas asignaciones tras el cierre
- límite de preventa y retiro único del saldo no vendido

### 6. Corrección defensiva

Se corrigió un bug en `StakingContract.sol`:

- antes se accedía al stake antes de validar el índice
- ahora primero se valida que el índice exista y luego se accede a la estructura

## Por qué se hizo así

### Preventa separada del token

La preventa no quedó mezclada dentro del ERC20 principal porque eso complica auditoría, trazabilidad y mantenimiento.

Separarla en `PresaleAllocation` permite:

- auditar la preventa como un flujo independiente
- cerrar la preventa sin afectar el token base
- cambiar reglas de distribución sin tocar la lógica central del token

### Modelo de escrow prefundeado

En el despliegue, el total de `PRESALE_CAP` se mintea al contrato de preventa.
Cada reclamo transfiere desde ese saldo reservado.
Al finalizar la preventa comienza un cliff de 30 días; luego se habilita un tercio de cada
asignación por mes durante tres meses.

Ventajas:

- las asignaciones aprobadas siempre están respaldadas por tokens
- otros minters no pueden agotar el supply reservado para preventa
- el token no concede `MINTER_ROLE` al contrato de preventa
- al finalizar, el admin puede recuperar exclusivamente el cupo no vendido

### Foundry como base de despliegue

Foundry se eligió para dejar un flujo simple de:

- compilar
- probar
- desplegar
- operar la preventa

Eso reduce fricción cuando las correcciones pasen re-verificación y el deploy de Polygon deba ejecutarse de inmediato.

## Cómo funciona

### Flujo de preventa

1. El admin despliega `HackToken` y `PresaleAllocation`.
2. El admin asigna tokens de preventa a uno o varios beneficiarios.
3. El beneficiario ejecuta `claim()`.
4. Tras un mes de bloqueo, se habilita un tercio de su asignación por cada mes transcurrido.
5. `PresaleAllocation` transfiere únicamente la porción habilitada al beneficiario.
6. Cuando la preventa termina, el admin ejecuta `finalizePresale()`; esto inicia el bloqueo.
7. El admin puede ejecutar `withdrawUnallocated()` para recuperar el saldo no asignado.

### Flujo de despliegue

1. Se definen variables de entorno en `.env`.
2. Se crea una keystore cifrada con `cast wallet import`.
3. Se ejecuta `DeployCore.s.sol` con `--account` y `--password-file`.
4. El script despliega el stack completo, asigna roles y prefunde el escrow de preventa.
5. El admin operativo puede usar `PresaleOps.s.sol` para gestionar la preventa.

### Manejo de claves

La forma correcta de manejar las private keys de wallets de despliegue es mediante
encrypted keystore o hardware wallet.

- No se recomienda guardar private keys crudas en `.env`.
- Para testnet y producción, usa `cast wallet import` y `forge script --account`.
- Si el entorno lo requiere, puede usarse hardware wallet directamente con Foundry.

### Polygon Amoy

Amoy queda como red de validación previa.

La idea es:

- probar allí primero
- revisar que todo quede correctamente enlazado
- una vez aprobado, repetir el mismo flujo en Polygon mainnet

## Validación ejecutada

Se verificó localmente:

- `forge build`
- `forge test`

Resultado:

- compilación exitosa
- 7 pruebas unitarias pasando para la preventa

## Trazabilidad con la propuesta de negocio

Se contrastó esta implementación con el whitepaper y los documentos de mecanismos.

| Propuesta | Implementación |
|---|---|
| Red Polygon | Scripts preparados para Polygon Amoy y Polygon mainnet. |
| Forge y OpenZeppelin | Foundry configurado y dependencias oficiales OpenZeppelin v5.0.2 y forge-std v1.9.1. |
| Oferta máxima de 1,000,000,000 HACK | `HackToken` mantiene ese límite y el script valida que preventa más incentivos iniciales no lo excedan. |
| Preventa pública: 10%, 100,000,000 HACK | Valor documentado en `.env.example`; el cap se prefundea en escrow. |
| Preventa pública: bloqueo de 1 mes y liberación mensual de 3 meses | `finalizePresale()` inicia el calendario; se habilita un tercio en cada uno de los meses 1, 2 y 3. |
| Incentivos: 30%, 300,000,000 HACK | Valor documentado en `.env.example` para el fondeo inicial de `IncentivesPool`. |

La liberación de preventa se interpreta como tres tramos mensuales iguales, con el primero
habilitado al finalizar el mes de bloqueo. Si negocio requiere que la primera liberación ocurra
un mes después del cliff, el calendario debe cambiar antes de desplegar.

### Pendiente de una distribución tokenómica completa

El alcance solicitado cubre la preventa y el pool de incentivos. El whitepaper también define
asignaciones para equipo, venta privada, venta pública, tesorería y airdrops. Esas categorías
todavía no tienen contratos de allocation/vesting dedicados ni quedan inmovilizadas por el
script de despliegue; por ahora el admin centralizado las puede mintear dentro de `maxSupply`.

Antes de declarar la tokenomics completamente implementada, se recomienda crear un módulo de
asignación y vesting para esas categorías y eliminar el minteo administrativo discrecional una
vez se hayan configurado sus reservas.

## Decisión de administración

El proyecto se opera de forma centralizada: la wallet de despliegue puede ser la
misma que `PROTOCOL_ADMIN_ADDRESS` y `PRESALE_ADMIN_ADDRESS`. Por esa decisión,
el script mantiene sus roles administrativos en vez de revocarlos al finalizar.

Recomendación operativa: usar una wallet exclusiva para el despliegue y operación,
protegida con encrypted keystore o hardware wallet; no usar una private key cruda
en `.env`.

## Archivos principales

- [contracts/PresaleAllocation.sol](contracts/PresaleAllocation.sol)
- [script/DeployCore.s.sol](script/DeployCore.s.sol)
- [script/PresaleOps.s.sol](script/PresaleOps.s.sol)
- [test/PresaleAllocation.t.sol](test/PresaleAllocation.t.sol)
- [foundry.toml](foundry.toml)
- [README.md](README.md)

## Observación

Si más adelante se quiere endurecer el flujo de preventa, lo siguiente natural sería agregar:

- vesting lineal
- whitelist de participantes
- límites por wallet
- eventos de auditoría más detallados
