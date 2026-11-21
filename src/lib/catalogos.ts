export const ASESORES = ['FATIMA FONSECA', 'ANGIE ZELAYA', 'MARÍA ORDOÑEZ', 'RICARDO RUIZ']
export const MOTIVOS = ['RECOMENDACIÓN', 'CONFIANZA', 'DOCUMENTACIÓN', 'DOCUMENTACIÓN Y CONFIANZA', 'PUBLICIDAD']
export const SERVICIOS = ['RETROEXCAVADORA', 'CAMION GRUA', 'MAQUINARIA PESADA', 'TRASLADO', 'TERMOFUSION', 'ELECTROFUSION', 'ANDAMIOS', 'SUMINISTRO', 'OTRO']
export const ESTADOS = ['ENVIADO', 'EN PROCESO', 'ACEPTADO', 'RECHAZADO', 'REEMPLAZADA'] as const
export const PAGOS = ['PENDIENTE DE FACTURACIÓN', 'PENDIENTE DE PAGO', 'CANCELADO', 'NEGOCIADA', 'RECHAZADO'] as const
export const COND_PAGO = ['CONTADO', 'CRÉDITO 15 DÍAS', 'CRÉDITO 20 DÍAS', 'CRÉDITO 30 DÍAS', 'CRÉDITO 60 DÍAS', 'FACTORING 60 DÍAS']
export const UNIDADES = ['HORAS', 'DÍA', 'SERVICIO', 'VIAJE', 'UNIDAD']
export const MOTIVOS_RECHAZO = ['PRECIO', 'PLAZO / DISPONIBILIDAD', 'EL CLIENTE LO HIZO CON OTRO PROVEEDOR', 'SERVICIO NO REALIZABLE', 'SIN RESPUESTA', 'OTRO']
export const COSTO_CAT = ['PERSONAL', 'ALIMENTACIÓN / VIÁTICOS', 'PEAJES Y TRANSPORTE', 'COMBUSTIBLE', 'MAQUINARIA PROPIA', 'PROVEEDOR / SUBCONTRATO',
  'MATERIALES', 'EPP, SCTR Y REQUISITOS', 'TRÁMITES (CAPITANÍA, PERMISOS)', 'FINANCIAMIENTO (INTERESES)', 'OTROS']
export const MESES = ['ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO', 'JULIO', 'AGOSTO', 'SETIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE']
export const COND_DEF = '1.- Orden de compra y/o servicio: deberá ser enviada a nuestros correos e indicar el número de esta cotización.\n2.- Forma de pago: se realizará al finalizar el servicio solicitado.\n3.- Abono en cuenta: una vez realizado el depósito o transferencia se deberá enviar el comprobante.'

/** % de detracción sugerido por tipo de servicio (aplica desde S/ 700) */
export const DETR_DEF = (s: string) => (s === 'TRASLADO' ? 0.04 : s === 'TERMOFUSION' || s === 'ELECTROFUSION' ? 0.12 : 0.1)
export const DETR_TXT = (s: string) =>
  s === 'TRASLADO' ? 'transporte de bienes: 4%' : s === 'TERMOFUSION' || s === 'ELECTROFUSION' ? 'servicio de termofusión / electrofusión: 12%' : 'alquiler de maquinaria y demás servicios: 10%'

export interface Seccion { id: string; n: string; path?: string; fase?: number; que?: string; campos?: string[]; fuente?: string; kpi?: string[] }
export interface Area { id: string; n: string; secs: Seccion[] }

export const AREAS: Area[] = [
  { id: 'comercial', n: 'Comercial y ventas', secs: [
    { id: 'cotizaciones', n: 'Cotizaciones (RQ)', path: '/cotizaciones' },
    { id: 'clientes', n: 'Clientes', path: '/clientes' },
    { id: 'tarifario', n: 'Tarifario por cliente', path: '/tarifario' },
    { id: 'seguimiento-comercial', n: 'Seguimiento comercial', fase: 1, que: 'Embudo de cotizaciones por asesora, motivo de contacto y tipo de servicio. Metas de venta mensuales y alertas de cotizaciones sin respuesta.', campos: ['Meta mensual por asesora', 'Cotizaciones sin respuesta > 7 días', 'Motivo de rechazo', 'Clientes nuevos vs recurrentes'], fuente: 'CONTROL DE COTIZACION (hojas mensuales)', kpi: ['Conversión', 'Ventas por asesora', 'Tarifa media por servicio'] },
  ]},
  { id: 'operaciones', n: 'Operaciones y servicios', secs: [
    { id: 'programacion', n: 'Programación semanal', fase: 1, que: 'Comercial programa la semana; operaciones valida y asigna operador y equipo.', campos: ['Semana', 'RQ / cliente', 'Equipo', 'Operador y rigger', 'Fecha y hora de salida', 'Visita técnica', 'Validado por operaciones'], fuente: 'PROGRAMACIÓN SEMANAL - <equipo>.xlsx', kpi: ['Programado vs ejecutado', 'Utilización de equipos'] },
    { id: 'partes-diarios', n: 'Partes diarios', fase: 1, que: 'Registro del servicio desde el celular: horómetro, horas, recorrido, peajes y conformidad. Es el ingreso de cada equipo (tabla partes_diarios ya creada).', campos: ['N° de parte', 'Fecha', 'RQ / cliente', 'Equipo', 'Operador', 'Horómetro inicio / fin', 'Recorrido', 'Peajes', 'Tarifa', 'Conformidad'], fuente: 'ANALISIS DE UTILIDAD → hoja INGRESO SEMANAL', kpi: ['Horas efectivas vs facturables', 'Ingreso por equipo'] },
    { id: 'disponibilidad', n: 'Disponibilidad de equipos', fase: 2, que: 'Estado diario de cada equipo: en servicio, disponible, en mantenimiento o parado.', campos: ['Equipo', 'Estado', 'Cliente / ubicación', 'Desde / hasta'], fuente: 'Llamadas y WhatsApp', kpi: ['Disponibilidad mecánica'] },
    { id: 'subcontratos', n: 'Subcontrataciones', fase: 3, que: 'Equipos de terceros alquilados para cubrir servicios.', campos: ['Proveedor', 'Equipo', 'Tarifa', 'RQ'], fuente: 'Sin registro', kpi: ['Margen con subcontrato'] },
  ]},
  { id: 'mantenimiento', n: 'Mantenimiento y activos', secs: [
    { id: 'equipos', n: 'Equipos y documentos', fase: 1, que: 'Ficha única por equipo con SOAT, revisión técnica, tarjeta, TUCE y certificado de operatividad con vencimientos (tablas equipos y equipo_documentos).', campos: ['Equipo', 'Placa', 'Horómetro', 'Documentos y vencimientos'], fuente: 'Copias en cada carpeta RQ', kpi: ['Documentos por vencer'] },
    { id: 'preventivos', n: 'Plan preventivo por horómetro', fase: 2, que: 'Aceite, filtros y revisiones según horas, con alertas.', campos: ['Equipo', 'Tarea', 'Cada N horas', 'Último horómetro'], fuente: 'PLAN DE MANTENIMIENTO DE MAQUINARIAS', kpi: ['Cumplimiento del preventivo'] },
    { id: 'combustible', n: 'Combustible', fase: 1, que: 'Cada carga por equipo y servicio; cuenta corriente con el grifo (notas de venta).', campos: ['Fecha', 'Equipo', 'RQ', 'Galones', 'Precio', 'Comprobante'], fuente: 'Hojas COMBUSTIBLE y DEUDA GRIFO', kpi: ['Consumo por hora', 'Deuda con el grifo'] },
  ]},
  { id: 'rrhh', n: 'Recursos humanos', secs: [
    { id: 'personal', n: 'Personal y expedientes', fase: 2, que: 'Ficha del trabajador con contrato y certificados.', campos: ['Nombre', 'Cargo', 'Contrato', 'Certificados'], fuente: 'DOCUMENTACIÓN DEL PERSONAL', kpi: ['Costo de planilla'] },
    { id: 'asistencia', n: 'Asistencia y horas extra', fase: 2, que: 'Ingreso, salida, horas extra validadas y bolsa de horas.', campos: ['Fecha', 'Trabajador', 'Ingreso / salida', 'Horas extra', 'Validado por'], fuente: 'Formato diario firmado', kpi: ['Horas extra por mes'] },
    { id: 'vencimientos', n: 'SCTR, Vida Ley y exámenes', fase: 1, que: 'Alertas antes de que venzan seguros y exámenes.', campos: ['Trabajador', 'Documento', 'Vencimiento'], fuente: 'Sin control actual', kpi: ['Por vencer en 7 días'] },
  ]},
  { id: 'finanzas', n: 'Administración y finanzas', secs: [
    { id: 'gastos', n: 'Gastos', fase: 1, que: 'Un solo registro de gasto con equipo, RQ, tipo de gasto y caja (tabla gastos ya creada). Reemplaza EGRESOS, hojas de equipo y caja chica.', campos: ['Fecha', 'Proveedor', 'Comprobante', 'Equipo', 'RQ', 'Tipo de gasto', 'Caja / forma de pago', 'Monto'], fuente: 'ANALISIS MENSUAL → EGRESOS · CAJA CHICA', kpi: ['Gasto por equipo, proyecto y mes'] },
    { id: 'cobranzas', n: 'Cobranzas', fase: 1, que: 'Facturas por cobrar con vencimiento y días de atraso.', campos: ['Factura', 'Condición', 'Vencimiento', 'Monto cobrado'], fuente: 'Columnas de pago del control', kpi: ['Por cobrar', 'Días de cobro'] },
    { id: 'tesoreria', n: 'Préstamos y compromisos', fase: 2, que: 'Cuotas de préstamos, planilla y gastos fijos para proyectar la caja (tabla compromisos).', campos: ['Concepto', 'Monto', 'Día de pago', 'Cuotas'], fuente: 'INGRESOS Y EGRESOS <mes>.xlsx', kpi: ['Caja proyectada', 'Utilidad después de gastos fijos'] },
  ]},
  { id: 'costos', n: 'Costos y presupuestos', secs: [
    { id: 'utilidad-equipo', n: 'Rentabilidad por equipo', fase: 1, que: 'Ingreso de partes menos gastos del equipo por mes (vista v_utilidad_equipo_mes).', campos: ['Equipo', 'Mes', 'Horas', 'Ingreso', 'Gasto', 'Utilidad'], fuente: 'ANALISIS DE UTILIDAD - <equipo>.xlsx', kpi: ['Margen por equipo'] },
    { id: 'presupuesto', n: 'Presupuesto y escenarios', fase: 3, que: 'Presupuesto anual por versión y escenarios A/B/C.', campos: ['Rubro', 'Mes', 'Monto', 'Versión'], fuente: 'Sin registro', kpi: ['Desviación presupuesto vs real'] },
  ]},
  { id: 'gerencia', n: 'Inteligencia gerencial', secs: [
    { id: 'inicio', n: 'Tablero ejecutivo', path: '/inicio' },
    { id: 'alertas', n: 'Alertas', fase: 2, que: 'Lo que vence o requiere acción: cobros, documentos, mantenimientos, cuotas.', campos: ['Tipo', 'Responsable', 'Fecha límite'], fuente: 'Todas las áreas', kpi: ['Alertas abiertas'] },
  ]},
]
export const GRUPOS: [string, string[]][] = [['Gestión comercial', ['comercial']], ['Operación', ['operaciones', 'mantenimiento', 'rrhh']], ['Administración', ['finanzas', 'costos']], ['Dirección', ['gerencia']]]
export const secPath = (s: Seccion) => s.path || `/seccion/${s.id}`
export const findSec = (id: string) => { for (const a of AREAS) { const s = a.secs.find(x => x.id === id); if (s) return { a, s } } return null }
