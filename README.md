# P02 · Guías y operadores: acreditación y cupos

Proyecto integrador de Bases de Datos · Universidad del Magdalena

El proyecto controla la acreditación y asignación de guías, los cupos
por operador y jornada, y las incidencias durante el ingreso de grupos.
El caso se sitúa en el contexto turístico del Parque Tayrona.
Los registros, las capacidades y las cuotas de prueba son sintéticos.

## Entorno

- MariaDB 10.4.32 en XAMPP.
- Base de datos: `p02_guias_cupos`.
- Versión final: 11 tablas, 3 vistas, 1 función, 6 procedimientos y 2 disparadores.

## Orden de instalación

1. Crear una base vacía llamada `p02_guias_cupos` con codificación `utf8mb4`.
2. Importar `12_creacion_esquema_mariadb.sql`.
3. Importar `22_control_cupos_por_grupo.sql`.
4. Importar `26_control_capacidad_jornada.sql`.
5. Importar `29_control_publicacion_cuotas.sql`.
6. Importar `14_carga_datos_sinteticos_mariadb.sql`.
7. Ejecutar `15_verificaciones_carga_mariadb.sql`.
8. Ejecutar `16_consultas_validacion_mariadb.sql`.
9. Importar `32_roles_y_permisos.sql` con una cuenta administradora.

La creación de una cuenta local de prueba se documenta por separado
con un marcador de contraseña.

## Pruebas y evidencias

El archivo `17_plan_pruebas_y_rendimiento.md` contiene el plan de pruebas.
La carpeta `evidencias` reúne las capturas de los resultados en MariaDB.

- `05_verificacion_carga.png`: conteos observados de la carga sintética.
- `07_q04_incidencia_por_ingreso.png`: incidencia vinculada al ingreso que generó el exceso.
- `21_verificacion_cupo_concurrente.png`: una reserva confirmada y otra pendiente.
- `23_prueba_grupos_cupo_exacto.png` y `24_prueba_grupo_sin_cupo_rechazado.png`: reparto válido y rechazo por exceso.
- `31_prueba_cuota_nueva_e_historial.png`: conservación de la cuota anterior y aplicación de la nueva.
- `33_prueba_taquilla_permiso_concedido.png` y `34_prueba_taquilla_permiso_denegado.png`: acceso permitido mediante una rutina y escritura directa rechazada.

El archivo `respaldo_p02_version_probada.sql` conserva la versión anterior
a los complementos 22, 26 y 29. El orden de instalación de arriba
reconstruye la versión final.