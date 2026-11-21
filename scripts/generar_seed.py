"""
Genera supabase/seed/seed_<año>.sql a partir de los Excel actuales de MARC:
  - CONTROL DE COTIZACION <año>.xlsx  (una hoja por mes)
  - TARIFARIO CLIENTES.xlsx           (RETROEXCAVADORA, CAMIÓN GRUA, TRANSPORTE)

Uso:
  pip install openpyxl
  python scripts/generar_seed.py --control "CONTROL DE COTIZACION 2026.xlsx" \
      --tarifario "TARIFARIO CLIENTES.xlsx" --anio 2026 --out supabase/seed/seed_2026.sql

Años anteriores (el tarifario es opcional; normalmente solo se carga con el año vigente):
  python scripts/generar_seed.py --control "CONTROL DE COTIZACION 2025.xlsx" --anio 2025 \
      --out supabase/seed/seed_2025.sql
Cada año se puede cargar en cualquier orden: los clientes se reconocen por nombre normalizado
y no se duplican entre años.

Unifica los nombres de cliente (FAMEGI S.A / SA / SAC → un solo cliente) y
genera IDs fijos, así que se puede volver a ejecutar sin duplicar datos.
"""
import argparse, datetime as dt, re, unicodedata, uuid
from collections import Counter, defaultdict
import openpyxl

NS = uuid.UUID("6b9f0b6e-2a51-4c49-9a3f-5d7a3b1c0a26")
MESES = ['ENERO','FEBRERO','MARZO','ABRIL','MAYO','JUNIO','JULIO','AGOSTO','SETIEMBRE','OCTUBRE','NOVIEMBRE','DICIEMBRE']
ALIAS = {  # mismas empresas escritas distinto en el control y el tarifario
    'AGROKASA': 'SOCIEDADAGRICOLADROKASA',
    'EMPRESADESERVGRALESSIPROING': 'EMPRESADESERVICIOSGENERALESSIPROING',
    'UNNATRANSPORTE': 'UNNATRANSPORTES',
    'SOLUCIONESORDONEZ': 'SOLUCIONESGENERALESORDONEZ',
}
RUC = {'FAMEGI': '20542106124', 'EMPRESADESERVICIOSGENERALESSIPROING': '20602450491'}


def sin_tildes(s):
    return ''.join(c for c in unicodedata.normalize('NFD', s) if unicodedata.category(c) != 'Mn')


def clave(nombre):
    s = sin_tildes(str(nombre).upper().replace('\n', ' '))
    s = re.sub(r'[^A-Z0-9 ]', '', s)
    s = re.sub(r'\b(S ?A ?C|S ?A ?A|S ?A|S ?R ?L|E ?I ?R ?L|E ?R ?L|SAC|SAA|SRL|EIRL)\b', '', s)
    k = re.sub(r'\s+', '', s)
    return ALIAS.get(k, k)


def limpio(v):
    if v is None:
        return None
    if isinstance(v, str):
        v = re.sub(r'\s+', ' ', v).strip()
        return v or None
    return v


def num(v):
    return float(v) if isinstance(v, (int, float)) else None


def fecha(v):
    if isinstance(v, (dt.datetime, dt.date)) and 2020 <= v.year <= 2030:
        return v.strftime('%Y-%m-%d')
    if isinstance(v, str):
        m = re.search(r'(\d{1,2})/(\d{1,2})/(\d{4})', v)
        if m:
            return f"{m[3]}-{int(m[2]):02d}-{int(m[1]):02d}"
    return None


def servicio(desc):
    x = sin_tildes(str(desc or '').upper())
    for k, v in [('RETRO', 'RETROEXCAVADORA'), ('ENROCADO', 'MAQUINARIA PESADA'), ('LASTRE', 'MAQUINARIA PESADA'),
                 ('MAQ. PESADA', 'MAQUINARIA PESADA'), ('EXCAVADORA', 'RETROEXCAVADORA'), ('GRUA', 'CAMION GRUA'),
                 ('IZAJE', 'CAMION GRUA'), ('TERMOFUS', 'TERMOFUSION'), ('ELECTROFUS', 'ELECTROFUSION'),
                 ('ANDAMIO', 'ANDAMIOS'), ('TRASLADO', 'TRASLADO'), ('SUMINISTRO', 'SUMINISTRO'), ('VENTA', 'SUMINISTRO'),
                 ('FLANGE', 'SUMINISTRO'), ('BRIDA', 'SUMINISTRO')]:
        if k in x:
            return v
    return 'OTRO'


def q(v):
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(round(v, 4))
    return "'" + str(v).replace("'", "''") + "'"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--control', required=True)
    ap.add_argument('--tarifario', required=False, help='Opcional: solo para el año vigente')
    ap.add_argument('--anio', type=int, default=2026)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()

    nombres = defaultdict(Counter)
    filas = []
    wb = openpyxl.load_workbook(a.control, data_only=True)
    for mes in MESES:
        if mes not in wb.sheetnames:
            continue
        ws = wb[mes]
        head = [limpio(c.value) for c in ws[2]]
        idx = {h: i for i, h in enumerate(head) if h}
        g = lambda r, h: r[idx[h]] if h in idx and idx[h] < len(r) else None
        for r in ws.iter_rows(min_row=3, values_only=True):
            cli = limpio(g(r, 'CLIENTE'))
            if not cli:
                continue
            nombres[clave(cli)][cli] += 1
            filas.append((mes, r, g))

    tarifas = []
    wt = openpyxl.load_workbook(a.tarifario, data_only=True) if a.tarifario else None
    for hoja, serv in [('RETROEXCAVADORA', 'RETROEXCAVADORA'), ('CAMIÓN GRUA', 'CAMION GRUA')]:
        if not wt or hoja not in wt.sheetnames:
            continue
        for r in wt[hoja].iter_rows(min_row=3, values_only=True):
            if not r[1] or r[3] is None:
                continue
            nm = limpio(r[1]); nombres[clave(nm)][nm] += 0
            si = lambda v: str(v).strip().upper() == 'SI'
            tarifas.append(dict(c=clave(nm), servicio=serv, hmin=num(r[2]), tarifa=num(r[3]), rec=si(r[4]), alm=si(r[5]),
                                igv=si(r[6]), hd=num(r[7]), td=num(r[8])))
    if wt and 'TRANSPORTE' in wt.sheetnames:
        ultimo = None
        for r in wt['TRANSPORTE'].iter_rows(min_row=3, values_only=True):
            if r[1]:
                ultimo = limpio(r[1]); nombres[clave(ultimo)][ultimo] += 0
            if ultimo and r[2] and r[5]:
                tarifas.append(dict(c=clave(ultimo), servicio='TRASLADO', tarifa=num(r[5]), desc=limpio(r[2]),
                                    orig=limpio(r[3]), dest=limpio(r[4]), anio=r[6]))

    cid = {k: str(uuid.uuid5(NS, 'cliente:' + k)) for k in nombres if k}
    out = [f"-- Datos importados de los Excel de MARC ({a.anio}). Generado {dt.date.today()}.",
           "-- Ejecutar DESPUÉS de las migraciones, con un usuario con permisos (SQL Editor de Supabase).",
           "begin;"]

    out.append("insert into public.clientes (id, razon_social, ruc) values")
    vals = []
    vistos_ruc = set()
    for k, cnt in sorted(nombres.items(), key=lambda kv: max(kv[1].items(), key=lambda x: (x[1], len(x[0])))[0]):
        if not k:
            continue
        nombre = max(cnt.items(), key=lambda x: (x[1], len(x[0])))[0].upper()
        ruc = RUC.get(k)
        if ruc in vistos_ruc:
            ruc = None
        if ruc:
            vistos_ruc.add(ruc)
        vals.append(f"  ({q(cid[k])}, {q(nombre)}, {q(ruc)})")
    out.append(',\n'.join(vals) + "\non conflict do nothing;\n")

    if tarifas:
        out.append("insert into public.tarifas (id, cliente_id, servicio, horas_minimas, tarifa, cobra_recorrido, incluye_almuerzo, incluye_igv, horas_jornada, tarifa_jornada, descripcion, origen, destino) values")
    vals = []
    for i, t in enumerate(tarifas):
        tid = str(uuid.uuid5(NS, f"tarifa:{t['c']}:{t['servicio']}:{i}"))
        vals.append(f"  ({q(tid)}, {q(cid[t['c']])}, {q(t['servicio'])}, {q(t.get('hmin'))}, {q(t['tarifa'])}, {q(t.get('rec', False))}, "
                    f"{q(t.get('alm', False))}, {q(t.get('igv', False))}, {q(t.get('hd'))}, {q(t.get('td'))}, {q(t.get('desc'))}, {q(t.get('orig'))}, {q(t.get('dest'))})")
    if vals:
        out.append(',\n'.join(vals) + "\non conflict do nothing;\n")

    out.append("insert into public.cotizaciones (id, numero, fecha, cliente_id, sede, asesor, motivo_contacto, servicio, tipo_comprobante, estado, moneda, "
               "descripcion, subtotal, total_libre, detraccion_pct, detraccion_monto, estado_detraccion, orden_servicio, hes, comprobante, "
               "fecha_comprobante, fecha_pago, estado_pago, monto_pagado, obs_cobro, origen) values")
    vals, vistos = [], Counter()
    for mes, r, g in filas:
        numero = limpio(g(r, 'N° REQUERIMIENTO')) or f"SN-{mes}-{len(vals)+1}"
        if not re.match(r'^\d{2}-\d{3,4}-\d{2}-\d{4}$', numero):
            numero = f"{numero} ({a.anio})"   # p. ej. 'NRO DE PARTE 694 (2026)': evita choques entre años
        vistos[numero] += 1
        if vistos[numero] > 1:
            numero = f"{numero} ({vistos[numero]})"
        f = fecha(g(r, 'FECHA')) or f"{a.anio}-{MESES.index(mes)+1:02d}-01"
        sub = num(g(r, 'SUB TOTAL SOLES')) or 0
        usd = num(g(r, 'SUB TOTAL DOLARES')) or 0
        lib = num(g(r, 'TOTAL LIBRE')) or 0
        moneda = 'USD' if usd > 0 and sub == 0 else 'PEN'
        if moneda == 'USD':
            sub = usd
        pct = num(g(r, '% DETRACCIÓN')) or 0
        pct = pct / 100 if pct > 1 else pct
        tipo = 'LIBRE' if (limpio(g(r, 'TIPO DE SERVICO')) == 'LIBRE') else 'FACTURADO'
        est = limpio(g(r, 'ESTADO DEL SERVICIO')) or 'ENVIADO'
        est = est if est in ('ENVIADO', 'EN PROCESO', 'ACEPTADO', 'RECHAZADO') else 'ENVIADO'
        ed = limpio(g(r, 'ESTADO - DETRACCIÓN'))
        ed = ed if ed in ('PENDIENTE', 'CANCELADO', 'NO APLICA') else None
        ep = limpio(g(r, 'ESTADO DE PAGO'))
        ep = ep if ep in ('PENDIENTE DE FACTURACIÓN', 'PENDIENTE DE PAGO', 'CANCELADO', 'NEGOCIADA', 'RECHAZADO') else None
        desc = limpio(g(r, 'DESCRIPCIÓN'))
        obs = '; '.join(x for x in [limpio(g(r, 'OBSERVACIÓN')), limpio(g(r, 'OBSERVACION COMERCIAL'))] if x) or None
        rid = str(uuid.uuid5(NS, f"cot:{a.anio}:{numero}"))
        vals.append("  (" + ", ".join(q(x) for x in [
            rid, numero, f, cid[clave(limpio(g(r, 'CLIENTE')))], limpio(g(r, 'SEDE')), limpio(g(r, 'ASESOR DE VENTA')),
            limpio(g(r, 'MOTIVO DE CONTACTO')), servicio(desc), tipo, est, moneda, desc, sub if tipo == 'FACTURADO' else 0,
            lib, pct, num(g(r, 'MONTO DE DETRACCIÓN')) or 0, ed, limpio(str(g(r, 'N° ORDEN DE SERVICIO / COMPRA') or '')),
            limpio(str(g(r, 'N°HES / CONFORMIDAD') or '')), limpio(g(r, 'N° COMPROBANTE')), fecha(g(r, 'FECHA DE COMPROBANTE')),
            fecha(g(r, 'FECHA DE PAGO')), ep, num(g(r, 'MONTO PAGADO')), obs, f'EXCEL {a.anio}']) + ")")
    out.append(',\n'.join(vals) + "\non conflict do nothing;\n")
    out.append("commit;")
    open(a.out, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print(f"Clientes: {len(cid)} · Tarifas: {len(tarifas)} · Cotizaciones: {len(vals)} → {a.out}")


if __name__ == '__main__':
    main()
