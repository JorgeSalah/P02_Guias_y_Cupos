USE p02_guias_cupos;

WITH inventario AS (
    SELECT 'Tabla' AS tipo,
           t.TABLE_NAME AS ambito,
           t.TABLE_NAME AS objeto,
           0 AS posicion,
           CONCAT('Motor: ', t.ENGINE, ' | Intercalación: ', t.TABLE_COLLATION)
               AS definicion,
           t.TABLE_COMMENT AS documentacion,
           'Comentario del catálogo' AS origen
    FROM information_schema.TABLES AS t
    WHERE t.TABLE_SCHEMA = DATABASE()
      AND t.TABLE_TYPE = 'BASE TABLE'

    UNION ALL

    SELECT 'Columna', c.TABLE_NAME, c.COLUMN_NAME, c.ORDINAL_POSITION,
           CONCAT(
               c.COLUMN_TYPE,
               IF(c.IS_NULLABLE = 'YES', ' NULL', ' NOT NULL'),
               IF(c.COLUMN_DEFAULT IS NULL, '', CONCAT(' DEFAULT ', c.COLUMN_DEFAULT)),
               IF(c.COLLATION_NAME IS NULL, '', CONCAT(' COLLATE ', c.COLLATION_NAME)),
               IF(c.EXTRA = '', '', CONCAT(' | ', c.EXTRA))
           ),
           c.COLUMN_COMMENT,
           'Comentario del catálogo'
    FROM information_schema.COLUMNS AS c
    JOIN information_schema.TABLES AS t
      ON t.TABLE_SCHEMA = c.TABLE_SCHEMA
     AND t.TABLE_NAME = c.TABLE_NAME
    WHERE c.TABLE_SCHEMA = DATABASE()
      AND t.TABLE_TYPE = 'BASE TABLE'

    UNION ALL

    SELECT tc.CONSTRAINT_TYPE, tc.TABLE_NAME, tc.CONSTRAINT_NAME, 0,
           CONCAT(
               '(', GROUP_CONCAT(k.COLUMN_NAME ORDER BY k.ORDINAL_POSITION), ')',
               CASE
                   WHEN tc.CONSTRAINT_TYPE = 'FOREIGN KEY' THEN CONCAT(
                       ' REFERENCES ', MAX(k.REFERENCED_TABLE_NAME), ' (',
                       GROUP_CONCAT(k.REFERENCED_COLUMN_NAME ORDER BY k.ORDINAL_POSITION),
                       ') ON UPDATE ', MAX(rc.UPDATE_RULE),
                       ' ON DELETE ', MAX(rc.DELETE_RULE)
                   )
                   ELSE ''
               END
           ),
           CASE tc.CONSTRAINT_TYPE
               WHEN 'PRIMARY KEY' THEN 'Identifica de forma única cada registro de la tabla.'
               WHEN 'FOREIGN KEY' THEN 'Vincula el registro con su entidad de origen y protege la referencia.'
               ELSE 'Impide vincular más de una incidencia al mismo ingreso de un grupo.'
           END,
           'Documentación de la restricción'
    FROM information_schema.TABLE_CONSTRAINTS AS tc
    JOIN information_schema.KEY_COLUMN_USAGE AS k
      ON k.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA
     AND k.TABLE_NAME = tc.TABLE_NAME
     AND k.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
    LEFT JOIN information_schema.REFERENTIAL_CONSTRAINTS AS rc
      ON rc.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA
     AND rc.TABLE_NAME = tc.TABLE_NAME
     AND rc.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
    WHERE tc.TABLE_SCHEMA = DATABASE()
      AND tc.CONSTRAINT_TYPE IN ('PRIMARY KEY', 'FOREIGN KEY', 'UNIQUE')
    GROUP BY tc.CONSTRAINT_TYPE, tc.TABLE_NAME, tc.CONSTRAINT_NAME

    UNION ALL

    SELECT 'CHECK', cc.TABLE_NAME, cc.CONSTRAINT_NAME, 0,
           cc.CHECK_CLAUSE,
           'Valida el dominio o la coherencia de los valores de la fila.',
           'Documentación de la restricción'
    FROM information_schema.CHECK_CONSTRAINTS AS cc
    WHERE cc.CONSTRAINT_SCHEMA = DATABASE()

    UNION ALL

    SELECT 'Índice', s.TABLE_NAME, s.INDEX_NAME, 0,
           CONCAT(
               MAX(s.INDEX_TYPE), ' (',
               GROUP_CONCAT(s.COLUMN_NAME ORDER BY s.SEQ_IN_INDEX), ')'
           ),
           CASE s.INDEX_NAME
               WHEN 'ix_certificaciones_vencimiento' THEN 'Apoya búsquedas por fecha de vencimiento.'
               WHEN 'ix_reservas_saldo' THEN 'Apoya el cálculo de cupos comprometidos.'
               WHEN 'ix_reservas_reporte_diario' THEN 'Apoya reportes de reservas por día.'
               WHEN 'ix_ingresos_cronologia' THEN 'Apoya el recorrido cronológico de entradas de un grupo.'
               ELSE 'Da soporte a una clave foránea.'
           END,
           'Documentación del índice'
    FROM information_schema.STATISTICS AS s
    WHERE s.TABLE_SCHEMA = DATABASE()
      AND s.NON_UNIQUE = 1
    GROUP BY s.TABLE_NAME, s.INDEX_NAME

    UNION ALL

    SELECT 'Vista', v.TABLE_NAME, v.TABLE_NAME, 0,
           v.VIEW_DEFINITION,
           CASE v.TABLE_NAME
               WHEN 'v_resumen_certificaciones_guia' THEN 'Resume las acreditaciones de cada guía.'
               WHEN 'v_cupos_comprometidos_operador_dia' THEN 'Suma los cupos confirmados por operador y jornada.'
               ELSE 'Resume incidencias por operador, guía histórico y tipo.'
           END,
           'Documentación de la vista'
    FROM information_schema.VIEWS AS v
    WHERE v.TABLE_SCHEMA = DATABASE()

    UNION ALL

    SELECT r.ROUTINE_TYPE, r.ROUTINE_NAME, r.ROUTINE_NAME, 0,
           CONCAT(
               'Seguridad: ', r.SECURITY_TYPE, ' | ',
               COALESCE(r.ROUTINE_DEFINITION, '[Definición no visible para esta cuenta]')
           ),
           r.ROUTINE_COMMENT,
           'Comentario del catálogo'
    FROM information_schema.ROUTINES AS r
    WHERE r.ROUTINE_SCHEMA = DATABASE()

    UNION ALL

    SELECT 'Disparador', tr.EVENT_OBJECT_TABLE, tr.TRIGGER_NAME, 0,
           CONCAT(
               tr.ACTION_TIMING, ' ', tr.EVENT_MANIPULATION,
               ' | ', tr.ACTION_STATEMENT
           ),
           CASE tr.TRIGGER_NAME
               WHEN 'tr_asignaciones_bi_vigencia' THEN 'Comprueba la vigencia del certificado al asignar.'
               ELSE 'Registra la incidencia cuando el ingreso acumulado supera el autorizado.'
           END,
           'Documentación del disparador'
    FROM information_schema.TRIGGERS AS tr
    WHERE tr.TRIGGER_SCHEMA = DATABASE()
)
SELECT tipo, ambito, objeto, posicion,
       REPLACE(REPLACE(REPLACE(definicion, CHAR(13), ''),
                       CHAR(10), ' | '), CHAR(9), ' ') AS definicion,
       REPLACE(REPLACE(REPLACE(documentacion, CHAR(13), ''),
                       CHAR(10), ' '), CHAR(9), ' ') AS documentacion,
       origen
FROM inventario
ORDER BY tipo, ambito, posicion, objeto;