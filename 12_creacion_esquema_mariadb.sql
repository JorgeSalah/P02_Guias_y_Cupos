/*
  P02 · Guías y operadores: acreditación y cupos
  Versión documental 0.4 · Noviembre de 2026
  Autoría: trabajo asistido por IA
  Destino: MariaDB 10.4.32 · p02_guias_cupos
  Estado: REVISADO ESTÁTICAMENTE · NO PROBADO EN SERVIDOR

  Fuente funcional: enunciado P02 y Fases 1–3 aprobadas.
  Inventario: 11 tablas, 3 vistas, 1 función, 3 procedimientos y 2 disparadores.
  Orden: tablas maestras, tablas dependientes, función, disparadores,
  procedimientos y vistas.

  Los códigos se suministran al registrar filas y se comparan con
  utf8mb4_bin. Las fechas de visita son días locales de Colombia.
  Los DATETIME(6) representan instantes en hora local de Colombia.
  Los campos opcionales llevan DEFAULT NULL según su significado.
  Toda FK aplica RESTRICT en borrado y actualización de la clave padre
  para proteger las referencias históricas.
  Privacidad: usar códigos ficticios, cantidades agregadas y descripciones
  generales sin nombres ni documentos de visitantes.
  Este archivo crea un esquema vacío. Los cuerpos de rutinas se ejecutan
  al invocar la rutina o activar el disparador correspondiente.
*/

USE p02_guias_cupos;

CREATE TABLE guias (
    codigo_guia VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Código ficticio estable del guía usado para vincular acreditaciones',
    -- PK: un registro por código de guía. R01.
    PRIMARY KEY (codigo_guia)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Guías que pueden recibir asignaciones a grupos. R01 y R03';

CREATE TABLE operadores (
    codigo_operador VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Código ficticio para asociar al operador con sus límites y reservas',
    denominacion VARCHAR(120) NOT NULL
        COMMENT 'Denominación ficticia legible para los reportes de operadores',
    -- PK: separa la identidad del operador de su denominación. R02 y R04.
    PRIMARY KEY (codigo_operador)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Operadores turísticos a los que se asignan cupos. R02 y R04';

CREATE TABLE sectores (
    codigo_sector VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Código estable del destino usado para controlar cupos y asignaciones',
    nombre_sector VARCHAR(100) NOT NULL
        COMMENT 'Nombre descriptivo del destino para identificarlo en reportes',
    -- PK: distingue destinos aunque tengan nombres parecidos. RN02 y RN03.
    PRIMARY KEY (codigo_sector)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Destinos en los que se programan visitas. R02 y R06';

CREATE TABLE certificaciones (
    codigo_guia VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Guía titular del certificado. Forma parte de su identificación',
    ref_certificacion VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Referencia interna que distingue certificados del mismo guía',
    tipo VARCHAR(80) NOT NULL
        COMMENT 'Clase de acreditación que consta en el certificado',
    entidad_emisora VARCHAR(150) NOT NULL
        COMMENT 'Denominación del organismo que expidió la acreditación',
    fecha_emision DATE NOT NULL
        COMMENT 'Primer día de vigencia documental de la certificación',
    fecha_vencimiento DATE NOT NULL
        COMMENT 'Último día válido de la certificación según el criterio aprobado',
    -- PK: la referencia se interpreta dentro de cada guía. R01.
    PRIMARY KEY (codigo_guia, ref_certificacion),
    -- FK: conserva la relación del certificado con su titular.
    CONSTRAINT fk_certificaciones_guia FOREIGN KEY (codigo_guia)
        REFERENCES guias (codigo_guia) ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- CHECK: evita un vencimiento anterior a la emisión. RN01.
    CONSTRAINT ck_certificaciones_fechas
        CHECK (fecha_emision <= fecha_vencimiento),
    -- Índice: búsqueda por rangos de vencimiento y recuperación del guía. R07.
    KEY ix_certificaciones_vencimiento (fecha_vencimiento, codigo_guia)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Historial de acreditaciones por guía. R01, R07 y RN01';

CREATE TABLE jornadas_sector (
    codigo_sector VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Sector cuya capacidad se configura para el día de visita',
    fecha_visita DATE NOT NULL
        COMMENT 'Día local de visita que delimita el control diario de cupos',
    capacidad_personas INT UNSIGNED NOT NULL
        COMMENT 'Capacidad base de la jornada en personas. Cero indica ausencia de cupos',
    -- PK: una capacidad base por sector y fecha. R06.
    PRIMARY KEY (codigo_sector, fecha_visita),
    -- FK: una jornada debe corresponder a un sector registrado.
    CONSTRAINT fk_jornadas_sector FOREIGN KEY (codigo_sector)
        REFERENCES sectores (codigo_sector) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Capacidad diaria por sector y punto de coordinación transaccional. R06 y RN03';

CREATE TABLE limites_operador (
    codigo_operador VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Operador al que corresponde el porcentaje de cupos',
    codigo_sector VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Sector de la jornada a la que se aplica este parámetro',
    fecha_visita DATE NOT NULL
        COMMENT 'Día de visita al que se aplica el parámetro',
    vigente_desde DATETIME(6) NOT NULL
        COMMENT 'Inicio inclusivo de la vigencia administrativa en hora local',
    vigente_hasta DATETIME(6) NULL DEFAULT NULL
        COMMENT 'Fin exclusivo de la vigencia en hora local. NULL indica intervalo abierto',
    porcentaje_maximo DECIMAL(5,2) NOT NULL
        COMMENT 'Máximo asignable expresado en porcentaje de 0.00 a 100.00',
    -- PK: conserva versiones distintas para el mismo operador y jornada. R04.
    PRIMARY KEY (codigo_operador, codigo_sector, fecha_visita, vigente_desde),
    -- Índice de soporte para la FK a la jornada.
    KEY ix_limites_jornada (codigo_sector, fecha_visita),
    -- FK: identifica al titular de la cuota.
    CONSTRAINT fk_limites_operador FOREIGN KEY (codigo_operador)
        REFERENCES operadores (codigo_operador) ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- FK: identifica la capacidad base de la cuota.
    CONSTRAINT fk_limites_jornada FOREIGN KEY (codigo_sector, fecha_visita)
        REFERENCES jornadas_sector (codigo_sector, fecha_visita)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- CHECK: valida el sentido del intervalo. El solapamiento es una regla entre filas.
    CONSTRAINT ck_limites_intervalo
        CHECK (vigente_hasta IS NULL OR vigente_hasta > vigente_desde),
    -- CHECK: el parámetro representa un porcentaje, no una fracción.
    CONSTRAINT ck_limites_porcentaje CHECK (porcentaje_maximo BETWEEN 0.00 AND 100.00)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Versiones del porcentaje máximo de un operador por sector y fecha. R04 y RN03';

CREATE TABLE reservas (
    codigo_reserva VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Código estable de la operación que compromete cupos del operador',
    codigo_operador VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Operador al que se le contabilizan los cupos de la reserva',
    codigo_sector VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Destino programado de los grupos incluidos en la reserva',
    fecha_visita DATE NOT NULL
        COMMENT 'Día de visita contra el que se controla el cupo',
    turno VARCHAR(30) NULL DEFAULT NULL
        COMMENT 'Horario descriptivo dentro del día. NULL indica que no se especificó turno',
    cupos_reservados INT UNSIGNED NOT NULL
        COMMENT 'Cantidad de personas de la reserva. Consume cupo cuando está confirmada',
    estado VARCHAR(12) COLLATE utf8mb4_bin NOT NULL DEFAULT 'pendiente'
        COMMENT 'Pendiente al crear. Confirmada consume cupos y liberada conserva historial',
    confirmada_en DATETIME(6) NULL DEFAULT NULL
        COMMENT 'Instante local de confirmación. NULL mientras la reserva esté pendiente',
    limite_vigente_desde DATETIME(6) NULL DEFAULT NULL
        COMMENT 'Inicio de vigencia de la versión aplicada. NULL mientras esté pendiente',
    -- PK: la reserva se suma una sola vez aunque cubra varios grupos. R02 y R09.
    PRIMARY KEY (codigo_reserva),
    -- Índices de soporte para las FK de la jornada y de la versión de cuota.
    -- El prefijo del segundo también cubre la FK del operador.
    KEY ix_reservas_jornada (codigo_sector, fecha_visita),
    KEY ix_reservas_limite (codigo_operador, codigo_sector, fecha_visita, limite_vigente_desde),
    -- Índice: saldo comprometido durante la confirmación. RN03.
    KEY ix_reservas_saldo (codigo_operador, codigo_sector, fecha_visita, estado),
    -- Índice: reportes diarios de varios operadores o sectores. R09.
    KEY ix_reservas_reporte_diario (fecha_visita, codigo_sector, codigo_operador),
    -- FK: operador válido aun cuando todavía no se aplique un límite.
    CONSTRAINT fk_reservas_operador FOREIGN KEY (codigo_operador)
        REFERENCES operadores (codigo_operador) ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- FK: jornada válida aun cuando la reserva esté pendiente.
    CONSTRAINT fk_reservas_jornada FOREIGN KEY (codigo_sector, fecha_visita)
        REFERENCES jornadas_sector (codigo_sector, fecha_visita)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- FK: impide aplicar la versión de otro operador, sector o fecha.
    CONSTRAINT fk_reservas_limite
        FOREIGN KEY (codigo_operador, codigo_sector, fecha_visita, limite_vigente_desde)
        REFERENCES limites_operador (codigo_operador, codigo_sector, fecha_visita, vigente_desde)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- CHECK: toda reserva representa una cantidad positiva de personas.
    CONSTRAINT ck_reservas_cupos CHECK (cupos_reservados > 0),
    -- CHECK: valida el dominio de estado y la presencia de su historial de confirmación.
    CONSTRAINT ck_reservas_estado_confirmacion CHECK (
        (estado = 'pendiente' AND confirmada_en IS NULL AND limite_vigente_desde IS NULL)
        OR
        (estado IN ('confirmada', 'liberada')
         AND confirmada_en IS NOT NULL AND limite_vigente_desde IS NOT NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Reservas de cupos por operador y jornada con historial de confirmación. R02 y RN03';

CREATE TABLE grupos (
    codigo_grupo VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Código ficticio del grupo usado en asignaciones e ingresos',
    codigo_reserva VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Reserva de la que el grupo obtiene operador y jornada',
    visitantes_autorizados INT UNSIGNED NOT NULL
        COMMENT 'Cantidad de personas autorizadas para este grupo en taquilla',
    -- PK: cada grupo es una unidad de control de acceso. R05 y RN04.
    PRIMARY KEY (codigo_grupo),
    -- Índice: FK y recuperación de todos los grupos cubiertos por una reserva.
    KEY ix_grupos_reserva (codigo_reserva),
    -- FK: vincula cada grupo a una sola reserva registrada.
    CONSTRAINT fk_grupos_reserva FOREIGN KEY (codigo_reserva)
        REFERENCES reservas (codigo_reserva) ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- CHECK: una autorización representa al menos una persona.
    CONSTRAINT ck_grupos_autorizados CHECK (visitantes_autorizados > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Grupos de visitantes y cantidad autorizada para acceder. R02, R05 y RN04';

CREATE TABLE asignaciones_guia (
    codigo_grupo VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Grupo al que corresponde la asignación histórica',
    ref_asignacion VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Referencia que distingue las asignaciones de un mismo grupo',
    codigo_guia VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Guía asignado y titular del certificado usado como respaldo',
    ref_certificacion VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Referencia del certificado dentro del historial de ese guía',
    registrada_en DATETIME(6) NOT NULL
        COMMENT 'Instante local de registro usado para verificar la acreditación',
    aplica_desde DATETIME(6) NOT NULL
        COMMENT 'Inicio inclusivo del período en que el guía atiende al grupo',
    aplica_hasta DATETIME(6) NULL DEFAULT NULL
        COMMENT 'Fin exclusivo del período. NULL indica asignación sin fin registrado',
    -- PK: preserva varias asignaciones en el historial de un grupo. R03 y R10.
    PRIMARY KEY (codigo_grupo, ref_asignacion),
    -- Índice: FK al certificado y búsqueda de asignaciones de un guía.
    KEY ix_asignaciones_certificacion (codigo_guia, ref_certificacion),
    -- FK: identifica el grupo de la asignación.
    CONSTRAINT fk_asignaciones_grupo FOREIGN KEY (codigo_grupo)
        REFERENCES grupos (codigo_grupo) ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- FK: exige que el certificado pertenezca al mismo guía de la asignación.
    CONSTRAINT fk_asignaciones_certificacion FOREIGN KEY (codigo_guia, ref_certificacion)
        REFERENCES certificaciones (codigo_guia, ref_certificacion)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- CHECK: evita intervalos vacíos o invertidos.
    CONSTRAINT ck_asignaciones_intervalo
        CHECK (aplica_hasta IS NULL OR aplica_hasta > aplica_desde)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Historial de guías asignados con certificado de respaldo. R03, RN01 y RN02';

CREATE TABLE ingresos (
    codigo_grupo VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Grupo cuya entrada parcial o total se está registrando',
    ref_ingreso VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Referencia de la entrada dentro del conjunto de ingresos del grupo',
    ingreso_en DATETIME(6) NOT NULL
        COMMENT 'Instante local de la entrada efectiva observada en taquilla',
    personas_ingresadas INT UNSIGNED NOT NULL
        COMMENT 'Personas que entraron en este evento. El acumulado se obtiene por suma',
    -- PK: separa las entradas sucesivas del mismo grupo. R05 y R08.
    PRIMARY KEY (codigo_grupo, ref_ingreso),
    -- Índice: recupera entradas del grupo en orden cronológico.
    KEY ix_ingresos_cronologia (codigo_grupo, ingreso_en, ref_ingreso),
    -- FK: toda entrada debe corresponder a un grupo registrado.
    CONSTRAINT fk_ingresos_grupo FOREIGN KEY (codigo_grupo)
        REFERENCES grupos (codigo_grupo) ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- CHECK: un ingreso efectivo representa al menos una persona.
    CONSTRAINT ck_ingresos_personas CHECK (personas_ingresadas > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Entradas efectivas por grupo y evento. R05, R08 y RN04';

CREATE TABLE incidencias (
    ref_incidencia VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Referencia global de la incidencia dentro del ejercicio',
    codigo_grupo VARCHAR(32) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Grupo en el que ocurrió el exceso o el cambio de destino',
    ocurrida_en DATETIME(6) NOT NULL
        COMMENT 'Instante local del evento usado para reconstruir el contexto',
    tipo VARCHAR(24) COLLATE utf8mb4_bin NOT NULL
        COMMENT 'Clase de evento: exceso_personas o cambio_destino',
    descripcion_general VARCHAR(500) NOT NULL
        COMMENT 'Descripción operativa en texto general sin datos personales de visitantes',
    ref_ingreso VARCHAR(32) COLLATE utf8mb4_bin NULL DEFAULT NULL
        COMMENT 'Entrada de origen del exceso. NULL para un cambio de destino',
    ref_asignacion VARCHAR(32) COLLATE utf8mb4_bin NULL DEFAULT NULL
        COMMENT 'Asignación aplicable al ocurrir el evento. NULL si no se vinculó una',
    -- PK: identifica cada evento documentado. R05 y R10.
    PRIMARY KEY (ref_incidencia),
    -- UNIQUE: un ingreso vinculado puede originar un solo exceso.
    -- Las filas con referencia NULL pueden registrar cambios independientes.
    UNIQUE KEY uq_incidencias_ingreso (codigo_grupo, ref_ingreso),
    -- Índice: soporte para la FK a la asignación del mismo grupo.
    KEY ix_incidencias_asignacion (codigo_grupo, ref_asignacion),
    -- FK: preserva el grupo también cuando no hay ingreso de origen.
    CONSTRAINT fk_incidencias_grupo FOREIGN KEY (codigo_grupo)
        REFERENCES grupos (codigo_grupo) ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- FK: el ingreso de origen debe pertenecer al grupo de la incidencia.
    CONSTRAINT fk_incidencias_ingreso FOREIGN KEY (codigo_grupo, ref_ingreso)
        REFERENCES ingresos (codigo_grupo, ref_ingreso)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- FK: la asignación vinculada debe pertenecer al mismo grupo.
    CONSTRAINT fk_incidencias_asignacion FOREIGN KEY (codigo_grupo, ref_asignacion)
        REFERENCES asignaciones_guia (codigo_grupo, ref_asignacion)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- CHECK: valida el tipo y reserva el vínculo al ingreso para el exceso.
    CONSTRAINT ck_incidencias_tipo_origen CHECK (
        (tipo = 'exceso_personas' AND ref_ingreso IS NOT NULL)
        OR (tipo = 'cambio_destino' AND ref_ingreso IS NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Incidencias de acceso con vínculo al grupo y contexto histórico. R05, R10 y RN04';


DELIMITER $$

-- FN · R06/RN03. Entradas: capacidad en personas y porcentaje en escala 0–100.
-- Salida: cupos enteros mediante redondeo hacia abajo.
CREATE FUNCTION fn_cupos_asignables(
    p_capacidad INT UNSIGNED, p_porcentaje DECIMAL(5,2)
)
RETURNS INT UNSIGNED
DETERMINISTIC NO SQL
COMMENT 'Calcula el máximo entero de cupos mediante redondeo hacia abajo'
BEGIN
    IF p_capacidad IS NULL OR p_porcentaje IS NULL
       OR p_porcentaje < 0 OR p_porcentaje > 100 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Capacidad o porcentaje inválido';
    END IF;

    RETURN FLOOR(p_capacidad * p_porcentaje * 0.01);
END$$

-- TR · RN01. Valida ambas fechas contra el certificado del guía.
-- El vencimiento es inclusivo. La regla de destinos pertenece al procedimiento.
CREATE TRIGGER tr_asignaciones_bi_vigencia
BEFORE INSERT ON asignaciones_guia
FOR EACH ROW
BEGIN
    DECLARE v_certificados_validos INT;

    SELECT COUNT(*) INTO v_certificados_validos
    FROM certificaciones AS c
    JOIN grupos AS g ON g.codigo_grupo = NEW.codigo_grupo
    JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva
    WHERE c.codigo_guia = NEW.codigo_guia
      AND c.ref_certificacion = NEW.ref_certificacion
      AND DATE(NEW.registrada_en) BETWEEN c.fecha_emision AND c.fecha_vencimiento
      AND r.fecha_visita BETWEEN c.fecha_emision AND c.fecha_vencimiento;

    IF v_certificados_validos = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La certificación no cubre el registro y la fecha de visita';
    END IF;
END$$

-- TR · RN04. Suma las entradas efectivas, incluida NEW.
-- Si la entrada deja el acumulado por encima de lo autorizado,
-- registra el exceso y la asignación aplicable en el instante de ingreso.
-- La referencia sintética de la incidencia automática se genera con UUID.
CREATE TRIGGER tr_ingresos_ai_exceso
AFTER INSERT ON ingresos
FOR EACH ROW
BEGIN
    DECLARE v_autorizados INT UNSIGNED;
    DECLARE v_ingresados DECIMAL(30,0);
    DECLARE v_asignacion VARCHAR(32);

    SELECT visitantes_autorizados INTO v_autorizados
    FROM grupos WHERE codigo_grupo = NEW.codigo_grupo;

    SELECT COALESCE(SUM(personas_ingresadas), 0) INTO v_ingresados
    FROM ingresos WHERE codigo_grupo = NEW.codigo_grupo;

    IF v_ingresados > v_autorizados THEN
        SELECT MAX(a.ref_asignacion) INTO v_asignacion
        FROM asignaciones_guia AS a
        WHERE a.codigo_grupo = NEW.codigo_grupo
          AND a.aplica_desde <= NEW.ingreso_en
          AND (a.aplica_hasta IS NULL OR NEW.ingreso_en < a.aplica_hasta);

        INSERT INTO incidencias (
            ref_incidencia, codigo_grupo, ocurrida_en, tipo,
            descripcion_general, ref_ingreso, ref_asignacion
        ) VALUES (
            REPLACE(UUID(), '-', ''), NEW.codigo_grupo, NEW.ingreso_en, 'exceso_personas',
            CONCAT('Acumulado ingresado: ', v_ingresados,
                   '. Autorizados: ', v_autorizados, '.'),
            NEW.ref_ingreso, v_asignacion
        );
    END IF;
END$$

-- PR · RN03. Entrada: código de una reserva pendiente.
-- Bloquea la jornada y comprueba la versión de cuota y el saldo actualizado.
-- Confirma la reserva o cancela toda la operación y devuelve el error.
CREATE PROCEDURE sp_confirmar_reserva(IN p_reserva VARCHAR(32))
COMMENT 'Confirma una reserva pendiente dentro de la cuota del operador'
BEGIN
    DECLARE v_operador VARCHAR(32);
    DECLARE v_sector VARCHAR(32);
    DECLARE v_fecha DATE;
    DECLARE v_capacidad INT UNSIGNED DEFAULT NULL;
    DECLARE v_cupos INT UNSIGNED DEFAULT NULL;
    DECLARE v_confirmacion DATETIME(6);
    DECLARE v_inicio DATETIME(6) DEFAULT NULL;
    DECLARE v_porcentaje DECIMAL(5,2);
    DECLARE v_versiones INT;
    DECLARE v_comprometidos DECIMAL(30,0);
    DECLARE v_transaccion_propia BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_transaccion_propia THEN ROLLBACK; END IF;
        RESIGNAL;
    END;

    IF @@in_transaction = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Llame al procedimiento fuera de una transacción';
    END IF;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_transaccion_propia = TRUE;

    SELECT MAX(codigo_operador), MAX(codigo_sector), MAX(fecha_visita)
    INTO v_operador, v_sector, v_fecha
    FROM reservas WHERE codigo_reserva = p_reserva;

    IF v_fecha IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reserva inexistente';
    END IF;

    SELECT capacidad_personas INTO v_capacidad
    FROM jornadas_sector
    WHERE codigo_sector = v_sector AND fecha_visita = v_fecha
    FOR UPDATE;

    SELECT cupos_reservados INTO v_cupos
    FROM reservas
    WHERE codigo_reserva = p_reserva AND estado = 'pendiente'
      AND codigo_operador = v_operador AND codigo_sector = v_sector AND fecha_visita = v_fecha
    FOR UPDATE;

    IF v_capacidad IS NULL OR v_cupos IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva ya no está pendiente o cambió de jornada';
    END IF;

    SET v_confirmacion = UTC_TIMESTAMP(6) - INTERVAL 5 HOUR;

    SELECT COUNT(*), MAX(vigente_desde), MAX(porcentaje_maximo)
    INTO v_versiones, v_inicio, v_porcentaje
    FROM limites_operador
    WHERE codigo_operador = v_operador AND codigo_sector = v_sector AND fecha_visita = v_fecha
      AND vigente_desde <= v_confirmacion
      AND (vigente_hasta IS NULL OR v_confirmacion < vigente_hasta);

    IF v_versiones <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Se requiere un único límite vigente';
    END IF;

    SELECT COALESCE(SUM(cupos_reservados), 0) INTO v_comprometidos
    FROM reservas
    WHERE codigo_operador = v_operador AND codigo_sector = v_sector
      AND fecha_visita = v_fecha AND estado = 'confirmada';

    IF v_comprometidos + v_cupos > fn_cupos_asignables(v_capacidad, v_porcentaje) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva supera el cupo disponible del operador';
    END IF;

    UPDATE reservas
    SET estado = 'confirmada', confirmada_en = v_confirmacion, limite_vigente_desde = v_inicio
    WHERE codigo_reserva = p_reserva;

    COMMIT;
END$$

-- PR · RN01/RN02. Entradas: grupo, referencia, guía, certificado e intervalo local.
-- Serializa por grupo y guía, comprueba intervalos y destinos, y delega
-- al disparador BEFORE INSERT la vigencia del certificado.
CREATE PROCEDURE sp_asignar_guia(
    IN p_grupo VARCHAR(32), IN p_asignacion VARCHAR(32),
    IN p_guia VARCHAR(32), IN p_certificacion VARCHAR(32),
    IN p_desde DATETIME(6), IN p_hasta DATETIME(6)
)
COMMENT 'Registra una asignación compatible con el grupo y el destino diario del guía'
BEGIN
    DECLARE v_reserva VARCHAR(32) DEFAULT NULL;
    DECLARE v_guia VARCHAR(32) DEFAULT NULL;
    DECLARE v_sector VARCHAR(32);
    DECLARE v_fecha DATE;
    DECLARE v_conflictos INT;
    DECLARE v_transaccion_propia BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_transaccion_propia THEN ROLLBACK; END IF;
        RESIGNAL;
    END;

    IF @@in_transaction = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Llame al procedimiento fuera de una transacción';
    END IF;
    IF p_desde IS NULL OR (p_hasta IS NOT NULL AND p_hasta <= p_desde) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Intervalo de asignación inválido';
    END IF;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_transaccion_propia = TRUE;

    SELECT codigo_reserva INTO v_reserva
    FROM grupos WHERE codigo_grupo = p_grupo FOR UPDATE;
    SELECT codigo_guia INTO v_guia
    FROM guias WHERE codigo_guia = p_guia FOR UPDATE;

    IF v_reserva IS NULL OR v_guia IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El grupo o el guía no existe';
    END IF;

    SELECT codigo_sector, fecha_visita INTO v_sector, v_fecha
    FROM reservas WHERE codigo_reserva = v_reserva;

    SELECT COUNT(*) INTO v_conflictos
    FROM asignaciones_guia AS a
    WHERE a.codigo_grupo = p_grupo
      AND (a.aplica_hasta IS NULL OR p_desde < a.aplica_hasta)
      AND (p_hasta IS NULL OR a.aplica_desde < p_hasta);

    IF v_conflictos > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El grupo ya tiene una asignación que se solapa';
    END IF;

    SELECT COUNT(*) INTO v_conflictos
    FROM asignaciones_guia AS a
    JOIN grupos AS g ON g.codigo_grupo = a.codigo_grupo
    JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva
    WHERE a.codigo_guia = p_guia AND r.fecha_visita = v_fecha
      AND r.codigo_sector <> v_sector;

    IF v_conflictos > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El guía ya tiene otro destino para esa fecha';
    END IF;

    INSERT INTO asignaciones_guia (
        codigo_grupo, ref_asignacion, codigo_guia, ref_certificacion,
        registrada_en, aplica_desde, aplica_hasta
    ) VALUES (
        p_grupo, p_asignacion, p_guia, p_certificacion,
        UTC_TIMESTAMP(6) - INTERVAL 5 HOUR, p_desde, p_hasta
    );

    COMMIT;
END$$

-- PR · RN04. Entradas: grupo, referencia, instante local y personas que ingresaron.
-- Bloquea al grupo antes de insertar. El disparador genera el exceso
-- dentro de la misma transacción cuando corresponde.
CREATE PROCEDURE sp_registrar_ingreso(
    IN p_grupo VARCHAR(32), IN p_ingreso VARCHAR(32),
    IN p_instante DATETIME(6), IN p_personas INT UNSIGNED
)
COMMENT 'Registra una entrada efectiva y coordina el cálculo del exceso por grupo'
BEGIN
    DECLARE v_grupo VARCHAR(32) DEFAULT NULL;
    DECLARE v_transaccion_propia BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_transaccion_propia THEN ROLLBACK; END IF;
        RESIGNAL;
    END;

    IF @@in_transaction = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Llame al procedimiento fuera de una transacción';
    END IF;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_transaccion_propia = TRUE;

    SELECT codigo_grupo INTO v_grupo
    FROM grupos WHERE codigo_grupo = p_grupo FOR UPDATE;

    IF v_grupo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Grupo inexistente';
    END IF;

    INSERT INTO ingresos (codigo_grupo, ref_ingreso, ingreso_en, personas_ingresadas)
    VALUES (p_grupo, p_ingreso, p_instante, p_personas);

    COMMIT;
END$$

DELIMITER ;

-- VISTA · R01/R07. Una fila por guía.
-- Resume su historial, incluso cuando aún no tiene certificados.
-- Los rangos de vencimiento por certificado se consultarán en la Fase 5.
CREATE SQL SECURITY INVOKER VIEW v_resumen_certificaciones_guia AS
SELECT g.codigo_guia,
       COUNT(c.ref_certificacion) AS total_certificaciones,
       MIN(c.fecha_vencimiento) AS primer_vencimiento_registrado,
       MAX(c.fecha_vencimiento) AS ultimo_vencimiento_registrado
FROM guias AS g
LEFT JOIN certificaciones AS c ON c.codigo_guia = g.codigo_guia
GROUP BY g.codigo_guia;

-- VISTA · R09/RN03. Una fila por operador, sector y día con reservas confirmadas.
-- Expone el numerador de uso. El informe posterior elegirá el límite aplicable
-- a la fecha de corte para calcular y mostrar el denominador.
CREATE SQL SECURITY INVOKER VIEW v_cupos_comprometidos_operador_dia AS
SELECT r.codigo_operador, r.codigo_sector, r.fecha_visita,
       COUNT(*) AS reservas_confirmadas,
       SUM(r.cupos_reservados) AS cupos_comprometidos
FROM reservas AS r
WHERE r.estado = 'confirmada'
GROUP BY r.codigo_operador, r.codigo_sector, r.fecha_visita;

-- VISTA · R10. Una fila por operador, guía histórico y tipo de incidencia.
-- El guía queda NULL cuando el evento no tiene una asignación vinculada.
CREATE SQL SECURITY INVOKER VIEW v_resumen_incidencias_guia_operador AS
SELECT r.codigo_operador, a.codigo_guia, i.tipo,
       COUNT(*) AS total_incidencias,
       MIN(i.ocurrida_en) AS primera_incidencia,
       MAX(i.ocurrida_en) AS ultima_incidencia
FROM incidencias AS i
JOIN grupos AS g ON g.codigo_grupo = i.codigo_grupo
JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva
LEFT JOIN asignaciones_guia AS a
    ON a.codigo_grupo = i.codigo_grupo AND a.ref_asignacion = i.ref_asignacion
GROUP BY r.codigo_operador, a.codigo_guia, i.tipo;