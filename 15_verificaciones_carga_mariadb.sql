USE p02_guias_cupos;

-- Totales por tabla y por escenario.
SELECT 'guias' AS control, COUNT(*) AS observado, 100 AS esperado FROM guias
UNION ALL SELECT 'certificaciones', COUNT(*), 200 FROM certificaciones
UNION ALL SELECT 'operadores', COUNT(*), 50 FROM operadores
UNION ALL SELECT 'sectores', COUNT(*), 50 FROM sectores
UNION ALL SELECT 'jornadas_sector', COUNT(*), 5000 FROM jornadas_sector
UNION ALL SELECT 'limites_operador', COUNT(*), 10000 FROM limites_operador
UNION ALL SELECT 'reservas', COUNT(*), 10000 FROM reservas
UNION ALL SELECT 'grupos', COUNT(*), 8500 FROM grupos
UNION ALL SELECT 'asignaciones_guia', COUNT(*), 8500 FROM asignaciones_guia
UNION ALL SELECT 'ingresos', COUNT(*), 10000 FROM ingresos
UNION ALL SELECT 'incidencias', COUNT(*), 1000 FROM incidencias
UNION ALL SELECT 'reservas confirmadas', COUNT(*), 8000 FROM reservas WHERE estado = 'confirmada'
UNION ALL SELECT 'reservas pendientes', COUNT(*), 1000 FROM reservas WHERE estado = 'pendiente'
UNION ALL SELECT 'reservas liberadas', COUNT(*), 1000 FROM reservas WHERE estado = 'liberada'
UNION ALL SELECT 'segundas entradas', COUNT(*), 1500 FROM ingresos WHERE ref_ingreso = 'I-02'
UNION ALL SELECT 'excesos', COUNT(*), 500 FROM incidencias WHERE tipo = 'exceso_personas'
UNION ALL SELECT 'cambios de destino', COUNT(*), 500 FROM incidencias WHERE tipo = 'cambio_destino'
UNION ALL SELECT 'certificados vencidos al corte', COUNT(*), 50
    FROM certificaciones WHERE fecha_vencimiento < '2026-11-16'
UNION ALL SELECT 'certificados próximos al corte', COUNT(*), 50
    FROM certificaciones WHERE fecha_vencimiento BETWEEN '2026-11-16' AND '2026-11-30'
UNION ALL SELECT 'excesos con guía histórico', COUNT(*), 500
    FROM incidencias WHERE tipo = 'exceso_personas' AND ref_asignacion IS NOT NULL;

-- R02 y R05. Referencias principales y compuestas sin padre. Esperado: cero filas.
SELECT 'grupo sin reserva' AS anomalia, g.codigo_grupo AS referencia
FROM grupos AS g LEFT JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva
WHERE r.codigo_reserva IS NULL
UNION ALL
SELECT 'ingreso sin grupo', CONCAT(e.codigo_grupo, '/', e.ref_ingreso)
FROM ingresos AS e LEFT JOIN grupos AS g ON g.codigo_grupo = e.codigo_grupo
WHERE g.codigo_grupo IS NULL
UNION ALL
SELECT 'incidencia sin ingreso del grupo', i.ref_incidencia
FROM incidencias AS i
LEFT JOIN ingresos AS e
  ON e.codigo_grupo = i.codigo_grupo AND e.ref_ingreso = i.ref_ingreso
WHERE i.ref_ingreso IS NOT NULL AND e.ref_ingreso IS NULL
UNION ALL
SELECT 'incidencia sin asignación del grupo', i.ref_incidencia
FROM incidencias AS i
LEFT JOIN asignaciones_guia AS a
  ON a.codigo_grupo = i.codigo_grupo AND a.ref_asignacion = i.ref_asignacion
WHERE i.ref_asignacion IS NOT NULL AND a.ref_asignacion IS NULL;

-- Nulos indebidos y cantidades fuera de dominio. Esperado: cero filas.
SELECT 'reserva con confirmación incoherente' AS anomalia, codigo_reserva AS referencia
FROM reservas
WHERE cupos_reservados IS NULL OR cupos_reservados <= 0
   OR (estado = 'pendiente'
       AND (confirmada_en IS NOT NULL OR limite_vigente_desde IS NOT NULL))
   OR (estado IN ('confirmada', 'liberada')
       AND (confirmada_en IS NULL OR limite_vigente_desde IS NULL))
UNION ALL
SELECT 'grupo con autorizados inválidos', codigo_grupo
FROM grupos WHERE visitantes_autorizados IS NULL OR visitantes_autorizados <= 0
UNION ALL
SELECT 'ingreso con cantidad inválida', CONCAT(codigo_grupo, '/', ref_ingreso)
FROM ingresos WHERE personas_ingresadas IS NULL OR personas_ingresadas <= 0;

-- Identificadores y orígenes duplicados. Esperado: cero filas.
SELECT 'reserva duplicada' AS anomalia, codigo_reserva AS referencia
FROM reservas GROUP BY codigo_reserva HAVING COUNT(*) > 1
UNION ALL
SELECT 'ingreso duplicado', CONCAT(codigo_grupo, '/', ref_ingreso)
FROM ingresos GROUP BY codigo_grupo, ref_ingreso HAVING COUNT(*) > 1
UNION ALL
SELECT 'más de una incidencia por ingreso', CONCAT(codigo_grupo, '/', ref_ingreso)
FROM incidencias WHERE ref_ingreso IS NOT NULL
GROUP BY codigo_grupo, ref_ingreso HAVING COUNT(*) > 1;

-- R02. Grupos que juntos exceden los cupos de su reserva. Esperado: cero filas.
SELECT r.codigo_reserva, r.cupos_reservados, SUM(g.visitantes_autorizados) AS autorizados
FROM reservas AS r
JOIN grupos AS g ON g.codigo_reserva = r.codigo_reserva
GROUP BY r.codigo_reserva, r.cupos_reservados
HAVING SUM(g.visitantes_autorizados) > r.cupos_reservados;

-- RN01. Certificados que no cubren registro o visita. Esperado: cero filas.
SELECT a.codigo_grupo, a.ref_asignacion, a.codigo_guia
FROM asignaciones_guia AS a
JOIN grupos AS g ON g.codigo_grupo = a.codigo_grupo
JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva
LEFT JOIN certificaciones AS c
  ON c.codigo_guia = a.codigo_guia AND c.ref_certificacion = a.ref_certificacion
WHERE c.codigo_guia IS NULL
   OR DATE(a.registrada_en) NOT BETWEEN c.fecha_emision AND c.fecha_vencimiento
   OR r.fecha_visita NOT BETWEEN c.fecha_emision AND c.fecha_vencimiento;

-- RN02. Guías con dos sectores en el mismo día. Esperado: cero filas.
SELECT a.codigo_guia, r.fecha_visita, COUNT(DISTINCT r.codigo_sector) AS destinos
FROM asignaciones_guia AS a
JOIN grupos AS g ON g.codigo_grupo = a.codigo_grupo
JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva
GROUP BY a.codigo_guia, r.fecha_visita
HAVING COUNT(DISTINCT r.codigo_sector) > 1;

-- D03. Asignaciones del mismo grupo con intervalos solapados. Esperado: cero filas.
SELECT a.codigo_grupo, a.ref_asignacion, b.ref_asignacion AS otra_asignacion
FROM asignaciones_guia AS a
JOIN asignaciones_guia AS b
  ON b.codigo_grupo = a.codigo_grupo AND a.ref_asignacion < b.ref_asignacion
WHERE (a.aplica_hasta IS NULL OR b.aplica_desde < a.aplica_hasta)
  AND (b.aplica_hasta IS NULL OR a.aplica_desde < b.aplica_hasta);

-- RN03. Dos versiones vigentes al mismo tiempo. Esperado: cero filas.
SELECT a.codigo_operador, a.codigo_sector, a.fecha_visita,
       a.vigente_desde, b.vigente_desde AS otra_version
FROM limites_operador AS a
JOIN limites_operador AS b
  ON b.codigo_operador = a.codigo_operador
 AND b.codigo_sector = a.codigo_sector
 AND b.fecha_visita = a.fecha_visita
 AND b.vigente_desde > a.vigente_desde
WHERE a.vigente_hasta IS NULL OR b.vigente_desde < a.vigente_hasta;

-- RN03. Versión aplicada fuera del instante de confirmación. Esperado: cero filas.
SELECT r.codigo_reserva, r.confirmada_en, r.limite_vigente_desde
FROM reservas AS r
LEFT JOIN limites_operador AS l
  ON l.codigo_operador = r.codigo_operador AND l.codigo_sector = r.codigo_sector
 AND l.fecha_visita = r.fecha_visita AND l.vigente_desde = r.limite_vigente_desde
WHERE r.estado IN ('confirmada', 'liberada')
  AND (
       l.vigente_desde IS NULL OR r.confirmada_en < l.vigente_desde
       OR (l.vigente_hasta IS NOT NULL AND r.confirmada_en >= l.vigente_hasta)
  );

-- RN03. Cuotas excedidas al cierre del período sintético. Esperado: cero filas.
SELECT v.codigo_operador, v.codigo_sector, v.fecha_visita, v.cupos_comprometidos,
       fn_cupos_asignables(j.capacidad_personas, l.porcentaje_maximo) AS cupos_maximos
FROM v_cupos_comprometidos_operador_dia AS v
JOIN jornadas_sector AS j
  ON j.codigo_sector = v.codigo_sector AND j.fecha_visita = v.fecha_visita
LEFT JOIN limites_operador AS l
  ON l.codigo_operador = v.codigo_operador
 AND l.codigo_sector = v.codigo_sector AND l.fecha_visita = v.fecha_visita
 AND l.vigente_desde <= '2026-10-08 23:59:59'
 AND (l.vigente_hasta IS NULL OR l.vigente_hasta > '2026-10-08 23:59:59')
WHERE l.vigente_desde IS NULL
   OR v.cupos_comprometidos > fn_cupos_asignables(j.capacidad_personas, l.porcentaje_maximo);

-- RN04. Entradas con exceso sin incidencia o incidencias sin exceso.
-- El orden coincide con la secuencia de registro de este conjunto sintético.
-- Esperado: cero filas.
WITH acumulados AS (
    SELECT e.codigo_grupo, e.ref_ingreso,
           SUM(e.personas_ingresadas) OVER (
               PARTITION BY e.codigo_grupo
               ORDER BY e.ingreso_en, e.ref_ingreso
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS ingresados_acumulados
    FROM ingresos AS e
)
SELECT a.codigo_grupo, a.ref_ingreso, a.ingresados_acumulados,
       g.visitantes_autorizados, i.ref_incidencia
FROM acumulados AS a
JOIN grupos AS g ON g.codigo_grupo = a.codigo_grupo
LEFT JOIN incidencias AS i
  ON i.codigo_grupo = a.codigo_grupo AND i.ref_ingreso = a.ref_ingreso
 AND i.tipo = 'exceso_personas'
WHERE (a.ingresados_acumulados > g.visitantes_autorizados AND i.ref_incidencia IS NULL)
   OR (a.ingresados_acumulados <= g.visitantes_autorizados AND i.ref_incidencia IS NOT NULL);