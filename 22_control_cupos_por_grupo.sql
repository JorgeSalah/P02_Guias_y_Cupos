/*
  P02 · R02 · Control de autorizados por reserva
  Destino: MariaDB 10.4.32 · trabajo asistido por IA
  Estado: REVISADO ESTÁTICAMENTE · NO PROBADO EN SERVIDOR

  El procedimiento bloquea la reserva mientras calcula el total.
  Así, dos llamadas sobre la misma reserva comprueban los cupos por turno.
  Al actualizar un grupo, su cantidad anterior se excluye de la suma.
*/

USE p02_guias_cupos;

DELIMITER $$

CREATE PROCEDURE sp_guardar_grupo(
    IN p_codigo_grupo VARCHAR(32),
    IN p_codigo_reserva VARCHAR(32),
    IN p_autorizados INT UNSIGNED
)
SQL SECURITY DEFINER
COMMENT 'Crea un grupo o ajusta sus autorizados dentro de los cupos de su reserva'
BEGIN
    DECLARE v_cupos INT UNSIGNED DEFAULT NULL;
    DECLARE v_reserva_actual VARCHAR(32) DEFAULT NULL;
    DECLARE v_otros_autorizados DECIMAL(30,0);
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

    IF p_codigo_grupo IS NULL OR p_codigo_reserva IS NULL
       OR p_autorizados IS NULL OR p_autorizados = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Indique el grupo, la reserva y una cantidad positiva';
    END IF;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_transaccion_propia = TRUE;

    -- Esta fila coordina las escrituras de grupos de la misma reserva.
    SELECT r.cupos_reservados INTO v_cupos
    FROM reservas AS r
    WHERE r.codigo_reserva = p_codigo_reserva COLLATE utf8mb4_bin
    FOR UPDATE;

    IF v_cupos IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva indicada no existe';
    END IF;

    SELECT MAX(g.codigo_reserva) INTO v_reserva_actual
    FROM grupos AS g
    WHERE g.codigo_grupo = p_codigo_grupo COLLATE utf8mb4_bin;

    IF v_reserva_actual IS NOT NULL
       AND v_reserva_actual COLLATE utf8mb4_bin
           <> p_codigo_reserva COLLATE utf8mb4_bin THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El grupo ya pertenece a otra reserva';
    END IF;

    SELECT COALESCE(SUM(g.visitantes_autorizados), 0)
    INTO v_otros_autorizados
    FROM grupos AS g
    WHERE g.codigo_reserva = p_codigo_reserva COLLATE utf8mb4_bin
      AND g.codigo_grupo <> p_codigo_grupo COLLATE utf8mb4_bin;

    IF v_otros_autorizados + p_autorizados > v_cupos THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Los autorizados de los grupos superan los cupos de la reserva';
    END IF;

    IF v_reserva_actual IS NULL THEN
        INSERT INTO grupos (codigo_grupo, codigo_reserva, visitantes_autorizados)
        VALUES (p_codigo_grupo, p_codigo_reserva, p_autorizados);
    ELSE
        UPDATE grupos
        SET visitantes_autorizados = p_autorizados
        WHERE codigo_grupo = p_codigo_grupo COLLATE utf8mb4_bin;
    END IF;

    COMMIT;
END$$

DELIMITER ;

SHOW PROCEDURE STATUS
WHERE Db = 'p02_guias_cupos' AND Name = 'sp_guardar_grupo';