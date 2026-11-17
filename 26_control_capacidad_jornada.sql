/*
  P02 · RN03 · Control de cambios de capacidad
  MariaDB 10.4.32 · Trabajo asistido por IA
  Estado: REVISADO ESTÁTICAMENTE · PENDIENTE DE PRUEBA EN SERVIDOR

  Usa el mismo bloqueo de jornada que sp_confirmar_reserva.
  Comprueba las reservas confirmadas por operador antes de reducir el aforo.
*/

USE p02_guias_cupos;

DELIMITER $$

CREATE PROCEDURE sp_cambiar_capacidad_jornada(
    IN p_sector VARCHAR(32),
    IN p_fecha DATE,
    IN p_capacidad_nueva INT UNSIGNED
)
SQL SECURITY DEFINER
COMMENT 'Cambia la capacidad de una jornada respetando los cupos comprometidos'
BEGIN
    DECLARE v_capacidad_actual INT UNSIGNED DEFAULT NULL;
    DECLARE v_corte DATETIME(6);
    DECLARE v_conflictos INT;
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
            SET MESSAGE_TEXT = 'Ejecute el procedimiento fuera de una transacción';
    END IF;

    IF p_sector IS NULL OR p_fecha IS NULL OR p_capacidad_nueva IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Indique sector, fecha y capacidad nueva';
    END IF;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_transaccion_propia = TRUE;

    SELECT j.capacidad_personas INTO v_capacidad_actual
    FROM jornadas_sector AS j
    WHERE j.codigo_sector = p_sector COLLATE utf8mb4_bin
      AND j.fecha_visita = p_fecha
    FOR UPDATE;

    IF v_capacidad_actual IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La jornada indicada no existe';
    END IF;

    IF p_capacidad_nueva < v_capacidad_actual THEN
        -- Ancla UTC de la llamada más el tiempo transcurrido hasta el bloqueo.
        -- El resultado se expresa en hora de Colombia, UTC-05:00.
        SET v_corte = TIMESTAMPADD(
            MICROSECOND,
            TIMESTAMPDIFF(MICROSECOND, NOW(6), SYSDATE(6)),
            UTC_TIMESTAMP(6)
        ) - INTERVAL 5 HOUR;

        SELECT COUNT(*) INTO v_conflictos
        FROM (
            SELECT r.codigo_operador,
                   SUM(r.cupos_reservados) AS cupos_comprometidos
            FROM reservas AS r
            WHERE r.codigo_sector = p_sector COLLATE utf8mb4_bin
              AND r.fecha_visita = p_fecha
              AND r.estado = 'confirmada'
            GROUP BY r.codigo_operador
        ) AS saldo
        WHERE (
            SELECT COUNT(*)
            FROM limites_operador AS l
            WHERE l.codigo_operador = saldo.codigo_operador
              AND l.codigo_sector = p_sector COLLATE utf8mb4_bin
              AND l.fecha_visita = p_fecha
              AND l.vigente_desde <= v_corte
              AND (l.vigente_hasta IS NULL OR v_corte < l.vigente_hasta)
        ) <> 1
        OR EXISTS (
            SELECT 1
            FROM limites_operador AS l
            WHERE l.codigo_operador = saldo.codigo_operador
              AND l.codigo_sector = p_sector COLLATE utf8mb4_bin
              AND l.fecha_visita = p_fecha
              AND (l.vigente_hasta IS NULL OR v_corte < l.vigente_hasta)
              AND saldo.cupos_comprometidos >
                  fn_cupos_asignables(p_capacidad_nueva, l.porcentaje_maximo)
        );

        IF v_conflictos > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'La capacidad nueva es incompatible con las cuotas y reservas confirmadas';
        END IF;
    END IF;

    UPDATE jornadas_sector
    SET capacidad_personas = p_capacidad_nueva
    WHERE codigo_sector = p_sector COLLATE utf8mb4_bin
      AND fecha_visita = p_fecha;

    COMMIT;
END$$

DELIMITER ;

SHOW PROCEDURE STATUS
WHERE Db = 'p02_guias_cupos' AND Name = 'sp_cambiar_capacidad_jornada';