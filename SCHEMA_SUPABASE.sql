-- ============================================================
-- GESTIÓN DE OBRA — Esquema Supabase/PostgreSQL
-- Versión 1.1 — Junio 2026
-- Basado en SCHEMA_SUPABASE.md
--
-- INSTRUCCIONES:
--   Pegar en el SQL Editor de un proyecto Supabase nuevo y vacío.
--   Ejecutar una sola vez. Es seguro re-ejecutar (idempotente).
--
-- ORDEN DE SECCIONES (sin forward-references):
--   1.  Extensión uuid-ossp
--   2.  Tablas núcleo           (empresas, profiles, empresa_miembros, obras, obra_miembros)
--   3.  Estructura de obra      (pisos, unidades, fases, partidas)
--   4.  Avances                 (avances, avances_historial)
--   5.  Gantt / cronograma      (cronograma_config, cronograma_unidades, cronograma_partidas, plan_semanal)
--   6.  Control ventanas        (control_ventanas_items, control_ventanas_programa)
--   7.  Logística               (logistica_viajes, logistica_materiales)
--   8.  Bodega                  (bodega_items, bodega_movimientos, bodega_vales, bodega_vale_items)
--   9.  Materiales              (materiales_items, materiales_stock)
--  10.  Asistencia/sobretiempo  (personal, equipos, equipo_miembros, asistencia_dias, sobretiempo)
--  11.  Rendimiento             (rendimiento_datos)
--  12.  Informes                (informes)
--  13.  Pasillos                (pasillo_items)
--  14.  Plantillas globales     (plantillas_tipo_obra, plantillas_fases, plantillas_partidas)
--  15.  Funciones helper RLS    (es_miembro_obra, rol_en_obra, responsable_en_obra)
--  16.  Índices
--  17.  Row Level Security      (ENABLE + políticas)
--  18.  Trigger handle_new_user
-- ============================================================


-- ============================================================
-- 1. EXTENSIÓN
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ============================================================
-- 2. TABLAS NÚCLEO
-- ============================================================

-- ------------------------------------------------------------
-- empresas
-- Nivel raíz. Una empresa puede tener muchas obras.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.empresas (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre      text        NOT NULL,
  rut         text        UNIQUE,                      -- RUT empresa (Chile)
  plan        text        NOT NULL DEFAULT 'free',     -- 'free' | 'pro' | 'enterprise'
  created_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.empresas IS 'Empresas constructoras o inmobiliarias. Nivel raíz del sistema.';

-- ------------------------------------------------------------
-- profiles
-- Extiende auth.users. Se crea automáticamente al registrarse (trigger sección 18).
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id          uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre      text        NOT NULL,
  email       text        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.profiles IS 'Perfil de cada usuario. 1:1 con auth.users.';

-- ------------------------------------------------------------
-- empresa_miembros
-- Qué usuarios pertenecen a qué empresa.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.empresa_miembros (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  uuid        NOT NULL REFERENCES public.empresas(id)  ON DELETE CASCADE,
  profile_id  uuid        NOT NULL REFERENCES public.profiles(id)  ON DELETE CASCADE,
  rol         text        NOT NULL DEFAULT 'miembro',  -- 'owner' | 'admin' | 'miembro'
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, profile_id)
);
COMMENT ON TABLE public.empresa_miembros IS 'Relación usuario ↔ empresa con rol.';

-- ------------------------------------------------------------
-- obras
-- El proyecto de construcción. Punto central de todo.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.obras (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            uuid        NOT NULL REFERENCES public.empresas(id)  ON DELETE CASCADE,
  nombre                text        NOT NULL,
  tipo                  text        NOT NULL,           -- 'casa' | 'departamento' | 'edificio' | 'urbanizacion'
  direccion             text,
  fecha_inicio          date,                           -- Día 0 del cronograma
  fecha_fin_planificada date,
  estado                text        NOT NULL DEFAULT 'activa',  -- 'activa' | 'pausada' | 'terminada'
  created_by            uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at            timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.obras IS 'Proyecto de construcción. Nodo central del que cuelga todo.';

-- ------------------------------------------------------------
-- obra_miembros
-- Qué usuarios acceden a qué obra y con qué rol.
-- responsable_key filtra qué partidas ve un supervisor/subcontrato.
-- Las funciones helper RLS (sección 15) dependen de esta tabla.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.obra_miembros (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id          uuid        NOT NULL REFERENCES public.obras(id)    ON DELETE CASCADE,
  profile_id       uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rol              text        NOT NULL,  -- 'admin' | 'jefe_obra' | 'supervisor' | 'subcontrato' | 'lectura'
  responsable_key  text,                 -- e.g. 'sucto.electrico', 'supervisor fase 1'
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (obra_id, profile_id)
);
COMMENT ON TABLE public.obra_miembros IS 'Relación usuario ↔ obra con rol y filtro de responsable.';


-- ============================================================
-- 3. ESTRUCTURA DE LA OBRA
-- Reemplaza el objeto _D hardcodeado en index.html.
-- ============================================================

-- ------------------------------------------------------------
-- pisos
-- Reemplaza _D.fl (mapa piso → departamentos)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pisos (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id    uuid        NOT NULL REFERENCES public.obras(id) ON DELETE CASCADE,
  nombre     text        NOT NULL,   -- 'Piso 2', 'Piso 3', etc.
  orden      int         NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.pisos IS 'Pisos o niveles de la obra. Reemplaza _D.fl del código.';

-- ------------------------------------------------------------
-- unidades
-- Los deptos, casas o unidades individuales. Reemplaza _D.ds.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.unidades (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id    uuid        NOT NULL REFERENCES public.obras(id)  ON DELETE CASCADE,
  piso_id    uuid        NOT NULL REFERENCES public.pisos(id)  ON DELETE CASCADE,
  codigo     text        NOT NULL,   -- '101', '202' — número del depto
  nombre     text,                   -- 'Depto 101' (opcional)
  tipo       text        NOT NULL DEFAULT 'departamento',  -- 'departamento' | 'casa' | 'local' | 'otro'
  orden      int         NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (obra_id, codigo)
);
COMMENT ON TABLE public.unidades IS 'Departamentos/unidades de la obra. Reemplaza _D.ds del código.';

-- ------------------------------------------------------------
-- fases
-- Las 4 fases de avance. Reemplaza la estructura de _D.ps/ps2/ps3/ps4.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fases (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id    uuid        NOT NULL REFERENCES public.obras(id) ON DELETE CASCADE,
  numero     int         NOT NULL,   -- 1, 2, 3, 4
  nombre     text        NOT NULL,   -- 'Fase 1', 'Estructura', etc.
  color      text        NOT NULL DEFAULT '#3b82f6',  -- Color hex para la UI
  orden      int         NOT NULL DEFAULT 0,
  UNIQUE (obra_id, numero)
);
COMMENT ON TABLE public.fases IS 'Fases de avance de la obra. Reemplaza la estructura implícita de _D.ps/ps2/ps3/ps4.';

-- ------------------------------------------------------------
-- partidas
-- Las 174 tareas de construcción. Reemplaza _D.ps, ps2, ps3, ps4
-- y PARTIDA_RESP_MAP del código.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.partidas (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id          uuid        NOT NULL REFERENCES public.obras(id)  ON DELETE CASCADE,
  fase_id          uuid        NOT NULL REFERENCES public.fases(id)  ON DELETE CASCADE,
  codigo           text,                  -- ID original en _D.ps (trazabilidad)
  nombre           text        NOT NULL,
  responsable_key  text,                  -- 'sucto.electrico', 'supervisor fase 1', etc.
  orden            int         NOT NULL DEFAULT 0,
  bloqueada        boolean     NOT NULL DEFAULT false,  -- true = % calculado automáticamente (ej: ventanas)
  created_at       timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.partidas IS 'Tareas/partidas de construcción. Reemplaza _D.ps y PARTIDA_RESP_MAP.';


-- ============================================================
-- 4. AVANCES
-- El dato más importante: % de avance por partida por unidad.
-- Reemplaza Firebase obras/victoria/saves/{depId} y _D.lf1/lf2/lf3.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.avances (
  id          uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id     uuid           NOT NULL REFERENCES public.obras(id)     ON DELETE CASCADE,
  unidad_id   uuid           NOT NULL REFERENCES public.unidades(id)  ON DELETE CASCADE,
  partida_id  uuid           NOT NULL REFERENCES public.partidas(id)  ON DELETE CASCADE,
  porcentaje  numeric(5,1)   NOT NULL DEFAULT 0
                             CHECK (porcentaje >= 0 AND porcentaje <= 100),
  updated_by  uuid           REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at  timestamptz    NOT NULL DEFAULT now(),
  UNIQUE (unidad_id, partida_id)
);
COMMENT ON TABLE public.avances IS 'Porcentaje de avance por partida por unidad. Core de la app.';

-- Historial de cambios (fase futura — tabla creada, trigger se activa cuando se necesite)
CREATE TABLE IF NOT EXISTS public.avances_historial (
  id                  uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id             uuid         NOT NULL REFERENCES public.obras(id)     ON DELETE CASCADE,
  unidad_id           uuid         NOT NULL REFERENCES public.unidades(id)  ON DELETE CASCADE,
  partida_id          uuid         NOT NULL REFERENCES public.partidas(id)  ON DELETE CASCADE,
  porcentaje_anterior numeric(5,1),
  porcentaje_nuevo    numeric(5,1) NOT NULL,
  changed_by          uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  changed_at          timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.avances_historial IS 'Auditoría de cambios en avances. Activar con trigger en avances cuando se necesite.';


-- ============================================================
-- 5. GANTT / CRONOGRAMA
-- Reemplaza PLAN, DELIVERY_OVERRIDES y ganttData de Firebase/localStorage.
-- ============================================================

-- Una fila por obra con la configuración base del cronograma.
CREATE TABLE IF NOT EXISTS public.cronograma_config (
  id                       uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id                  uuid  NOT NULL UNIQUE REFERENCES public.obras(id) ON DELETE CASCADE,
  fecha_inicio             date  NOT NULL,    -- Día 0 del cronograma
  dias_semana_laborables   int   NOT NULL DEFAULT 5,  -- 5 = lun-vie, 6 = lun-sáb
  date_shift_dias          int   NOT NULL DEFAULT 0   -- Desplazamiento global en días
);
COMMENT ON TABLE public.cronograma_config IS 'Config base del cronograma por obra. Reemplaza la fecha fija 23-Feb-2026.';

-- Cronograma base de cada unidad por fase.
-- Reemplaza PLAN.de y DELIVERY_OVERRIDES (partes dep_X y fase_X).
CREATE TABLE IF NOT EXISTS public.cronograma_unidades (
  id                   uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id              uuid  NOT NULL REFERENCES public.obras(id)    ON DELETE CASCADE,
  unidad_id            uuid  NOT NULL REFERENCES public.unidades(id) ON DELETE CASCADE,
  fase_id              uuid  NOT NULL REFERENCES public.fases(id)    ON DELETE CASCADE,
  dia_inicio           int   NOT NULL,   -- Días desde fecha_inicio del proyecto
  dia_fin              int   NOT NULL,
  dia_inicio_override  int,              -- NULL = sin override manual del usuario
  dia_fin_override     int,
  UNIQUE (unidad_id, fase_id)
);
COMMENT ON TABLE public.cronograma_unidades IS 'Cronograma por unidad/fase. Reemplaza DELIVERY_OVERRIDES del código.';

-- Cronograma a nivel de tarea individual.
-- Reemplaza PLAN.pa y los overrides pa_* del Gantt.
-- unidad_id NULL = la tarea aplica a toda la obra.
CREATE TABLE IF NOT EXISTS public.cronograma_partidas (
  id                   uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id              uuid  NOT NULL REFERENCES public.obras(id)    ON DELETE CASCADE,
  partida_id           uuid  NOT NULL REFERENCES public.partidas(id) ON DELETE CASCADE,
  unidad_id            uuid  REFERENCES public.unidades(id) ON DELETE CASCADE,
  offset_inicio        int,
  offset_fin           int,
  dia_inicio_override  int,
  dia_fin_override     int
);
-- UNIQUE con unidad_id nullable se maneja con índices parciales (sección 16)
COMMENT ON TABLE public.cronograma_partidas IS 'Cronograma por tarea individual. Reemplaza PLAN.pa y overrides pa_* del Gantt.';

-- Módulo "Plan Personal". Reemplaza weekData de Firebase.
CREATE TABLE IF NOT EXISTS public.plan_semanal (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id          uuid        NOT NULL REFERENCES public.obras(id)     ON DELETE CASCADE,
  semana_inicio    date        NOT NULL,   -- Lunes de la semana
  unidad_id        uuid        REFERENCES public.unidades(id)  ON DELETE CASCADE,
  partida_id       uuid        REFERENCES public.partidas(id)  ON DELETE CASCADE,
  responsable_key  text,
  estado           text        NOT NULL DEFAULT 'pendiente',  -- 'pendiente' | 'en_proceso' | 'completado'
  notas            text,
  created_by       uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at       timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.plan_semanal IS 'Plan de trabajo semanal. Reemplaza weekData de Firebase.';


-- ============================================================
-- 6. CONTROL VENTANAS
-- Reemplaza ctrl_vent_est_v2 y ctrl_vent_prog_v1 de localStorage.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.control_ventanas_items (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id      uuid        NOT NULL REFERENCES public.obras(id)     ON DELETE CASCADE,
  unidad_id    uuid        NOT NULL REFERENCES public.unidades(id)  ON DELETE CASCADE,
  item_codigo  text        NOT NULL,  -- 'V1', 'V2' — identificador dentro del depto
  tipo         text        NOT NULL DEFAULT 'termopanel',  -- 'marco' | 'termopanel' | 'quincalleria'
  estado       text        NOT NULL DEFAULT 'pendiente',
                           -- 'pendiente' | 'rasgo' | 'medida' | 'transito' | 'en_obra' | 'instalando' | 'completo'
  fecha_estado date,
  notas        text,
  updated_by   uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.control_ventanas_items IS 'Estado de cada ventana por unidad. Reemplaza ctrl_vent_est_v2.';

CREATE TABLE IF NOT EXISTS public.control_ventanas_programa (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id           uuid        NOT NULL REFERENCES public.obras(id)    ON DELETE CASCADE,
  unidad_id         uuid        REFERENCES public.unidades(id) ON DELETE CASCADE,
  semana_programada date,
  tipo              text,       -- 'marco' | 'termopanel' | 'quincalleria'
  notas             text,
  created_by        uuid        REFERENCES public.profiles(id) ON DELETE SET NULL
);
COMMENT ON TABLE public.control_ventanas_programa IS 'Programa de instalación de ventanas. Reemplaza ctrl_vent_prog_v1.';


-- ============================================================
-- 7. LOGÍSTICA
-- Reemplaza logData de Firebase.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.logistica_viajes (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id          uuid        NOT NULL REFERENCES public.obras(id) ON DELETE CASCADE,
  fecha            date        NOT NULL,
  hora_llegada     time,
  hora_salida      time,
  tipo             text        NOT NULL DEFAULT 'camion',  -- 'camion' | 'despacho' | 'retiro' | 'otro'
  ubicacion_estado text,       -- 'hub_oficina' | 'despacho' | 'en_obra'
  proveedor        text,
  patente          text,
  notas            text,
  created_by       uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.logistica_viajes IS 'Llegadas de camiones y despachos. Reemplaza logData de Firebase.';

CREATE TABLE IF NOT EXISTS public.logistica_materiales (
  id                  uuid     PRIMARY KEY DEFAULT gen_random_uuid(),
  viaje_id            uuid     NOT NULL REFERENCES public.logistica_viajes(id) ON DELETE CASCADE,
  nombre_material     text     NOT NULL,
  cantidad            numeric,
  unidad_medida       text,    -- 'm2' | 'un' | 'kg' | 'm'
  unidad_destino_id   uuid     REFERENCES public.unidades(id) ON DELETE SET NULL,
  notas               text
);
COMMENT ON TABLE public.logistica_materiales IS 'Materiales por viaje de logística.';


-- ============================================================
-- 8. BODEGA
-- Reemplaza bodegaData de Firebase.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.bodega_items (
  id             uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id        uuid         NOT NULL REFERENCES public.obras(id) ON DELETE CASCADE,
  nombre         text         NOT NULL,
  codigo         text,
  unidad_medida  text,        -- 'm2' | 'un' | 'kg'
  stock_actual   numeric      NOT NULL DEFAULT 0,
  stock_minimo   numeric      NOT NULL DEFAULT 0,
  created_at     timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.bodega_items IS 'Catálogo de materiales en bodega por obra.';

CREATE TABLE IF NOT EXISTS public.bodega_movimientos (
  id                  uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id             uuid         NOT NULL REFERENCES public.obras(id)        ON DELETE CASCADE,
  item_id             uuid         NOT NULL REFERENCES public.bodega_items(id) ON DELETE CASCADE,
  tipo                text         NOT NULL,  -- 'entrada' | 'salida' | 'ajuste'
  cantidad            numeric      NOT NULL,  -- positivo = entrada, negativo = salida
  unidad_destino_id   uuid         REFERENCES public.unidades(id) ON DELETE SET NULL,
  persona             text,
  notas               text,
  fecha               date         NOT NULL,
  created_by          uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at          timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.bodega_movimientos IS 'Entradas y salidas de inventario.';

CREATE TABLE IF NOT EXISTS public.bodega_vales (
  id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id      uuid         NOT NULL REFERENCES public.obras(id)    ON DELETE CASCADE,
  numero_vale  text,
  fecha        date         NOT NULL,
  persona      text         NOT NULL,
  unidad_id    uuid         REFERENCES public.unidades(id) ON DELETE SET NULL,
  estado       text         NOT NULL DEFAULT 'pendiente',  -- 'pendiente' | 'entregado' | 'anulado'
  created_by   uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at   timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.bodega_vales IS 'Vales de retiro de materiales de bodega.';

CREATE TABLE IF NOT EXISTS public.bodega_vale_items (
  id                   uuid     PRIMARY KEY DEFAULT gen_random_uuid(),
  vale_id              uuid     NOT NULL REFERENCES public.bodega_vales(id)  ON DELETE CASCADE,
  item_id              uuid     NOT NULL REFERENCES public.bodega_items(id)  ON DELETE RESTRICT,
  cantidad_pedida      numeric  NOT NULL,
  cantidad_entregada   numeric
);
COMMENT ON TABLE public.bodega_vale_items IS 'Ítems dentro de cada vale de bodega.';


-- ============================================================
-- 9. MATERIALES
-- Reemplaza matData de Firebase.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.materiales_items (
  id             uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id        uuid         NOT NULL REFERENCES public.obras(id) ON DELETE CASCADE,
  nombre         text         NOT NULL,
  codigo         text,
  unidad_medida  text,
  created_at     timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.materiales_items IS 'Catálogo de materiales operativos por obra (distinto de bodega).';

CREATE TABLE IF NOT EXISTS public.materiales_stock (
  id          uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id     uuid         NOT NULL REFERENCES public.obras(id)            ON DELETE CASCADE,
  item_id     uuid         NOT NULL REFERENCES public.materiales_items(id) ON DELETE CASCADE,
  ubicacion   text         NOT NULL,   -- 'hub' | 'bodega' | 'en_obra'
  unidad_id   uuid         REFERENCES public.unidades(id) ON DELETE SET NULL,
  cantidad    numeric      NOT NULL DEFAULT 0,
  updated_at  timestamptz  NOT NULL DEFAULT now()
);
-- UNIQUE con unidad_id nullable se maneja con índices parciales (sección 16)
COMMENT ON TABLE public.materiales_stock IS 'Stock de materiales por ubicación y unidad.';


-- ============================================================
-- 10. ASISTENCIA Y SOBRETIEMPO
-- Reemplaza asistData, stData y orgData de Firebase.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.personal (
  id                  uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id             uuid         NOT NULL REFERENCES public.obras(id) ON DELETE CASCADE,
  nombre              text         NOT NULL,
  rut                 text,
  tipo                text         NOT NULL DEFAULT 'casa',  -- 'casa' | 'subcontrato'
  subcontrato_nombre  text,
  cargo               text,
  activo              boolean      NOT NULL DEFAULT true,
  created_at          timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.personal IS 'Trabajadores de la obra (propios y subcontratos). Reemplaza base de personal de asistData.';

-- Jerarquía de cuadrillas. Soporta self-reference para organigrama.
CREATE TABLE IF NOT EXISTS public.equipos (
  id                uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id           uuid  NOT NULL REFERENCES public.obras(id) ON DELETE CASCADE,
  nombre            text  NOT NULL,
  tipo              text  NOT NULL DEFAULT 'casa',   -- 'casa' | 'subcontrato'
  supervisor_nombre text,
  parent_equipo_id  uuid  REFERENCES public.equipos(id) ON DELETE SET NULL,
  orden             int   NOT NULL DEFAULT 0
);
COMMENT ON TABLE public.equipos IS 'Cuadrillas y organigrama de equipos. Reemplaza orgData de Firebase.';

CREATE TABLE IF NOT EXISTS public.equipo_miembros (
  id           uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  equipo_id    uuid  NOT NULL REFERENCES public.equipos(id)  ON DELETE CASCADE,
  personal_id  uuid  NOT NULL REFERENCES public.personal(id) ON DELETE CASCADE,
  UNIQUE (equipo_id, personal_id)
);
COMMENT ON TABLE public.equipo_miembros IS 'Trabajadores por equipo.';

CREATE TABLE IF NOT EXISTS public.asistencia_dias (
  id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id      uuid         NOT NULL REFERENCES public.obras(id)     ON DELETE CASCADE,
  fecha        date         NOT NULL,
  personal_id  uuid         NOT NULL REFERENCES public.personal(id)  ON DELETE CASCADE,
  estado       text         NOT NULL DEFAULT 'presente',  -- 'presente' | 'ausente' | 'licencia' | 'feriado'
  horas        numeric      NOT NULL DEFAULT 8,
  notas        text,
  created_by   uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at   timestamptz  NOT NULL DEFAULT now(),
  UNIQUE (obra_id, fecha, personal_id)
);
COMMENT ON TABLE public.asistencia_dias IS 'Asistencia diaria por trabajador. Reemplaza asistData de Firebase.';

CREATE TABLE IF NOT EXISTS public.sobretiempo (
  id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id      uuid         NOT NULL REFERENCES public.obras(id)     ON DELETE CASCADE,
  fecha        date         NOT NULL,
  personal_id  uuid         NOT NULL REFERENCES public.personal(id)  ON DELETE CASCADE,
  horas_extra  numeric      NOT NULL,
  valor_hora   numeric,
  motivo       text,
  estado       text         NOT NULL DEFAULT 'pendiente',  -- 'pendiente' | 'aprobado' | 'pagado'
  aprobado_por uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_by   uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at   timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.sobretiempo IS 'Horas extra por trabajador. Reemplaza stData de Firebase.';


-- ============================================================
-- 11. RENDIMIENTO
-- Reemplaza rendData de Firebase.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.rendimiento_datos (
  id             uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id        uuid         NOT NULL REFERENCES public.obras(id) ON DELETE CASCADE,
  semana_inicio  date         NOT NULL,   -- Lunes de la semana
  fase_id        uuid         REFERENCES public.fases(id) ON DELETE CASCADE,  -- NULL = global
  tipo           text         NOT NULL,   -- 'teorico' | 'real' | 'dotacion'
  valor          numeric      NOT NULL,
  notas          text,
  created_by     uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at     timestamptz  NOT NULL DEFAULT now()
);
-- UNIQUE con fase_id nullable se maneja con índices parciales (sección 16)
COMMENT ON TABLE public.rendimiento_datos IS 'Métricas de productividad por semana y fase. Reemplaza rendData de Firebase.';


-- ============================================================
-- 12. INFORMES
-- Reemplaza reportData de Firebase.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.informes (
  id             uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id        uuid         NOT NULL REFERENCES public.obras(id) ON DELETE CASCADE,
  semana_inicio  date         NOT NULL,
  semana_fin     date         NOT NULL,
  titulo         text,
  estado         text         NOT NULL DEFAULT 'borrador',  -- 'borrador' | 'publicado'
  config_json    jsonb,       -- Configuración de qué pisos/deptos incluir
  created_by     uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at     timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.informes IS 'Informes semanales generados. Reemplaza reportData de Firebase.';


-- ============================================================
-- 13. PASILLOS Y ÁREAS COMUNES
-- Reemplaza pasillos_v1 de localStorage.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.pasillo_items (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id         uuid         NOT NULL REFERENCES public.obras(id)  ON DELETE CASCADE,
  piso_id         uuid         NOT NULL REFERENCES public.pisos(id)  ON DELETE CASCADE,
  sector          text         NOT NULL,   -- 'san_antonio' | 'huerfanos' | 'hall_ascensor' | etc.
  partida_nombre  text         NOT NULL,   -- nombre libre de la tarea en el pasillo
  porcentaje      numeric(5,1) NOT NULL DEFAULT 0
                               CHECK (porcentaje >= 0 AND porcentaje <= 100),
  updated_by      uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at      timestamptz  NOT NULL DEFAULT now(),
  UNIQUE (obra_id, piso_id, sector, partida_nombre)
);
COMMENT ON TABLE public.pasillo_items IS 'Avance en pasillos y áreas comunes. Reemplaza pasillos_v1 de localStorage.';


-- ============================================================
-- 14. PLANTILLAS GLOBALES
-- Sin obra_id. Contienen las 174 partidas de Victoria como plantilla.
-- Solo lectura para usuarios; escritura solo para service role.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.plantillas_tipo_obra (
  id           uuid     PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre       text     NOT NULL,   -- 'Edificio Residencial', 'Casa', 'Urbanización'
  tipo         text     NOT NULL,   -- 'edificio' | 'casa' | 'urbanizacion'
  descripcion  text,
  activa       boolean  NOT NULL DEFAULT true
);
COMMENT ON TABLE public.plantillas_tipo_obra IS 'Tipos de obra disponibles como plantilla base (global, sin obra_id).';

CREATE TABLE IF NOT EXISTS public.plantillas_fases (
  id                  uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  plantilla_tipo_id   uuid  NOT NULL REFERENCES public.plantillas_tipo_obra(id) ON DELETE CASCADE,
  numero              int   NOT NULL,
  nombre              text  NOT NULL,
  color               text  NOT NULL DEFAULT '#3b82f6',
  orden               int   NOT NULL DEFAULT 0
);
COMMENT ON TABLE public.plantillas_fases IS 'Fases predefinidas por tipo de obra (plantilla global).';

CREATE TABLE IF NOT EXISTS public.plantillas_partidas (
  id                   uuid     PRIMARY KEY DEFAULT gen_random_uuid(),
  plantilla_tipo_id    uuid     NOT NULL REFERENCES public.plantillas_tipo_obra(id) ON DELETE CASCADE,
  fase_numero          int      NOT NULL,
  codigo_original      text,    -- ID original en _D.ps (trazabilidad)
  nombre               text     NOT NULL,
  responsable_sugerido text,    -- De PARTIDA_RESP_MAP
  orden                int      NOT NULL DEFAULT 0,
  activa               boolean  NOT NULL DEFAULT true
);
COMMENT ON TABLE public.plantillas_partidas IS 'Las 174 partidas del Edificio Victoria como plantilla reutilizable.';


-- ============================================================
-- 15. FUNCIONES HELPER RLS
-- Se crean DESPUÉS de todas las tablas porque el cuerpo SQL
-- de cada función referencia obra_miembros y partidas.
-- ============================================================

-- Comprueba si el usuario autenticado es miembro de la obra indicada.
CREATE OR REPLACE FUNCTION public.es_miembro_obra(p_obra_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.obra_miembros
    WHERE obra_id    = p_obra_id
      AND profile_id = auth.uid()
  );
$$;

-- Devuelve el rol del usuario en la obra. NULL si no es miembro.
CREATE OR REPLACE FUNCTION public.rol_en_obra(p_obra_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT rol
  FROM public.obra_miembros
  WHERE obra_id    = p_obra_id
    AND profile_id = auth.uid()
  LIMIT 1;
$$;

-- Devuelve el responsable_key del usuario en la obra.
CREATE OR REPLACE FUNCTION public.responsable_en_obra(p_obra_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT responsable_key
  FROM public.obra_miembros
  WHERE obra_id    = p_obra_id
    AND profile_id = auth.uid()
  LIMIT 1;
$$;


-- ============================================================
-- 16. ÍNDICES
-- ============================================================

-- avances (tabla más consultada)
CREATE INDEX IF NOT EXISTS idx_avances_obra_id      ON public.avances (obra_id);
CREATE INDEX IF NOT EXISTS idx_avances_unidad_id    ON public.avances (unidad_id);
CREATE INDEX IF NOT EXISTS idx_avances_partida_id   ON public.avances (partida_id);

-- avances_historial
CREATE INDEX IF NOT EXISTS idx_avances_hist_obra    ON public.avances_historial (obra_id);
CREATE INDEX IF NOT EXISTS idx_avances_hist_detalle ON public.avances_historial (unidad_id, partida_id);

-- partidas
CREATE INDEX IF NOT EXISTS idx_partidas_obra_id     ON public.partidas (obra_id);
CREATE INDEX IF NOT EXISTS idx_partidas_fase_id     ON public.partidas (fase_id);
CREATE INDEX IF NOT EXISTS idx_partidas_resp        ON public.partidas (responsable_key)
  WHERE responsable_key IS NOT NULL;

-- unidades
CREATE INDEX IF NOT EXISTS idx_unidades_obra_id     ON public.unidades (obra_id);
CREATE INDEX IF NOT EXISTS idx_unidades_piso_id     ON public.unidades (piso_id);

-- cronograma_unidades
CREATE INDEX IF NOT EXISTS idx_crono_uni_obra       ON public.cronograma_unidades (obra_id);
CREATE INDEX IF NOT EXISTS idx_crono_uni_unidad     ON public.cronograma_unidades (unidad_id);

-- cronograma_partidas: UNIQUE parcial para unidad_id nullable
-- (una partida puede tener un cronograma global —unidad_id NULL— y además
--  overrides por unidad —unidad_id NOT NULL—)
CREATE UNIQUE INDEX IF NOT EXISTS idx_crono_part_global_unique
  ON public.cronograma_partidas (partida_id)
  WHERE unidad_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_crono_part_unidad_unique
  ON public.cronograma_partidas (partida_id, unidad_id)
  WHERE unidad_id IS NOT NULL;

-- plan_semanal
CREATE INDEX IF NOT EXISTS idx_plan_semanal_obra    ON public.plan_semanal (obra_id, semana_inicio);

-- control_ventanas_items
CREATE INDEX IF NOT EXISTS idx_ctrl_vent_unidad     ON public.control_ventanas_items (unidad_id);
CREATE INDEX IF NOT EXISTS idx_ctrl_vent_estado     ON public.control_ventanas_items (obra_id, estado);

-- logistica_viajes
CREATE INDEX IF NOT EXISTS idx_logistica_fecha      ON public.logistica_viajes (obra_id, fecha);

-- bodega
CREATE INDEX IF NOT EXISTS idx_bodega_items_obra    ON public.bodega_items (obra_id);
CREATE INDEX IF NOT EXISTS idx_bodega_mov_item      ON public.bodega_movimientos (item_id);
CREATE INDEX IF NOT EXISTS idx_bodega_vales_obra    ON public.bodega_vales (obra_id, fecha);

-- materiales_stock: UNIQUE parcial para unidad_id nullable
CREATE UNIQUE INDEX IF NOT EXISTS idx_mat_stock_global_unique
  ON public.materiales_stock (item_id, ubicacion)
  WHERE unidad_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mat_stock_unidad_unique
  ON public.materiales_stock (item_id, ubicacion, unidad_id)
  WHERE unidad_id IS NOT NULL;

-- asistencia_dias
CREATE INDEX IF NOT EXISTS idx_asist_obra_fecha     ON public.asistencia_dias (obra_id, fecha);
CREATE INDEX IF NOT EXISTS idx_asist_personal       ON public.asistencia_dias (personal_id);

-- sobretiempo
CREATE INDEX IF NOT EXISTS idx_st_obra_fecha        ON public.sobretiempo (obra_id, fecha);

-- rendimiento_datos: UNIQUE parcial para fase_id nullable
CREATE UNIQUE INDEX IF NOT EXISTS idx_rend_global_unique
  ON public.rendimiento_datos (obra_id, semana_inicio, tipo)
  WHERE fase_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_rend_fase_unique
  ON public.rendimiento_datos (obra_id, semana_inicio, fase_id, tipo)
  WHERE fase_id IS NOT NULL;

-- obra_miembros
CREATE INDEX IF NOT EXISTS idx_obra_miem_profile    ON public.obra_miembros (profile_id);
CREATE INDEX IF NOT EXISTS idx_obra_miem_obra       ON public.obra_miembros (obra_id);

-- personal
CREATE INDEX IF NOT EXISTS idx_personal_obra        ON public.personal (obra_id);

-- plantillas_partidas
CREATE INDEX IF NOT EXISTS idx_tmpl_part_tipo       ON public.plantillas_partidas (plantilla_tipo_id, fase_numero);


-- ============================================================
-- 17. ROW LEVEL SECURITY
-- ============================================================
-- Activar RLS en las 33 tablas.
-- Las funciones helper (sección 15) ya existen en este punto.
-- ============================================================

ALTER TABLE public.empresas                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.empresa_miembros          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.obras                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.obra_miembros             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pisos                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unidades                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fases                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partidas                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.avances                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.avances_historial         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cronograma_config         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cronograma_unidades       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cronograma_partidas       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_semanal              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.control_ventanas_items    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.control_ventanas_programa ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.logistica_viajes          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.logistica_materiales      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bodega_items              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bodega_movimientos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bodega_vales              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bodega_vale_items         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.materiales_items          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.materiales_stock          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.personal                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.equipos                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.equipo_miembros           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asistencia_dias           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sobretiempo               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rendimiento_datos         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.informes                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pasillo_items             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plantillas_tipo_obra      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plantillas_fases          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plantillas_partidas       ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- POLÍTICAS — profiles
-- ============================================================
DROP POLICY IF EXISTS "profiles_select_own"  ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_obra" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own"  ON public.profiles;

CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  USING (id = auth.uid());

CREATE POLICY "profiles_select_obra"
  ON public.profiles FOR SELECT
  USING (
    id IN (
      SELECT om.profile_id FROM public.obra_miembros om
      WHERE om.obra_id IN (
        SELECT obra_id FROM public.obra_miembros
        WHERE profile_id = auth.uid()
      )
    )
  );

CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  USING (id = auth.uid());

-- ============================================================
-- POLÍTICAS — empresas
-- ============================================================
DROP POLICY IF EXISTS "empresas_select_miembro" ON public.empresas;
DROP POLICY IF EXISTS "empresas_update_admin"   ON public.empresas;

CREATE POLICY "empresas_select_miembro"
  ON public.empresas FOR SELECT
  USING (
    id IN (
      SELECT empresa_id FROM public.empresa_miembros
      WHERE profile_id = auth.uid()
    )
  );

CREATE POLICY "empresas_update_admin"
  ON public.empresas FOR UPDATE
  USING (
    id IN (
      SELECT empresa_id FROM public.empresa_miembros
      WHERE profile_id = auth.uid()
        AND rol IN ('owner', 'admin')
    )
  );

-- ============================================================
-- POLÍTICAS — empresa_miembros
-- ============================================================
DROP POLICY IF EXISTS "emp_miem_select" ON public.empresa_miembros;

CREATE POLICY "emp_miem_select"
  ON public.empresa_miembros FOR SELECT
  USING (profile_id = auth.uid());

-- ============================================================
-- POLÍTICAS — obras
-- ============================================================
DROP POLICY IF EXISTS "obras_select_miembro" ON public.obras;
DROP POLICY IF EXISTS "obras_insert_empresa" ON public.obras;
DROP POLICY IF EXISTS "obras_update_admin"   ON public.obras;

CREATE POLICY "obras_select_miembro"
  ON public.obras FOR SELECT
  USING (public.es_miembro_obra(id));

CREATE POLICY "obras_insert_empresa"
  ON public.obras FOR INSERT
  WITH CHECK (
    empresa_id IN (
      SELECT empresa_id FROM public.empresa_miembros
      WHERE profile_id = auth.uid()
        AND rol IN ('owner', 'admin')
    )
  );

CREATE POLICY "obras_update_admin"
  ON public.obras FOR UPDATE
  USING (public.rol_en_obra(id) IN ('admin', 'jefe_obra'));

-- ============================================================
-- POLÍTICAS — obra_miembros
-- ============================================================
DROP POLICY IF EXISTS "obra_miem_select"       ON public.obra_miembros;
DROP POLICY IF EXISTS "obra_miem_insert_admin" ON public.obra_miembros;
DROP POLICY IF EXISTS "obra_miem_delete_admin" ON public.obra_miembros;

CREATE POLICY "obra_miem_select"
  ON public.obra_miembros FOR SELECT
  USING (public.es_miembro_obra(obra_id));

CREATE POLICY "obra_miem_insert_admin"
  ON public.obra_miembros FOR INSERT
  WITH CHECK (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));

CREATE POLICY "obra_miem_delete_admin"
  ON public.obra_miembros FOR DELETE
  USING (public.rol_en_obra(obra_id) = 'admin');

-- ============================================================
-- POLÍTICAS — pisos, unidades, fases
-- Lectura: todos los miembros. Escritura: admin/jefe_obra.
-- ============================================================
DROP POLICY IF EXISTS "pisos_select"    ON public.pisos;
DROP POLICY IF EXISTS "pisos_write"     ON public.pisos;
DROP POLICY IF EXISTS "unidades_select" ON public.unidades;
DROP POLICY IF EXISTS "unidades_write"  ON public.unidades;
DROP POLICY IF EXISTS "fases_select"    ON public.fases;
DROP POLICY IF EXISTS "fases_write"     ON public.fases;

CREATE POLICY "pisos_select"    ON public.pisos    FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "pisos_write"     ON public.pisos    FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "unidades_select" ON public.unidades FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "unidades_write"  ON public.unidades FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "fases_select"    ON public.fases    FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "fases_write"     ON public.fases    FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));

-- ============================================================
-- POLÍTICAS — partidas
-- ============================================================
DROP POLICY IF EXISTS "partidas_select" ON public.partidas;
DROP POLICY IF EXISTS "partidas_write"  ON public.partidas;

CREATE POLICY "partidas_select" ON public.partidas FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "partidas_write"  ON public.partidas FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));

-- ============================================================
-- POLÍTICAS — avances
-- Lectura: todos los miembros.
-- Escritura: admin/jefe_obra escriben todo.
--            supervisor/subcontrato solo escriben sus partidas
--            (responsable_key coincide, o no tienen filtro asignado).
-- ============================================================
DROP POLICY IF EXISTS "avances_select" ON public.avances;
DROP POLICY IF EXISTS "avances_insert" ON public.avances;
DROP POLICY IF EXISTS "avances_update" ON public.avances;
DROP POLICY IF EXISTS "avances_delete" ON public.avances;

CREATE POLICY "avances_select"
  ON public.avances FOR SELECT
  USING (public.es_miembro_obra(obra_id));

CREATE POLICY "avances_insert"
  ON public.avances FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.obra_miembros om
      WHERE om.obra_id    = avances.obra_id
        AND om.profile_id = auth.uid()
        AND om.rol IN ('admin', 'jefe_obra', 'supervisor', 'subcontrato')
        AND (
          om.rol IN ('admin', 'jefe_obra')
          OR om.responsable_key IS NULL
          OR om.responsable_key = (
            SELECT p.responsable_key FROM public.partidas p
            WHERE p.id = avances.partida_id
          )
        )
    )
  );

CREATE POLICY "avances_update"
  ON public.avances FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.obra_miembros om
      WHERE om.obra_id    = avances.obra_id
        AND om.profile_id = auth.uid()
        AND om.rol IN ('admin', 'jefe_obra', 'supervisor', 'subcontrato')
        AND (
          om.rol IN ('admin', 'jefe_obra')
          OR om.responsable_key IS NULL
          OR om.responsable_key = (
            SELECT p.responsable_key FROM public.partidas p
            WHERE p.id = avances.partida_id
          )
        )
    )
  );

CREATE POLICY "avances_delete"
  ON public.avances FOR DELETE
  USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));

-- avances_historial: solo lectura (escritura solo vía trigger de la app)
DROP POLICY IF EXISTS "avances_hist_select" ON public.avances_historial;

CREATE POLICY "avances_hist_select"
  ON public.avances_historial FOR SELECT
  USING (public.es_miembro_obra(obra_id));

-- ============================================================
-- POLÍTICAS — cronograma
-- Lectura: todos los miembros. Escritura: admin/jefe_obra.
-- ============================================================
DROP POLICY IF EXISTS "crono_cfg_select"  ON public.cronograma_config;
DROP POLICY IF EXISTS "crono_cfg_write"   ON public.cronograma_config;
DROP POLICY IF EXISTS "crono_uni_select"  ON public.cronograma_unidades;
DROP POLICY IF EXISTS "crono_uni_write"   ON public.cronograma_unidades;
DROP POLICY IF EXISTS "crono_part_select" ON public.cronograma_partidas;
DROP POLICY IF EXISTS "crono_part_write"  ON public.cronograma_partidas;
DROP POLICY IF EXISTS "plan_sem_select"   ON public.plan_semanal;
DROP POLICY IF EXISTS "plan_sem_write"    ON public.plan_semanal;

CREATE POLICY "crono_cfg_select"  ON public.cronograma_config    FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "crono_cfg_write"   ON public.cronograma_config    FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "crono_uni_select"  ON public.cronograma_unidades  FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "crono_uni_write"   ON public.cronograma_unidades  FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "crono_part_select" ON public.cronograma_partidas  FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "crono_part_write"  ON public.cronograma_partidas  FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "plan_sem_select"   ON public.plan_semanal         FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "plan_sem_write"    ON public.plan_semanal         FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra', 'supervisor', 'subcontrato'));

-- ============================================================
-- POLÍTICAS — control ventanas
-- ============================================================
DROP POLICY IF EXISTS "ctrl_vent_items_select" ON public.control_ventanas_items;
DROP POLICY IF EXISTS "ctrl_vent_items_write"  ON public.control_ventanas_items;
DROP POLICY IF EXISTS "ctrl_vent_prog_select"  ON public.control_ventanas_programa;
DROP POLICY IF EXISTS "ctrl_vent_prog_write"   ON public.control_ventanas_programa;

CREATE POLICY "ctrl_vent_items_select" ON public.control_ventanas_items    FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "ctrl_vent_items_write"  ON public.control_ventanas_items    FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra', 'supervisor', 'subcontrato'));
CREATE POLICY "ctrl_vent_prog_select"  ON public.control_ventanas_programa FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "ctrl_vent_prog_write"   ON public.control_ventanas_programa FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));

-- ============================================================
-- POLÍTICAS — logística
-- logistica_materiales no tiene obra_id propio; sube por FK a logistica_viajes.
-- ============================================================
DROP POLICY IF EXISTS "log_viajes_select" ON public.logistica_viajes;
DROP POLICY IF EXISTS "log_viajes_write"  ON public.logistica_viajes;
DROP POLICY IF EXISTS "log_mat_select"    ON public.logistica_materiales;
DROP POLICY IF EXISTS "log_mat_write"     ON public.logistica_materiales;

CREATE POLICY "log_viajes_select" ON public.logistica_viajes FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "log_viajes_write"  ON public.logistica_viajes FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra', 'supervisor'));

CREATE POLICY "log_mat_select"
  ON public.logistica_materiales FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.logistica_viajes lv
      WHERE lv.id = logistica_materiales.viaje_id
        AND public.es_miembro_obra(lv.obra_id)
    )
  );

CREATE POLICY "log_mat_write"
  ON public.logistica_materiales FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.logistica_viajes lv
      WHERE lv.id = logistica_materiales.viaje_id
        AND public.rol_en_obra(lv.obra_id) IN ('admin', 'jefe_obra', 'supervisor')
    )
  );

-- ============================================================
-- POLÍTICAS — bodega
-- bodega_vale_items no tiene obra_id propio; sube por FK a bodega_vales.
-- ============================================================
DROP POLICY IF EXISTS "bod_items_select"   ON public.bodega_items;
DROP POLICY IF EXISTS "bod_items_write"    ON public.bodega_items;
DROP POLICY IF EXISTS "bod_mov_select"     ON public.bodega_movimientos;
DROP POLICY IF EXISTS "bod_mov_write"      ON public.bodega_movimientos;
DROP POLICY IF EXISTS "bod_vales_select"   ON public.bodega_vales;
DROP POLICY IF EXISTS "bod_vales_write"    ON public.bodega_vales;
DROP POLICY IF EXISTS "bod_vale_it_select" ON public.bodega_vale_items;
DROP POLICY IF EXISTS "bod_vale_it_write"  ON public.bodega_vale_items;

CREATE POLICY "bod_items_select" ON public.bodega_items       FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "bod_items_write"  ON public.bodega_items       FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "bod_mov_select"   ON public.bodega_movimientos FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "bod_mov_write"    ON public.bodega_movimientos FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "bod_vales_select" ON public.bodega_vales       FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "bod_vales_write"  ON public.bodega_vales       FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));

CREATE POLICY "bod_vale_it_select"
  ON public.bodega_vale_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.bodega_vales bv
      WHERE bv.id = bodega_vale_items.vale_id
        AND public.es_miembro_obra(bv.obra_id)
    )
  );

CREATE POLICY "bod_vale_it_write"
  ON public.bodega_vale_items FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.bodega_vales bv
      WHERE bv.id = bodega_vale_items.vale_id
        AND public.rol_en_obra(bv.obra_id) IN ('admin', 'jefe_obra')
    )
  );

-- ============================================================
-- POLÍTICAS — materiales
-- ============================================================
DROP POLICY IF EXISTS "mat_items_select" ON public.materiales_items;
DROP POLICY IF EXISTS "mat_items_write"  ON public.materiales_items;
DROP POLICY IF EXISTS "mat_stock_select" ON public.materiales_stock;
DROP POLICY IF EXISTS "mat_stock_write"  ON public.materiales_stock;

CREATE POLICY "mat_items_select" ON public.materiales_items FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "mat_items_write"  ON public.materiales_items FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "mat_stock_select" ON public.materiales_stock FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "mat_stock_write"  ON public.materiales_stock FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));

-- ============================================================
-- POLÍTICAS — personal, equipos, asistencia, sobretiempo
-- Solo admin y jefe_obra acceden a datos de nómina.
-- equipo_miembros no tiene obra_id propio; sube por FK a equipos.
-- ============================================================
DROP POLICY IF EXISTS "personal_select"  ON public.personal;
DROP POLICY IF EXISTS "personal_write"   ON public.personal;
DROP POLICY IF EXISTS "equipos_select"   ON public.equipos;
DROP POLICY IF EXISTS "equipos_write"    ON public.equipos;
DROP POLICY IF EXISTS "eq_miem_select"   ON public.equipo_miembros;
DROP POLICY IF EXISTS "eq_miem_write"    ON public.equipo_miembros;
DROP POLICY IF EXISTS "asist_select"     ON public.asistencia_dias;
DROP POLICY IF EXISTS "asist_write"      ON public.asistencia_dias;
DROP POLICY IF EXISTS "st_select"        ON public.sobretiempo;
DROP POLICY IF EXISTS "st_write"         ON public.sobretiempo;

CREATE POLICY "personal_select" ON public.personal       FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "personal_write"  ON public.personal       FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "equipos_select"  ON public.equipos        FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "equipos_write"   ON public.equipos        FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "asist_select"    ON public.asistencia_dias FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "asist_write"     ON public.asistencia_dias FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "st_select"       ON public.sobretiempo    FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "st_write"        ON public.sobretiempo    FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));

CREATE POLICY "eq_miem_select"
  ON public.equipo_miembros FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.equipos eq
      WHERE eq.id = equipo_miembros.equipo_id
        AND public.es_miembro_obra(eq.obra_id)
    )
  );

CREATE POLICY "eq_miem_write"
  ON public.equipo_miembros FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.equipos eq
      WHERE eq.id = equipo_miembros.equipo_id
        AND public.rol_en_obra(eq.obra_id) IN ('admin', 'jefe_obra')
    )
  );

-- ============================================================
-- POLÍTICAS — rendimiento, informes, pasillo_items
-- ============================================================
DROP POLICY IF EXISTS "rend_select"    ON public.rendimiento_datos;
DROP POLICY IF EXISTS "rend_write"     ON public.rendimiento_datos;
DROP POLICY IF EXISTS "inf_select"     ON public.informes;
DROP POLICY IF EXISTS "inf_write"      ON public.informes;
DROP POLICY IF EXISTS "pasillo_select" ON public.pasillo_items;
DROP POLICY IF EXISTS "pasillo_write"  ON public.pasillo_items;

CREATE POLICY "rend_select"    ON public.rendimiento_datos FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "rend_write"     ON public.rendimiento_datos FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "inf_select"     ON public.informes          FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "inf_write"      ON public.informes          FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra'));
CREATE POLICY "pasillo_select" ON public.pasillo_items     FOR SELECT USING (public.es_miembro_obra(obra_id));
CREATE POLICY "pasillo_write"  ON public.pasillo_items     FOR ALL    USING (public.rol_en_obra(obra_id) IN ('admin', 'jefe_obra', 'supervisor'));

-- ============================================================
-- POLÍTICAS — plantillas globales
-- Solo SELECT para cualquier usuario autenticado.
-- INSERT/UPDATE/DELETE solo via service role (no se definen políticas de escritura).
-- ============================================================
DROP POLICY IF EXISTS "tmpl_tipo_select"     ON public.plantillas_tipo_obra;
DROP POLICY IF EXISTS "tmpl_fases_select"    ON public.plantillas_fases;
DROP POLICY IF EXISTS "tmpl_partidas_select" ON public.plantillas_partidas;

CREATE POLICY "tmpl_tipo_select"
  ON public.plantillas_tipo_obra FOR SELECT
  TO authenticated
  USING (activa = true);

CREATE POLICY "tmpl_fases_select"
  ON public.plantillas_fases FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "tmpl_partidas_select"
  ON public.plantillas_partidas FOR SELECT
  TO authenticated
  USING (activa = true);


-- ============================================================
-- 18. TRIGGER: AUTO-CREAR PROFILE AL REGISTRARSE
-- Se dispara cuando Supabase Auth crea un nuevo usuario.
-- El nombre se pasa como metadata al hacer signup:
--   supabase.auth.signUp({ email, password,
--     options: { data: { nombre: 'Juan Pérez' } } })
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, nombre, email)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nombre', split_part(NEW.email, '@', 1)),
    NEW.email
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- ============================================================
-- FIN DEL SCRIPT
-- ============================================================
-- Tablas:   33
-- Índices:  ~30
-- Políticas RLS: ~60
-- Funciones: 4 (es_miembro_obra, rol_en_obra, responsable_en_obra, handle_new_user)
-- Trigger: 1 (on_auth_user_created)
--
-- SIGUIENTE PASO (Etapa 0, parte 2):
--   Insertar datos de plantillas con las 174 partidas del Edificio Victoria.
--   Ver script separado: SEED_PLANTILLAS.sql (pendiente de generar).
-- ============================================================
