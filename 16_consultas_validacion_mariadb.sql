USE p02_guias_cupos;

-- Parámetros de las consultas. Ejecutar junto con los SELECT que los usan.
SET @corte_certificados = DATE('2026-11-16');
SET @horizonte_dias = 14;
SET @desde_visita = DATE('2026-07-01');
SET @hasta_visita = DATE('2026-10-08');
SET @corte_cuota = '2026-10-08 23:59:59';
SET @guia = 'GUI-001';
SET @grupo = 'G1-00001';
SET @operador = 'OP-018';
SET @sector = 'SEC-001';
SET @dia = DATE('2026-07-01');

-- Q01 · R07/RN01. Certificaciones vencidas y próximas a vencer.
-- Esperado: 50 vencidas y 50 próximas con estos parámetros.
-- Una certificación que vence el día del corte sigue vigente ese día.
SELECT c.codigo_guia, c.ref_certificacion, c.tipo, c.fecha_vencimiento,
       CASE WHEN c.fecha_vencimiento < @corte_certificados THEN 'vencida'
            ELSE 'próxima a vencer' END AS estado_al_corte
FROM certificaciones AS c
WHERE c.fecha_emision <= @corte_certificados
  AND c.fecha_vencimiento <= DATE_ADD(@corte_certificados, INTERVAL @horizonte_dias DAY)
ORDER BY c.fecha_vencimiento, c.codigo_guia, c.ref_certificacion;

-- Q02 · R01. Historial de acreditaciones de un guía.
-- Esperado para GUI-001: C-ANT y C-BASE.
-- Un código inexistente devuelve cero filas.
SELECT c.ref_certificacion, c.tipo, c.entidad_emisora,
       c.fecha_emision, c.fecha_vencimiento
FROM certificaciones AS c
WHERE c.codigo_guia = @guia
ORDER BY c.fecha_emision, c.ref_certificacion;

-- Q03 · R08/RN04. Grupos con más visitantes ingresados que autorizados.
-- Esperado: 500 grupos con exceso de una persona cada uno.
-- Llegar exactamente al autorizado no cuenta como exceso.
SELECT g.codigo_grupo, g.visitantes_autorizados,
       SUM(e.personas_ingresadas) AS total_ingresado,
       SUM(e.personas_ingresadas) - g.visitantes_autorizados AS exceso
FROM grupos AS g
JOIN ingresos AS e ON e.codigo_grupo = g.codigo_grupo
GROUP BY g.codigo_grupo, g.visitantes_autorizados
HAVING SUM(e.personas_ingresadas) > g.visitantes_autorizados
ORDER BY g.codigo_grupo;

-- Q04 · R05/R08/RN04. Auditoría de ingresos acumulados en un grupo.
-- Esperado para G1-00001: acumulados de 6 y 10 frente a 9 autorizados.
-- Solo I-02 debe tener incidencia de exceso.
SELECT e.ref_ingreso, e.ingreso_en, e.personas_ingresadas,
       SUM(e.personas_ingresadas) OVER (
           PARTITION BY e.codigo_grupo
           ORDER BY e.ingreso_en, e.ref_ingreso
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS ingresados_acumulados,
       g.visitantes_autorizados, i.ref_incidencia
FROM ingresos AS e
JOIN grupos AS g ON g.codigo_grupo = e.codigo_grupo
LEFT JOIN incidencias AS i
  ON i.codigo_grupo = e.codigo_grupo AND i.ref_ingreso = e.ref_ingreso
 AND i.tipo = 'exceso_personas'
WHERE e.codigo_grupo = @grupo
ORDER BY e.ingreso_en, e.ref_ingreso;

-- Q05 · R04/R06/R09/RN03. Utilización por operador, sector y fecha.
-- El corte elige la versión de cuota. El numerador usa el estado actual
-- de las reservas para esa fecha de visita.
-- Esperado para OP-018 / SEC-001 / 2026-07-01: 20 de 44 cupos de cuota,
-- 45,45 % de la cuota y 25,00 % de la capacidad de 80 personas.
-- Si una cuota está en cero, ese porcentaje de uso queda NULL.
SELECT q.codigo_operador, q.codigo_sector, q.fecha_visita,
       q.capacidad_personas, q.porcentaje_maximo,
       q.cupos_asignables, q.cupos_comprometidos,
       ROUND(100.00 * q.cupos_comprometidos / NULLIF(q.cupos_asignables, 0), 2)
           AS porcentaje_de_cuota_utilizado,
       ROUND(100.00 * q.cupos_comprometidos / NULLIF(q.capacidad_personas, 0), 2)
           AS porcentaje_de_capacidad_del_sector
FROM (
    SELECT l.codigo_operador, l.codigo_sector, l.fecha_visita,
           j.capacidad_personas, l.porcentaje_maximo,
           fn_cupos_asignables(j.capacidad_personas, l.porcentaje_maximo)
               AS cupos_asignables,
           COALESCE(v.cupos_comprometidos, 0) AS cupos_comprometidos
    FROM limites_operador AS l
    JOIN jornadas_sector AS j
      ON j.codigo_sector = l.codigo_sector AND j.fecha_visita = l.fecha_visita
    LEFT JOIN v_cupos_comprometidos_operador_dia AS v
      ON v.codigo_operador = l.codigo_operador AND v.codigo_sector = l.codigo_sector
     AND v.fecha_visita = l.fecha_visita
    WHERE l.fecha_visita BETWEEN @desde_visita AND @hasta_visita
      AND l.vigente_desde <= @corte_cuota
      AND (l.vigente_hasta IS NULL OR @corte_cuota < l.vigente_hasta)
) AS q
ORDER BY q.fecha_visita, q.codigo_operador, q.codigo_sector;

-- Q06 · R10. Historial de incidencias por operador y guía.
-- Con los parámetros iniciales aparecen el exceso de G1-00001
-- y su cambio de destino CAMB-00001, entre los eventos que correspondan.
-- Asignar NULL a una variable permite consultar sin ese filtro.
SELECT i.ocurrida_en, r.codigo_operador, a.codigo_guia, r.codigo_sector,
       i.codigo_grupo, i.tipo, i.ref_incidencia, i.descripcion_general
FROM incidencias AS i
JOIN grupos AS g ON g.codigo_grupo = i.codigo_grupo
JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva
LEFT JOIN asignaciones_guia AS a
  ON a.codigo_grupo = i.codigo_grupo AND a.ref_asignacion = i.ref_asignacion
WHERE (@operador IS NULL OR r.codigo_operador = @operador)
  AND (@guia IS NULL OR a.codigo_guia = @guia)
  AND i.ocurrida_en >= @desde_visita
  AND i.ocurrida_en < DATE_ADD(@hasta_visita, INTERVAL 1 DAY)
ORDER BY i.ocurrida_en, i.ref_incidencia;

-- Q07 · R02. Reservas que cubren más de un grupo.
-- Esperado: 500 reservas. Este reporte muestra los cupos una vez por reserva.
SELECT r.codigo_reserva, r.cupos_reservados, g.total_grupos, g.total_autorizados
FROM reservas AS r
JOIN (
    SELECT codigo_reserva, COUNT(*) AS total_grupos,
           SUM(visitantes_autorizados) AS total_autorizados
    FROM grupos
    GROUP BY codigo_reserva
    HAVING COUNT(*) > 1
) AS g ON g.codigo_reserva = r.codigo_reserva
ORDER BY r.codigo_reserva;

-- Q08 · R04/RN03. Reservas confirmadas usando una cuota ya cerrada al corte.
-- Esperado: 500 filas. R-00001 conserva la versión del 60,00 %.
SELECT r.codigo_reserva, r.confirmada_en, l.vigente_desde,
       l.vigente_hasta, l.porcentaje_maximo
FROM reservas AS r
JOIN limites_operador AS l
  ON l.codigo_operador = r.codigo_operador AND l.codigo_sector = r.codigo_sector
 AND l.fecha_visita = r.fecha_visita AND l.vigente_desde = r.limite_vigente_desde
WHERE r.estado = 'confirmada' AND l.vigente_hasta <= @corte_cuota
ORDER BY r.codigo_reserva;

-- Q09 · R03/RN02. Control de guías con más de un destino el mismo día.
-- Esperado: cero filas. Varios grupos en el mismo destino cuentan como un destino.
SELECT a.codigo_guia, r.fecha_visita, COUNT(DISTINCT r.codigo_sector) AS destinos
FROM asignaciones_guia AS a
JOIN grupos AS g ON g.codigo_grupo = a.codigo_grupo
JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva
GROUP BY a.codigo_guia, r.fecha_visita
HAVING COUNT(DISTINCT r.codigo_sector) > 1;

-- Q10 · R09/RN03. Total comprometido por estado en el intervalo de visitas.
-- Esperado: 8.000 confirmadas y 160.000 cupos comprometidos.
-- Pendiente y liberada: 1.000 reservas por estado y cero cupos comprometidos.
SELECT r.estado, COUNT(*) AS reservas,
       SUM(CASE WHEN r.estado = 'confirmada' THEN r.cupos_reservados ELSE 0 END)
           AS cupos_comprometidos
FROM reservas AS r
WHERE r.fecha_visita BETWEEN @desde_visita AND @hasta_visita
GROUP BY r.estado
ORDER BY r.estado;

-- Q11 · R10. Total de incidencias por tipo a partir de la vista analítica.
-- Esperado: 500 cambios de destino y 500 excesos.
SELECT tipo, SUM(total_incidencias) AS incidencias
FROM v_resumen_incidencias_guia_operador
GROUP BY tipo
ORDER BY tipo;

-- Q12 · R05/RN04. Grupos programados que aún no registran ingresos.
-- Esperado en la carga base: cero filas.
-- En una prueba de un grupo nuevo sin entradas, debe aparecer ese grupo.
SELECT g.codigo_grupo, r.codigo_operador, r.fecha_visita
FROM grupos AS g
JOIN reservas AS r ON r.codigo_reserva = g.codigo_reserva
WHERE r.fecha_visita BETWEEN @desde_visita AND @hasta_visita
  AND NOT EXISTS (
      SELECT 1 FROM ingresos AS e WHERE e.codigo_grupo = g.codigo_grupo
  )
ORDER BY r.fecha_visita, g.codigo_grupo;


-- P01 · R07. Búsqueda de certificados próximos por rango de vencimiento.
-- Índice candidato: ix_certificaciones_vencimiento.
EXPLAIN
SELECT c.codigo_guia, c.ref_certificacion, c.fecha_vencimiento
FROM certificaciones AS c
WHERE c.fecha_emision <= @corte_certificados
  AND c.fecha_vencimiento BETWEEN @corte_certificados
                             AND DATE_ADD(@corte_certificados, INTERVAL @horizonte_dias DAY)
ORDER BY c.fecha_vencimiento, c.codigo_guia;

-- P02 · RN03. Lectura del saldo que usa la confirmación de reservas.
-- Índice candidato: ix_reservas_saldo.
EXPLAIN
SELECT COALESCE(SUM(r.cupos_reservados), 0) AS comprometidos
FROM reservas AS r
WHERE r.codigo_operador = @operador AND r.codigo_sector = @sector
  AND r.fecha_visita = @dia AND r.estado = 'confirmada';

-- P03 · R05/R08. Reconstrucción cronológica de las entradas de un grupo.
-- Índice candidato: ix_ingresos_cronologia.
EXPLAIN
SELECT e.ref_ingreso, e.ingreso_en, e.personas_ingresadas
FROM ingresos AS e
WHERE e.codigo_grupo = @grupo
ORDER BY e.ingreso_en, e.ref_ingreso;