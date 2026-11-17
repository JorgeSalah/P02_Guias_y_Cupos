/*
  P02 · R04 / RN03 · Publicación de cuotas
  MariaDB 10.4.32 · Trabajo asistido por IA
  Estado: REVISADO ESTÁTICAMENTE · PENDIENTE DE PRUEBA EN SERVIDOR

  Agrega sp_publicar_limite_operador y actualiza sp_confirmar_reserva.
  Ambas rutinas bloquean la misma jornada y evalúan la vigencia
  usando la hora efectiva después de obtener el bloqueo.
*/

USE p02_guias_cupos;

DELIMITER $$

CREATE OR REPLACE PROCEDURE sp_confirmar_reserva(IN p_reserva VARCHAR(32))
SQL SECURITY DEFINER
COMMENT 'Confirma una reserva pendiente con la cuota vigente tras bloquear la jornada'
BEGIN
    DECLARE v_operador VARCHAR(32);
    DECLARE v_sector VARCHAR(32);
    DECLARE v_fecha DATE;
    DECLARE v_capacidad INT UNSIGNED DEFAULT NULL;
    DECLARE v_cupos INT UNSIGNED DEFAULT NULL;
    DECLARE v_confirmacion DATETIME(6);
    DECLARE v_inicio DATETIME(6);
    DECLARE v_porcentaje DECIMAL(5,2);
    DECLARE v_versiones INT;
    DECLARE v_comprometidos DECIMAL(30,0);
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
            SET MESSAGE_TEXT = 'Llame al procedimiento fuera de una transacción';
    END IF;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_transaccion_propia = TRUE;

    SELECT MAX(codigo_operador), MAX(codigo_sector), MAX(fecha_visita)
    INTO v_operador, v_sector, v_fecha
    FROM reservas
    WHERE codigo_reserva = p_reserva COLLATE utf8mb4_bin;

    IF v_fecha IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reserva inexistente';
    END IF;

    SELECT capacidad_personas INTO v_capacidad
    FROM jornadas_sector
    WHERE codigo_sector = v_sector COLLATE utf8mb4_bin
      AND fecha_visita = v_fecha
    FOR UPDATE;

    SELECT cupos_reservados INTO v_cupos
    FROM reservas
    WHERE codigo_reserva = p_reserva COLLATE utf8mb4_bin
      AND codigo_operador = v_operador COLLATE utf8mb4_bin
      AND codigo_sector = v_sector COLLATE utf8mb4_bin
      AND fecha_visita = v_fecha
      AND estado = 'pendiente'
    FOR UPDATE;

    IF v_capacidad IS NULL OR v_cupos IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva ya no está pendiente o cambió de jornada';
    END IF;

    -- Hora de Colombia en el momento de la comprobación, tras cualquier espera.
    SET v_confirmacion = TIMESTAMPADD(
        MICROSECOND,
        TIMESTAMPDIFF(MICROSECOND, NOW(6), SYSDATE(6)),
        UTC_TIMESTAMP(6)
    ) - INTERVAL 5 HOUR;

    SELECT COUNT(*), MAX(vigente_desde), MAX(porcentaje_maximo)
    INTO v_versiones, v_inicio, v_porcentaje
    FROM limites_operador
    WHERE codigo_operador = v_operador COLLATE utf8mb4_bin
      AND codigo_sector = v_sector COLLATE utf8mb4_bin
      AND fecha_visita = v_fecha
      AND vigente_desde <= v_confirmacion
      AND (vigente_hasta IS NULL OR v_confirmacion < vigente_hasta);

    IF v_versiones <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Se requiere un único límite vigente';
    END IF;

    SELECT COALESCE(SUM(cupos_reservados), 0) INTO v_comprometidos
    FROM reservas
    WHERE codigo_operador = v_operador COLLATE utf8mb4_bin
      AND codigo_sector = v_sector COLLATE utf8mb4_bin
      AND fecha_visita = v_fecha
      AND estado = 'confirmada';

    IF v_comprometidos + v_cupos > fn_cupos_asignables(v_capacidad, v_porcentaje) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva supera el cupo disponible del operador';
    END IF;

    UPDATE reservas
    SET estado = 'confirmada',
        confirmada_en = v_confirmacion,
        limite_vigente_desde = v_inicio
    WHERE codigo_reserva = p_reserva COLLATE utf8mb4_bin;

    COMMIT;
END$$


CREATE PROCEDURE sp_publicar_limite_operador(
    IN p_operador VARCHAR(32),
    IN p_sector VARCHAR(32),
    IN p_fecha DATE,
    IN p_porcentaje DECIMAL(5,2)
)
SQL SECURITY DEFINER
COMMENT 'Publica una cuota inmediata sin solapar versiones ni exceder cupos comprometidos'
BEGIN
    DECLARE v_capacidad INT UNSIGNED DEFAULT NULL;
    DECLARE v_corte DATETIME(6);
    DECLARE v_inicio_anterior DATETIME(6);
    DECLARE v_versiones_activas INT;
    DECLARE v_comprometidos DECIMAL(30,0);
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
            SET MESSAGE_TEXT = 'Llame al procedimiento fuera de una transacción';
    END IF;

    IF p_operador IS NULL OR p_sector IS NULL OR p_fecha IS NULL
       OR p_porcentaje IS NULL OR p_porcentaje NOT BETWEEN 0.00 AND 100.00 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Indique operador, sector, fecha y un porcentaje entre 0 y 100';
    END IF;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_transaccion_propia = TRUE;

    SELECT capacidad_personas INTO v_capacidad
    FROM jornadas_sector
    WHERE codigo_sector = p_sector COLLATE utf8mb4_bin
      AND fecha_visita = p_fecha
    FOR UPDATE;

    IF v_capacidad IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La jornada indicada no existe';
    END IF;

    SET v_corte = TIMESTAMPADD(
        MICROSECOND,
        TIMESTAMPDIFF(MICROSECOND, NOW(6), SYSDATE(6)),
        UTC_TIMESTAMP(6)
    ) - INTERVAL 5 HOUR;

    SELECT COUNT(*), MAX(vigente_desde)
    INTO v_versiones_activas, v_inicio_anterior
    FROM limites_operador
    WHERE codigo_operador = p_operador COLLATE utf8mb4_bin
      AND codigo_sector = p_sector COLLATE utf8mb4_bin
      AND fecha_visita = p_fecha
      AND vigente_desde <= v_corte
      AND (vigente_hasta IS NULL OR v_corte < vigente_hasta);

    -- La versión nueva queda abierta. Una vigencia futura la solaparía.
    IF v_versiones_activas > 1 OR EXISTS (
        SELECT 1
        FROM limites_operador
        WHERE codigo_operador = p_operador COLLATE utf8mb4_bin
          AND codigo_sector = p_sector COLLATE utf8mb4_bin
          AND fecha_visita = p_fecha
          AND vigente_desde > v_corte
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La nueva cuota se solaparía con otra vigencia';
    END IF;

    SELECT COALESCE(SUM(cupos_reservados), 0) INTO v_comprometidos
    FROM reservas
    WHERE codigo_operador = p_operador COLLATE utf8mb4_bin
      AND codigo_sector = p_sector COLLATE utf8mb4_bin
      AND fecha_visita = p_fecha
      AND estado = 'confirmada';

    IF v_comprometidos > fn_cupos_asignables(v_capacidad, p_porcentaje) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La nueva cuota es menor que los cupos ya comprometidos';
    END IF;

    IF v_inicio_anterior IS NOT NULL THEN
        -- El cierre es exclusivo. Conserva válidas las referencias históricas.
        IF v_corte <= v_inicio_anterior OR EXISTS (
            SELECT 1
            FROM reservas
            WHERE codigo_operador = p_operador COLLATE utf8mb4_bin
              AND codigo_sector = p_sector COLLATE utf8mb4_bin
              AND fecha_visita = p_fecha
              AND limite_vigente_desde = v_inicio_anterior
              AND confirmada_en >= v_corte
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'No es posible cerrar la vigencia sin afectar el historial';
        END IF;

        UPDATE limites_operador
        SET vigente_hasta = v_corte
        WHERE codigo_operador = p_operador COLLATE utf8mb4_bin
          AND codigo_sector = p_sector COLLATE utf8mb4_bin
          AND fecha_visita = p_fecha
          AND vigente_desde = v_inicio_anterior;
    END IF;

    INSERT INTO limites_operador (
        codigo_operador, codigo_sector, fecha_visita,
        vigente_desde, vigente_hasta, porcentaje_maximo
    )
    VALUES (p_operador, p_sector, p_fecha, v_corte, NULL, p_porcentaje);

    COMMIT;
END$$

DELIMITER ;

SHOW PROCEDURE STATUS
WHERE Db = 'p02_guias_cupos'
  AND Name IN ('sp_confirmar_reserva', 'sp_publicar_limite_operador');