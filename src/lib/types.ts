export type Rol = 'gerencia' | 'administracion' | 'comercial' | 'operaciones'

export interface Perfil { id: string; usuario: string; nombre: string; rol: Rol; activo: boolean }

export interface Empresa {
  razon_social: string; ruc: string; direccion: string | null; telefono: string | null; correo: string | null
  cuenta_soles: string | null; cuenta_detraccion: string | null; prefijo_base_anio: number
}

export interface Cliente {
  id: string; razon_social: string; ruc: string | null; direccion: string | null; rubro: string | null; condicion_pago: string | null
}
export interface ClienteResumen extends Cliente {
  cotizaciones: number; aceptadas: number; venta_pen: number; ultima_cotizacion: string | null; servicios_tarifa: string[] | null
}

export interface Tarifa {
  id: string; cliente_id: string; servicio: string; horas_minimas: number | null; tarifa: number
  cobra_recorrido: boolean; incluye_almuerzo: boolean; incluye_igv: boolean
  horas_jornada: number | null; tarifa_jornada: number | null
  descripcion: string | null; origen: string | null; destino: string | null; activo: boolean
  clientes?: { razon_social: string }
}

export type EstadoCot = 'ENVIADO' | 'EN PROCESO' | 'ACEPTADO' | 'RECHAZADO' | 'REEMPLAZADA'
export type EstadoPago = 'PENDIENTE DE FACTURACIÓN' | 'PENDIENTE DE PAGO' | 'CANCELADO' | 'NEGOCIADA' | 'RECHAZADO'

export interface Cotizacion {
  id: string; numero: string; fecha: string; cliente_id: string; cliente: string
  ruc: string | null; direccion: string | null; sede: string | null; contacto: string | null; correo: string | null
  asesor: string | null; motivo_contacto: string | null; servicio: string | null
  tipo_comprobante: 'FACTURADO' | 'LIBRE'; moneda: 'PEN' | 'USD'; tipo_cambio: number | null; validez_dias: number
  descripcion: string | null; mostrar_detalle: boolean
  subtotal: number; total_libre: number; detraccion_pct: number; detraccion_monto: number
  condiciones: string | null; gastos_adm_pct: number
  estado: EstadoCot; motivo_rechazo: string | null; obs_comercial: string | null
  version_de: string | null; reemplazada_por: string | null
  orden_servicio: string | null; partes: string | null; hes: string | null; condicion_pago: string | null
  comprobante: string | null; fecha_comprobante: string | null
  estado_detraccion: 'PENDIENTE' | 'CANCELADO' | 'NO APLICA' | null; estado_pago: EstadoPago | null
  fecha_pago: string | null; monto_pagado: number | null; obs_cobro: string | null; origen: string
  venta: number; igv: number; total: number; fecha_vencimiento: string | null; dias_atraso: number | null
}

export interface Item { id?: string; descripcion: string; unidad: string; cantidad: number; precio_unitario: number }
export interface Costo { id?: string; rubro: string; detalle: string | null; monto: number }
