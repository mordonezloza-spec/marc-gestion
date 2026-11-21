-- =====================================================================
-- MARC · Usuarios y roles
-- 1) Supabase → Authentication → Users → Add user → Create new user
--    Crea cada correo con su contraseña y marca "Auto Confirm User":
--      mordonez@marc-eirl.com · azelaya@marc-eirl.com · ffonseca@marc-eirl.com · rruiz@marc-eirl.com
-- 2) Luego ejecuta este script en el SQL Editor.
-- Para agregar a alguien después, añade una línea en VALUES y vuelve a ejecutar.
-- Roles: gerencia | administracion | comercial | operaciones
-- =====================================================================
insert into public.perfiles (id, usuario, nombre, rol)
select u.id, upper(split_part(u.email, '@', 1)), v.nombre, v.rol
from auth.users u
join (values
  ('mordonez@marc-eirl.com', 'María Ordoñez',  'gerencia'),
  ('azelaya@marc-eirl.com',  'Angie Zelaya',   'administracion'),
  ('ffonseca@marc-eirl.com', 'Fátima Fonseca', 'comercial'),
  ('rruiz@marc-eirl.com',    'Ricardo Ruiz',   'operaciones')
) as v(email, nombre, rol) on v.email = u.email
on conflict (id) do update set nombre = excluded.nombre, rol = excluded.rol, activo = true;

-- Verificación: debe listar los usuarios con su rol
select p.usuario, p.nombre, p.rol, u.email
from public.perfiles p join auth.users u on u.id = p.id
order by p.rol, p.usuario;
