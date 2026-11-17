/*
  P02 · Permisos de operación · MariaDB 10.4.32
  Trabajo asistido por IA · PENDIENTE DE PRUEBA EN SERVIDOR
  Instala los roles desde una cuenta administradora.
  Las cuentas individuales de prueba se configuran por separado.
*/

CREATE ROLE p02_taquilla;
CREATE ROLE p02_acreditacion;
CREATE ROLE p02_admin_cupos;

-- Taquilla puede crear reservas pendientes. El estado y los datos de
-- confirmación se establecen mediante la rutina de confirmación.
GRANT SELECT ON p02_guias_cupos.reservas TO p02_taquilla;
GRANT SELECT ON p02_guias_cupos.grupos TO p02_taquilla;

GRANT INSERT (
    codigo_reserva, codigo_operador, codigo_sector,
    fecha_visita, turno, cupos_reservados
) ON p02_guias_cupos.reservas TO p02_taquilla;

GRANT EXECUTE ON PROCEDURE p02_guias_cupos.sp_confirmar_reserva
    TO p02_taquilla;
GRANT EXECUTE ON PROCEDURE p02_guias_cupos.sp_guardar_grupo
    TO p02_taquilla;
GRANT EXECUTE ON PROCEDURE p02_guias_cupos.sp_registrar_ingreso
    TO p02_taquilla;

-- Acreditación registra guías y certificados y asigna guías a grupos.
GRANT SELECT, INSERT ON p02_guias_cupos.guias TO p02_acreditacion;
GRANT SELECT, INSERT ON p02_guias_cupos.certificaciones TO p02_acreditacion;
GRANT SELECT ON p02_guias_cupos.grupos TO p02_acreditacion;
GRANT SELECT ON p02_guias_cupos.asignaciones_guia TO p02_acreditacion;
GRANT EXECUTE ON PROCEDURE p02_guias_cupos.sp_asignar_guia
    TO p02_acreditacion;

-- Administración crea los datos iniciales de operación y cambia
-- capacidades y porcentajes a través de las rutinas de control.
GRANT SELECT, INSERT ON p02_guias_cupos.operadores TO p02_admin_cupos;
GRANT SELECT, INSERT ON p02_guias_cupos.sectores TO p02_admin_cupos;
GRANT SELECT, INSERT ON p02_guias_cupos.jornadas_sector TO p02_admin_cupos;
GRANT SELECT ON p02_guias_cupos.limites_operador TO p02_admin_cupos;
GRANT SELECT ON p02_guias_cupos.reservas TO p02_admin_cupos;
GRANT EXECUTE ON PROCEDURE p02_guias_cupos.sp_cambiar_capacidad_jornada
    TO p02_admin_cupos;
GRANT EXECUTE ON PROCEDURE p02_guias_cupos.sp_publicar_limite_operador
    TO p02_admin_cupos;

SHOW GRANTS FOR p02_taquilla;
SHOW GRANTS FOR p02_acreditacion;
SHOW GRANTS FOR p02_admin_cupos;