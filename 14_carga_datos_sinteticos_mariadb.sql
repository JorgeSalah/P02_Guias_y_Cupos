/*
  P02 · Carga sintética independiente
  SINTÉTICO — SOLO USO ACADÉMICO
  MariaDB 10.4.32 · Versión 0.5 · NO PROBADO EN SERVIDOR
  Destino: p02_guias_cupos con el DDL aprobado y las tablas vacías.
  Semilla fija: 17. Fechas e importes de cupo completamente ficticios.

  Las reservas y asignaciones históricas se cargan con fechas explícitas.
  La carga comprueba los datos resultantes. Las pruebas de los procedimientos
  y de concurrencia se ejecutarán por separado.
*/

USE p02_guias_cupos;

DELIMITER $$

BEGIN NOT ATOMIC
    DECLARE v_inicio DATE DEFAULT '2026-07-01';
    DECLARE v_semilla INT DEFAULT 17;
    DECLARE v_transaccion_propia BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_transaccion_propia THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF @@in_transaction = 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ejecute la carga en una sesión sin transacción activa';
    END IF;

    IF @@foreign_key_checks <> 1 OR @@check_constraint_checks <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La carga requiere claves foráneas y CHECK activos';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM INFORMATION_SCHEMA.TRIGGERS
        WHERE TRIGGER_SCHEMA = DATABASE()
          AND TRIGGER_NAME IN ('tr_asignaciones_bi_vigencia', 'tr_ingresos_ai_exceso')
    ) <> 2 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Instale los dos disparadores aprobados antes de cargar';
    END IF;

    START TRANSACTION;
    SET v_transaccion_propia = TRUE;

    IF EXISTS (SELECT 1 FROM guias)
       OR EXISTS (SELECT 1 FROM certificaciones)
       OR EXISTS (SELECT 1 FROM operadores)
       OR EXISTS (SELECT 1 FROM sectores)
       OR EXISTS (SELECT 1 FROM jornadas_sector)
       OR EXISTS (SELECT 1 FROM limites_operador)
       OR EXISTS (SELECT 1 FROM reservas)
       OR EXISTS (SELECT 1 FROM grupos)
       OR EXISTS (SELECT 1 FROM asignaciones_guia)
       OR EXISTS (SELECT 1 FROM ingresos)
       OR EXISTS (SELECT 1 FROM incidencias) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La carga requiere las once tablas vacías';
    END IF;

    -- Padres. Los códigos y denominaciones se generan para el ejercicio.
    INSERT INTO guias (codigo_guia)
    SELECT CONCAT('GUI-', LPAD(seq, 3, '0'))
    FROM seq_1_to_100;

    INSERT INTO operadores (codigo_operador, denominacion)
    SELECT CONCAT('OP-', LPAD(seq, 3, '0')),
           CONCAT('Operador sintético ', LPAD(seq, 3, '0'))
    FROM seq_1_to_50;

    INSERT INTO sectores (codigo_sector, nombre_sector)
    SELECT CONCAT('SEC-', LPAD(seq, 3, '0')),
           CONCAT('Sector sintético ', LPAD(seq, 3, '0'))
    FROM seq_1_to_50;

    -- Una certificación base y una histórica o próxima a vencer por guía.
    INSERT INTO certificaciones (
        codigo_guia, ref_certificacion, tipo, entidad_emisora,
        fecha_emision, fecha_vencimiento
    )
    SELECT codigo_guia, 'C-BASE', 'Acreditación base sintética',
           'Entidad emisora ficticia A', '2026-01-01', '2027-12-31'
    FROM guias;

    INSERT INTO certificaciones (
        codigo_guia, ref_certificacion, tipo, entidad_emisora,
        fecha_emision, fecha_vencimiento
    )
    SELECT CONCAT('GUI-', LPAD(seq, 3, '0')),
           CASE WHEN seq <= 50 THEN 'C-ANT' ELSE 'C-PROX' END,
           'Acreditación complementaria sintética', 'Entidad emisora ficticia B',
           CASE WHEN seq <= 50 THEN '2024-01-01' ELSE '2026-01-01' END,
           CASE
               WHEN seq <= 50 THEN '2025-12-31'
               ELSE DATE_ADD('2026-11-16', INTERVAL (MOD(seq + v_semilla, 15)) DAY)
           END
    FROM seq_1_to_100;

    -- 100 jornadas por sector. Cada capacidad sintética es de 80, 100 o 120.
    INSERT INTO jornadas_sector (codigo_sector, fecha_visita, capacidad_personas)
    SELECT s.codigo_sector,
           DATE_ADD(v_inicio, INTERVAL d.seq DAY),
           80 + 20 * MOD(CAST(RIGHT(s.codigo_sector, 3) AS UNSIGNED) + v_semilla, 3)
    FROM sectores AS s
    CROSS JOIN seq_0_to_99 AS d;

    -- Dos versiones sin solapamiento. La nueva inicia cuando termina la anterior.
    INSERT INTO limites_operador (
        codigo_operador, codigo_sector, fecha_visita,
        vigente_desde, vigente_hasta, porcentaje_maximo
    )
    SELECT CONCAT('OP-', LPAD(
               1 + MOD(CAST(RIGHT(j.codigo_sector, 3) AS UNSIGNED)
                       - 1 + DATEDIFF(j.fecha_visita, v_inicio) + v_semilla, 50),
               3, '0')),
           j.codigo_sector, j.fecha_visita,
           CASE WHEN v.seq = 1
                THEN TIMESTAMP(j.fecha_visita - INTERVAL 30 DAY, '00:00:00')
                ELSE TIMESTAMP(j.fecha_visita - INTERVAL 2 DAY, '00:00:00')
           END,
           CASE WHEN v.seq = 1
                THEN TIMESTAMP(j.fecha_visita - INTERVAL 2 DAY, '00:00:00')
                ELSE NULL
           END,
           CASE WHEN v.seq = 1 THEN 60.00
                ELSE 50.00 + 5.00 * MOD(CAST(RIGHT(j.codigo_sector, 3) AS UNSIGNED), 2)
           END
    FROM jornadas_sector AS j
    CROSS JOIN seq_1_to_2 AS v;

    -- Dos reservas por jornada. Las seleccionadas por residuo 1 de 20
    -- se confirmaron con la versión anterior. Las demás usan la versión nueva
    -- si tienen historial de confirmación.
    INSERT INTO reservas (
        codigo_reserva, codigo_operador, codigo_sector, fecha_visita,
        turno, cupos_reservados, estado, confirmada_en, limite_vigente_desde
    )
    SELECT CONCAT('R-', LPAD(x.n, 5, '0')),
           l.codigo_operador, x.codigo_sector, x.fecha_visita, 'Mañana', 20,
           CASE MOD(x.n, 10)
               WHEN 0 THEN 'pendiente'
               WHEN 2 THEN 'liberada'
               ELSE 'confirmada'
           END,
           CASE
               WHEN MOD(x.n, 10) = 0 THEN NULL
               WHEN MOD(x.n, 20) = 1
                   THEN TIMESTAMP(x.fecha_visita - INTERVAL 3 DAY, '10:00:00')
               ELSE TIMESTAMP(x.fecha_visita - INTERVAL 1 DAY, '10:00:00')
           END,
           CASE WHEN MOD(x.n, 10) = 0 THEN NULL ELSE l.vigente_desde END
    FROM (
        SELECT seq AS n,
               CONCAT('SEC-', LPAD(1 + MOD((seq - 1) DIV 2, 50), 3, '0')) AS codigo_sector,
               DATE_ADD(v_inicio, INTERVAL ((seq - 1) DIV 100) DAY) AS fecha_visita
        FROM seq_1_to_10000
    ) AS x
    JOIN limites_operador AS l
      ON l.codigo_sector = x.codigo_sector
     AND l.fecha_visita = x.fecha_visita
     AND (
            (MOD(x.n, 20) = 1 AND l.vigente_hasta IS NOT NULL)
         OR (MOD(x.n, 20) <> 1 AND l.vigente_hasta IS NULL)
     );

    -- Aun con dos grupos, el total autorizado queda dentro de los 20 cupos.
    INSERT INTO grupos (codigo_grupo, codigo_reserva, visitantes_autorizados)
    SELECT CONCAT('G1-', SUBSTRING(codigo_reserva, 3)),
           codigo_reserva,
           8 + MOD(CAST(SUBSTRING(codigo_reserva, 3) AS UNSIGNED), 5)
    FROM reservas
    WHERE estado = 'confirmada';

    INSERT INTO grupos (codigo_grupo, codigo_reserva, visitantes_autorizados)
    SELECT CONCAT('G2-', SUBSTRING(codigo_reserva, 3)), codigo_reserva, 5
    FROM reservas
    WHERE estado = 'confirmada'
      AND MOD(CAST(SUBSTRING(codigo_reserva, 3) AS UNSIGNED), 20) = 1;

    -- Cada guía conserva el mismo destino por día. Si atiende dos grupos,
    -- el primero termina a las 11:00 y el segundo empieza a esa hora.
    INSERT INTO asignaciones_guia (
        codigo_grupo, ref_asignacion, codigo_guia, ref_certificacion,
        registrada_en, aplica_desde, aplica_hasta
    )
    SELECT g.codigo_grupo, 'A-01',
           CONCAT('GUI-', LPAD(
               1 + MOD(CAST(SUBSTRING(r.codigo_reserva, 3) AS UNSIGNED) - 1, 100),
               3, '0')),
           'C-BASE',
           TIMESTAMP(r.fecha_visita - INTERVAL 1 DAY, '12:00:00'),
           TIMESTAMP(r.fecha_visita,
                     CASE WHEN LEFT(g.codigo_grupo, 2) = 'G1' THEN '08:00:00'
                          ELSE '11:00:00' END),
           TIMESTAMP(r.fecha_visita,
                     CASE WHEN LEFT(g.codigo_grupo, 2) = 'G1' THEN '11:00:00'
                          ELSE '14:00:00' END)
    FROM grupos AS g
    JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva;

    -- 8.500 primeras entradas. Ninguna supera por sí sola el autorizado.
    INSERT INTO ingresos (codigo_grupo, ref_ingreso, ingreso_en, personas_ingresadas)
    SELECT g.codigo_grupo, 'I-01',
           TIMESTAMP(r.fecha_visita,
                     CASE WHEN LEFT(g.codigo_grupo, 2) = 'G1' THEN '08:30:00'
                          ELSE '12:00:00' END),
           CASE
               WHEN LEFT(g.codigo_grupo, 2) = 'G2' THEN 4
               WHEN MOD(CAST(SUBSTRING(r.codigo_reserva, 3) AS UNSIGNED), 20)
                    IN (1, 3, 5) THEN 6
               ELSE g.visitantes_autorizados - 2
           END
    FROM grupos AS g
    JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva;

    -- 1.500 segundas entradas. 1.000 llegan exactamente al autorizado.
    -- Las otras 500 lo superan en una persona y activan el disparador.
    INSERT INTO ingresos (codigo_grupo, ref_ingreso, ingreso_en, personas_ingresadas)
    SELECT g.codigo_grupo, 'I-02', TIMESTAMP(r.fecha_visita, '09:00:00'),
           g.visitantes_autorizados - 6
           + CASE WHEN MOD(CAST(SUBSTRING(r.codigo_reserva, 3) AS UNSIGNED), 20) = 1
                  THEN 1 ELSE 0 END
    FROM grupos AS g
    JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva
    WHERE LEFT(g.codigo_grupo, 2) = 'G1'
      AND MOD(CAST(SUBSTRING(r.codigo_reserva, 3) AS UNSIGNED), 20) IN (1, 3, 5);

    -- Incidencias manuales. El cambio se registra como evento de taquilla.
    INSERT INTO incidencias (
        ref_incidencia, codigo_grupo, ocurrida_en, tipo,
        descripcion_general, ref_ingreso, ref_asignacion
    )
    SELECT CONCAT('CAMB-', SUBSTRING(r.codigo_reserva, 3)),
           g.codigo_grupo, TIMESTAMP(r.fecha_visita, '10:15:00'),
           'cambio_destino', 'Cambio de destino reportado en la simulación de taquilla',
           NULL, 'A-01'
    FROM grupos AS g
    JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva
    WHERE LEFT(g.codigo_grupo, 2) = 'G1'
      AND MOD(CAST(SUBSTRING(r.codigo_reserva, 3) AS UNSIGNED), 20) = 1;

    -- Comprobación de las tablas centrales y del efecto del disparador.
    IF (SELECT COUNT(*) FROM reservas) <> 10000
       OR (SELECT COUNT(*) FROM ingresos) <> 10000
       OR (SELECT COUNT(*) FROM grupos) <> 8500
       OR (SELECT COUNT(*) FROM incidencias WHERE tipo = 'exceso_personas') <> 500
       OR (SELECT COUNT(*) FROM incidencias WHERE tipo = 'cambio_destino') <> 500 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Los conteos centrales no coinciden con el plan sintético';
    END IF;

    COMMIT;
END$$

DELIMITER ;