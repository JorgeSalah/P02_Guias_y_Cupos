# Plan de pruebas y rendimiento del proyecto P02

**Proyecto** · Guías y operadores: acreditación y cupos  
**Integrante** · Jorge Iván Salah Fernández  
**Asignatura** · Bases de Datos, Universidad del Magdalena  
**Entorno** · MariaDB 10.4.32 en XAMPP, base de datos `p02_guias_cupos`

## 1. Preparación

1. Reconstruye una base vacía siguiendo el orden del `README.md`. El esquema inicial está en `12_creacion_esquema_mariadb.sql`. Los archivos `22_control_cupos_por_grupo.sql`, `26_control_capacidad_jornada.sql` y `29_control_publicacion_cuotas.sql` completan los controles. `32_roles_y_permisos.sql` configura los roles.
2. Carga los datos sintéticos con `14_carga_datos_sinteticos_mariadb.sql`. Ejecuta `15_verificaciones_carga_mariadb.sql` y `16_consultas_validacion_mariadb.sql` **antes** de crear los registros `P5-`, para que los conteos correspondan a la carga inicial.
3. Conéctate como administrador para preparar los datos y las pruebas de negocio. Usa una cuenta con el rol `p02_taquilla` solo para la prueba de permisos.
4. Ejecuta cada caso que espera un rechazo en un envío aparte. Un mensaje de error esperado puede detener el resto de un bloque en phpMyAdmin. Los bloques que crean datos `P5-` se ejecutan una vez por base de pruebas.

## 2. Carga inicial y consultas

| Control | Resultado esperado | Resultado observado y evidencia |
|---|---|---|
| Conteos de la carga | 53.400 filas en las 11 tablas. Entre ellas, 10.000 reservas, 10.000 ingresos, 8.500 grupos y 1.000 incidencias. | Los 20 controles de conteo de la carga coincidieron. `evidencias/05_verificacion_carga.png`. |
| Integridad de los datos | Los controles de anomalías del script 15 deben devolver cero filas. | Las consultas de anomalías devolvieron resultados vacíos. |
| Q01 · Vigencia de certificados | Con corte al 16/11/2026 y horizonte de 14 días, 50 certificados vencidos y 50 próximos a vencer. | Los conteos se verificaron con el script 15. `evidencias/05_verificacion_carga.png`. |
| Q03 · Grupos con exceso | 500 grupos con ingreso superior al autorizado. | 500 grupos. `evidencias/06_q03_grupos_con_exceso.png`. |
| Q04 · Ingresos acumulados | Para `G1-00001`, `I-01` deja 6 acumulados y `I-02` deja 10 con 9 autorizados. La incidencia corresponde a `I-02`. | Se verificaron ambos acumulados y el vínculo del exceso. `evidencias/07_q04_incidencia_por_ingreso.png`. |
| Q05 · Uso de cupos | Para `OP-018`, `SEC-001` y 01/07/2026, 20 comprometidos, 44 asignables y capacidad 80. Como referencia, el uso es 45,45 % de la cuota y 25,00 % de la capacidad. | Valores de referencia para cotejar con la consulta. |
| Q06 y Q11 · Incidencias | Q06 muestra el detalle por guía y operador. Q11 agrupa por tipo. La carga contiene 500 excesos y 500 cambios de destino. | Los conteos por tipo se verificaron con el script 15. `evidencias/05_verificacion_carga.png`. |

En Q05, la fecha de corte selecciona la versión de la cuota. Los cupos comprometidos se calculan con el estado actual de las reservas para la jornada consultada.

## 3. Datos para las pruebas operativas

Ejecuta este bloque en la pestaña SQL de phpMyAdmin. La fecha fija los casos en una jornada posterior a la carga sintética. Las dos últimas llamadas se ejecutan después de confirmar la transacción de preparación.

```sql
USE p02_guias_cupos;

SET @ahora_p5 = UTC_TIMESTAMP(6) - INTERVAL 5 HOUR;
SET @visita_p5 = DATE_ADD(
    GREATEST(DATE(@ahora_p5), DATE('2026-10-08')), INTERVAL 2 DAY
);
SET @inicio_cuota_p5 = @ahora_p5 - INTERVAL 1 DAY;

START TRANSACTION;

INSERT INTO jornadas_sector (codigo_sector, fecha_visita, capacidad_personas)
VALUES ('SEC-001', @visita_p5, 20),
       ('SEC-002', @visita_p5, 20),
       ('SEC-003', @visita_p5, 20);

INSERT INTO limites_operador (
    codigo_operador, codigo_sector, fecha_visita, vigente_desde, porcentaje_maximo
)
VALUES ('OP-001', 'SEC-001', @visita_p5, @inicio_cuota_p5, 50.00),
       ('OP-001', 'SEC-002', @visita_p5, @inicio_cuota_p5, 50.00),
       ('OP-001', 'SEC-003', @visita_p5, @inicio_cuota_p5, 50.00);

INSERT INTO reservas (
    codigo_reserva, codigo_operador, codigo_sector, fecha_visita, cupos_reservados
)
VALUES ('P5-CUPO-A', 'OP-001', 'SEC-001', @visita_p5, 10),
       ('P5-CUPO-B', 'OP-001', 'SEC-001', @visita_p5, 10),
       ('P5-RES-GA', 'OP-001', 'SEC-002', @visita_p5, 10),
       ('P5-RES-GB', 'OP-001', 'SEC-003', @visita_p5, 10);

INSERT INTO guias (codigo_guia) VALUES ('P5-GUI-01'), ('P5-GUI-02');

INSERT INTO certificaciones (
    codigo_guia, ref_certificacion, tipo, entidad_emisora,
    fecha_emision, fecha_vencimiento
)
VALUES
    ('P5-GUI-01', 'P5-VENC', 'Acreditación de prueba', 'Emisora ficticia',
     DATE(@ahora_p5) - INTERVAL 30 DAY, DATE(@ahora_p5) - INTERVAL 1 DAY),
    ('P5-GUI-01', 'P5-VALIDA', 'Acreditación de prueba', 'Emisora ficticia',
     DATE(@ahora_p5) - INTERVAL 30 DAY, @visita_p5),
    ('P5-GUI-02', 'P5-VALIDA', 'Acreditación de prueba', 'Emisora ficticia',
     DATE(@ahora_p5) - INTERVAL 30 DAY, @visita_p5 + INTERVAL 30 DAY);

INSERT INTO grupos (codigo_grupo, codigo_reserva, visitantes_autorizados)
VALUES ('P5-G-A', 'P5-RES-GA', 10), ('P5-G-B', 'P5-RES-GB', 10);

COMMIT;

CALL sp_confirmar_reserva('P5-RES-GA');
CALL sp_confirmar_reserva('P5-RES-GB');
```

## 4. Pruebas de las reglas de negocio

### T01–T04 · Vigencia y destino del guía

Ejecuta el `SET` junto con cada `CALL` por separado, especialmente si phpMyAdmin abre una conexión nueva entre envíos.

```sql
SET @visita_p5 = (
    SELECT fecha_visita FROM reservas WHERE codigo_reserva = 'P5-RES-GA'
);

-- T01 · Certificado vencido. Espera un rechazo.
CALL sp_asignar_guia(
    'P5-G-A', 'P5-A-VENC', 'P5-GUI-01', 'P5-VENC',
    TIMESTAMP(@visita_p5, '08:00:00'), TIMESTAMP(@visita_p5, '11:00:00')
);

-- T02 · Visita en el último día válido. Espera una asignación.
CALL sp_asignar_guia(
    'P5-G-A', 'P5-A-01', 'P5-GUI-01', 'P5-VALIDA',
    TIMESTAMP(@visita_p5, '08:00:00'), TIMESTAMP(@visita_p5, '11:00:00')
);

-- T03 · Mismo guía en otro sector el mismo día. Espera un rechazo.
CALL sp_asignar_guia(
    'P5-G-B', 'P5-A-OTRO', 'P5-GUI-01', 'P5-VALIDA',
    TIMESTAMP(@visita_p5, '14:00:00'), TIMESTAMP(@visita_p5, '16:00:00')
);

-- T04 · Guía distinto para el segundo sector. Espera una asignación.
CALL sp_asignar_guia(
    'P5-G-B', 'P5-B-01', 'P5-GUI-02', 'P5-VALIDA',
    TIMESTAMP(@visita_p5, '14:00:00'), TIMESTAMP(@visita_p5, '16:00:00')
);

SELECT codigo_grupo, ref_asignacion, codigo_guia, ref_certificacion
FROM asignaciones_guia
WHERE codigo_grupo IN ('P5-G-A', 'P5-G-B')
ORDER BY codigo_grupo, ref_asignacion;
```

**Observado:** se rechazaron T01 y T03 con el error 1644. La tabla final mostró `P5-G-A` con `P5-GUI-01` y `P5-G-B` con `P5-GUI-02`. Evidencias 12 a 15.

### T05–T07 · Ingresos al límite, exceso y reintento

Ejecuta después de T02. Ejecuta el `SET` de nuevo si cambias de sesión.

```sql
SET @visita_p5 = (
    SELECT fecha_visita FROM reservas WHERE codigo_reserva = 'P5-RES-GA'
);

-- T05 · Límite exacto. Esperado: 10 personas y cero excesos.
CALL sp_registrar_ingreso('P5-G-A', 'P5-I-01', TIMESTAMP(@visita_p5, '08:15:00'), 6);
CALL sp_registrar_ingreso('P5-G-A', 'P5-I-02', TIMESTAMP(@visita_p5, '08:30:00'), 4);

SELECT COUNT(*) AS excesos_al_llegar_a_diez
FROM incidencias WHERE codigo_grupo = 'P5-G-A' AND tipo = 'exceso_personas';

-- T06 · Exceso. Esperado: una incidencia para P5-I-03 vinculada a P5-GUI-01.
CALL sp_registrar_ingreso('P5-G-A', 'P5-I-03', TIMESTAMP(@visita_p5, '08:45:00'), 1);

SELECT i.ref_ingreso, i.tipo, a.codigo_guia
FROM incidencias AS i
LEFT JOIN asignaciones_guia AS a
  ON a.codigo_grupo = i.codigo_grupo AND a.ref_asignacion = i.ref_asignacion
WHERE i.codigo_grupo = 'P5-G-A' AND i.tipo = 'exceso_personas';

-- T07 · En un envío aparte, repite P5-I-03. Esperado: error 1062.
CALL sp_registrar_ingreso('P5-G-A', 'P5-I-03', TIMESTAMP(@visita_p5, '08:45:00'), 1);

-- Después del rechazo, ejecuta por separado esta verificación.
SELECT COUNT(*) AS entradas,
       COALESCE(SUM(personas_ingresadas), 0) AS personas_ingresadas,
       (SELECT COUNT(*) FROM incidencias
        WHERE codigo_grupo = 'P5-G-A' AND tipo = 'exceso_personas') AS incidencias_por_exceso
FROM ingresos
WHERE codigo_grupo = 'P5-G-A';
```

**Observado:** al llegar a 10 autorizados hubo cero excesos. La entrada siguiente produjo una incidencia. El intento duplicado dejó 3 entradas, 11 personas y 1 incidencia. Evidencias 16 a 19.

### T08 · Dos sesiones compiten por la misma cuota

La jornada de `SEC-001` tiene capacidad 20 y el operador tiene una cuota del 50 %. Las reservas `P5-CUPO-A` y `P5-CUPO-B` solicitan 10 cupos cada una.

1. Abre tres conexiones independientes a MariaDB con la base `p02_guias_cupos`. Usa una como **Control** y las otras como **A** y **B**.
2. En **Control**, abre la transacción y bloquea la fila de la jornada. Si pegas en la consola, envía el `SELECT` en una sola línea.

```sql
START TRANSACTION;
SELECT codigo_sector, fecha_visita, capacidad_personas FROM jornadas_sector WHERE codigo_sector = 'SEC-001' AND fecha_visita = (SELECT fecha_visita FROM reservas WHERE codigo_reserva = 'P5-CUPO-A') FOR UPDATE;
```

3. En **A**, ejecuta `CALL sp_confirmar_reserva('P5-CUPO-A');`. Mientras espera, en **B** ejecuta `CALL sp_confirmar_reserva('P5-CUPO-B');`.
4. Con ambas llamadas pendientes, ejecuta `COMMIT;` en **Control**.
5. Comprueba el resultado.

```sql
SELECT codigo_reserva, estado, cupos_reservados,
       CASE WHEN estado = 'confirmada' THEN cupos_reservados ELSE 0 END
           AS cupos_comprometidos
FROM reservas
WHERE codigo_reserva IN ('P5-CUPO-A', 'P5-CUPO-B')
ORDER BY codigo_reserva;
```

**Esperado:** una reserva confirmada con 10 cupos comprometidos y la otra pendiente con 0. Cualquiera puede confirmarse primero. **Observado:** A se confirmó, B recibió el rechazo por cuota y quedó pendiente. Evidencias `20a_concurrencia_reserva_a.png`, `20b_concurrencia_reserva_b.png` y `21_verificacion_cupo_concurrente.png`. El tiempo de la consola durante esta prueba incluye la espera del bloqueo.

## 5. Pruebas de los controles complementarios

### T09 · Reparto de cupos entre grupos

Prepara una jornada con capacidad 40, cuota del 50 % y una reserva de 20 cupos. Así se puede probar el reparto sin modificar la jornada usada en T08.

```sql
SET @visita_p5 = (
    SELECT fecha_visita FROM reservas WHERE codigo_reserva = 'P5-RES-GA'
);
SET @inicio_cuota = (UTC_TIMESTAMP(6) - INTERVAL 5 HOUR) - INTERVAL 1 DAY;

START TRANSACTION;

INSERT INTO jornadas_sector (codigo_sector, fecha_visita, capacidad_personas)
VALUES ('SEC-004', @visita_p5, 40);

INSERT INTO limites_operador (
    codigo_operador, codigo_sector, fecha_visita, vigente_desde, porcentaje_maximo
)
VALUES ('OP-001', 'SEC-004', @visita_p5, @inicio_cuota, 50.00);

INSERT INTO reservas (
    codigo_reserva, codigo_operador, codigo_sector, fecha_visita, cupos_reservados
)
VALUES ('P5-RES-GRUPOS', 'OP-001', 'SEC-004', @visita_p5, 20);

COMMIT;

CALL sp_confirmar_reserva('P5-RES-GRUPOS');
CALL sp_guardar_grupo('P5-CAP-12', 'P5-RES-GRUPOS', 12);
CALL sp_guardar_grupo('P5-CAP-08', 'P5-RES-GRUPOS', 8);

SELECT COUNT(*) AS grupos,
       GROUP_CONCAT(visitantes_autorizados
                    ORDER BY visitantes_autorizados DESC SEPARATOR ' + ') AS reparto,
       SUM(visitantes_autorizados) AS total_autorizados
FROM grupos WHERE codigo_reserva = 'P5-RES-GRUPOS';
```

En otro envío, ejecuta `CALL sp_guardar_grupo('P5-CAP-01', 'P5-RES-GRUPOS', 1);`. Tras el rechazo, ejecuta estas dos llamadas y repite el conteo anterior.

```sql
CALL sp_guardar_grupo('P5-CAP-12', 'P5-RES-GRUPOS', 11);
CALL sp_guardar_grupo('P5-CAP-08', 'P5-RES-GRUPOS', 9);
```

**Observado:** se aceptó el reparto 12 + 8, se rechazó agregar el tercer grupo y se aceptó el ajuste a 11 + 9, manteniendo el total en 20. Evidencias 23 a 25.

### T10 · Reducción de capacidad

Ejecuta después de T09. Envía las llamadas incompatibles por separado y repite el `SET` si cambias de sesión.

```sql
SET @visita_p5 = (
    SELECT fecha_visita FROM reservas WHERE codigo_reserva = 'P5-RES-GRUPOS'
);

-- Espera un rechazo. El 50 % de 38 da 19 cupos.
CALL sp_cambiar_capacidad_jornada('SEC-004', @visita_p5, 38);

-- En otro envío, ambas llamadas deben aceptarse.
CALL sp_cambiar_capacidad_jornada('SEC-004', @visita_p5, 42);
CALL sp_cambiar_capacidad_jornada('SEC-004', @visita_p5, 40);

SELECT capacidad_personas,
       fn_cupos_asignables(capacidad_personas, 50.00) AS cuota_del_operador
FROM jornadas_sector
WHERE codigo_sector = 'SEC-004' AND fecha_visita = @visita_p5;
```

**Observado:** se rechazó la reducción a 38. Se aceptó subir a 42 y volver a 40. El resultado final mostró capacidad 40 y cuota 20, igual a los 20 cupos comprometidos. Evidencias 27 y 28.

### T11 · Publicación de cuota e historial

Ejecuta después de T10. Envía la prueba del 49 % por separado y repite el `SET` si cambias de sesión.

```sql
SET @visita_p5 = (
    SELECT fecha_visita FROM reservas WHERE codigo_reserva = 'P5-RES-GRUPOS'
);

-- Espera un rechazo. El 49 % de 40, redondeado hacia abajo, da 19 cupos.
CALL sp_publicar_limite_operador('OP-001', 'SEC-004', @visita_p5, 49.00);

-- En otro envío, publica el 55 % y confirma una reserva de dos cupos.
CALL sp_publicar_limite_operador('OP-001', 'SEC-004', @visita_p5, 55.00);

INSERT INTO reservas (
    codigo_reserva, codigo_operador, codigo_sector, fecha_visita, cupos_reservados
)
VALUES ('P5-RES-CUOTA-55', 'OP-001', 'SEC-004', @visita_p5, 2);

CALL sp_confirmar_reserva('P5-RES-CUOTA-55');

SELECT r.codigo_reserva, r.estado, r.cupos_reservados,
       l.porcentaje_maximo AS porcentaje_aplicado,
       l.vigente_hasta AS fin_de_la_version
FROM reservas AS r
JOIN limites_operador AS l
  ON l.codigo_operador = r.codigo_operador AND l.codigo_sector = r.codigo_sector
 AND l.fecha_visita = r.fecha_visita AND l.vigente_desde = r.limite_vigente_desde
WHERE r.codigo_reserva IN ('P5-RES-GRUPOS', 'P5-RES-CUOTA-55')
ORDER BY r.confirmada_en;
```

**Observado:** se rechazó el 49 %. La reserva anterior conservó el 50 % y su versión tiene fecha de cierre. La reserva nueva quedó confirmada con el 55 % y la nueva versión sigue abierta. Evidencias 30 y 31.

### T12 · Permiso concedido y denegado en taquilla

Como administrador, instala los roles con el archivo 32. Crea una cuenta local de prueba y sustituye el marcador por una contraseña que usarás solo en tu servidor.

```sql
CREATE USER 'p02_prueba_taquilla'@'localhost' IDENTIFIED BY 'TU_CLAVE_LOCAL';
GRANT p02_taquilla TO 'p02_prueba_taquilla'@'localhost';
SET DEFAULT ROLE p02_taquilla FOR 'p02_prueba_taquilla'@'localhost';
```

Abre otra conexión como la cuenta de prueba, por ejemplo con `mysql -u p02_prueba_taquilla -p p02_guias_cupos`. Ejecuta después de T04.

```sql
SELECT CURRENT_USER() AS cuenta, CURRENT_ROLE() AS rol;
SET @visita_p5 = (SELECT fecha_visita FROM reservas WHERE codigo_reserva = 'P5-RES-GB');
CALL sp_registrar_ingreso('P5-G-B', 'P5-ROL-01', TIMESTAMP(@visita_p5, '14:15:00'), 1);

-- La prueba de permiso intenta escribir el mismo valor de la fila.
UPDATE grupos
SET visitantes_autorizados = visitantes_autorizados
WHERE codigo_grupo = 'P5-G-B';
```

**Observado:** con la cuenta `p02_prueba_taquilla@localhost` y el rol `p02_taquilla`, la llamada al procedimiento terminó con `Query OK`. El `UPDATE` directo sobre grupos recibió el error 1142. Evidencias 32, 33 y 34. Los roles de acreditación y administración se configuraron, y sus pruebas con cuentas independientes quedaron como trabajo futuro.

## 6. Rendimiento

Ejecuta los tres bloques `EXPLAIN` al final de `16_consultas_validacion_mariadb.sql`, con los parámetros del mismo archivo y antes de añadir los datos `P5-`.

| Plan | Índice considerado | Acceso elegido en MariaDB | Filas estimadas | Evidencia |
|---|---|---|---:|---|
| P01 · Vencimiento de certificados | `ix_certificaciones_vencimiento` | Recorrido completo, con filtro y ordenamiento adicional. | 200 | `08_explain_p01_certificaciones.png` |
| P02 · Saldo de cupos | `ix_reservas_saldo` | Búsqueda mediante `ix_reservas_saldo`. | 1 | `09_explain_p02_saldo_cupos.png` |
| P03 · Entradas de un grupo | `ix_ingresos_cronologia` | Búsqueda mediante `ix_ingresos_cronologia`. | 2 | `10_explain_p03_entradas_grupo.png` |

Los valores de `rows` son estimaciones del optimizador. La prueba de dos sesiones comprueba el control de la cuota concurrente. Una evaluación de rendimiento bajo cargas mayores requeriría pruebas adicionales.
