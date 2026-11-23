-- =====================================================================
--  English Quest · base de datos para Supabase
--  Pega TODO este archivo en Supabase -> SQL Editor -> New query -> Run.
--  Se puede ejecutar más de una vez sin perder datos.
-- =====================================================================
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists eq_users(
  id bigint generated always as identity primary key,
  username text unique not null, display_name text not null, pwhash text not null, created_at text not null);
create table if not exists eq_sessions(
  sid text primary key, user_id bigint not null references eq_users(id) on delete cascade, expires timestamptz not null);
create table if not exists eq_settings(key text primary key, value text not null);
create table if not exists eq_worlds(
  id bigint generated always as identity primary key, position int not null, name text not null,
  description text not null default '', theme text not null default 'cielo', medal text not null default 'bronce',
  checkpoint_text text not null default '', character jsonb not null);
create table if not exists eq_questions(
  id bigint generated always as identity primary key, world_id bigint not null references eq_worlds(id) on delete cascade,
  position int not null, label text not null default '', objective text not null default '', prompt text not null,
  options jsonb not null, correct int not null);
create table if not exists eq_submissions(
  id bigint generated always as identity primary key, token text unique not null, full_name text not null, cycle text not null,
  course text not null, avatar jsonb not null, first_try int not null default 0, total int not null default 0,
  attempts_count int not null default 0, created_at text not null, worlds_done int not null default 0, finished int not null default 0);
create table if not exists eq_attempts(
  id bigint generated always as identity primary key, token text not null, question_id bigint, world_name text not null,
  label text not null, prompt text not null, chosen_text text not null, correct_text text not null,
  is_correct int not null, attempt_no int not null, created_at text not null);
create index if not exists idx_eq_attempts_token on eq_attempts(token);
create table if not exists eq_fails(at timestamptz not null default now());

-- Nadie puede leer ni escribir las tablas directamente desde internet: todo pasa por la función eq_api.
alter table eq_users enable row level security;
alter table eq_sessions enable row level security;
alter table eq_settings enable row level security;
alter table eq_worlds enable row level security;
alter table eq_questions enable row level security;
alter table eq_submissions enable row level security;
alter table eq_attempts enable row level security;
alter table eq_fails enable row level security;
revoke all on eq_users, eq_sessions, eq_settings, eq_worlds, eq_questions, eq_submissions, eq_attempts, eq_fails from anon, authenticated;

create or replace function eq_now() returns text language sql stable as
$$ select to_char(now() at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI:SS') $$;
create or replace function eq_res(p_status int, p_data jsonb) returns jsonb language sql immutable as
$$ select jsonb_build_object('status', p_status, 'data', p_data) $$;
create or replace function eq_err(p_status int, p_msg text) returns jsonb language sql immutable as
$$ select eq_res(p_status, jsonb_build_object('error', p_msg)) $$;
create or replace function eq_clip(v text, n int) returns text language sql immutable as
$$ select left(regexp_replace(coalesce(v, ''), '^\s+|\s+$', '', 'g'), n) $$;

create or replace function eq_char(c jsonb) returns jsonb language plpgsql immutable as $$
declare o jsonb := $q${"skin": "#f2c9a0", "hair": "#8a4b2d", "hairStyle": "bun", "outfit": "#a3237c", "outfitStyle": "robe", "accessory": "none"}$q$::jsonb; k text;
begin
  if c is null or jsonb_typeof(c) <> 'object' then return o; end if;
  foreach k in array array['skin','hair','outfit'] loop
    if (c->>k) ~ '^#[0-9a-fA-F]{6}$' then o := o || jsonb_build_object(k, lower(c->>k)); end if;
  end loop;
  if (c->>'hairStyle') = any(array['bun','short','long','spiky','cap']) then o := o || jsonb_build_object('hairStyle', c->>'hairStyle'); end if;
  if (c->>'outfitStyle') = any(array['robe','tshirt','hoodie']) then o := o || jsonb_build_object('outfitStyle', c->>'outfitStyle'); end if;
  if (c->>'accessory') = any(array['none','glasses','headphones','book']) then o := o || jsonb_build_object('accessory', c->>'accessory'); end if;
  return o;
end $$;

create or replace function eq_settings_get() returns jsonb language sql stable as $$
  select jsonb_build_object('title', $q$English Quest: El Desafío del Sílabo$q$, 'subtitle', $q$Módulo Formativo N° 2 · Interpretación y Redacción de Textos$q$, 'instructions', $q$Recorrerás 4 mundos basados en los indicadores de logro del sílabo.
Cada mundo tiene preguntas de opción múltiple y retos prácticos.
Si respondes bien, avanzas; si fallas, podrás reintentar.$q$, 'final_message', $q$Has recorrido con éxito las 17 sesiones del sílabo de Interpretación y Redacción de Textos para Diseño y Programación Web. ¡Estás preparado(a) para tu evaluación final!$q$)
    || coalesce((select jsonb_object_agg(key, value) from eq_settings
                 where key in ('title','subtitle','instructions','final_message')), '{}'::jsonb)
$$;

create or replace function eq_worlds_json(p_answers boolean) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(
    jsonb_build_object('id', w.id, 'position', w.position, 'name', w.name, 'description', w.description, 'theme', w.theme,
      'medal', w.medal, 'checkpoint_text', w.checkpoint_text, 'character', w.character,
      'questions', coalesce((select jsonb_agg(
          jsonb_build_object('id', q.id, 'world_id', q.world_id, 'label', q.label, 'objective', q.objective,
                             'prompt', q.prompt, 'options', q.options)
          || case when p_answers then jsonb_build_object('correct', q.correct) else '{}'::jsonb end
          order by q.position, q.id) from eq_questions q where q.world_id = w.id), '[]'::jsonb))
    order by w.position, w.id), '[]'::jsonb)
  from eq_worlds w
$$;

create or replace function eq_recompute(p_token text) returns jsonb language plpgsql as $$
declare v_total int; v_first int; v_count int; v_done int;
begin
  select count(*) into v_total from eq_questions;
  select count(distinct question_id) into v_first from eq_attempts where token = p_token and attempt_no = 1 and is_correct = 1;
  select count(*) into v_count from eq_attempts where token = p_token;
  select count(*) into v_done from eq_worlds w
   where exists (select 1 from eq_questions q where q.world_id = w.id)
     and not exists (select 1 from eq_questions q where q.world_id = w.id
                     and not exists (select 1 from eq_attempts a where a.token = p_token and a.question_id = q.id and a.is_correct = 1));
  update eq_submissions set first_try = v_first, total = v_total, attempts_count = v_count, worlds_done = v_done where token = p_token;
  return jsonb_build_object('first', v_first, 'total', v_total, 'done', v_done);
end $$;

create or replace function eq_move(p_table text, p_id bigint, p_dir text) returns void language plpgsql as $$
declare ids bigint[]; i int; j int; t bigint; wid bigint;
begin
  if p_table = 'worlds' then
    select array_agg(id order by position, id) into ids from eq_worlds;
  else
    select world_id into wid from eq_questions where id = p_id;
    select array_agg(id order by position, id) into ids from eq_questions where world_id = wid;
  end if;
  i := array_position(ids, p_id);
  j := case when p_dir = 'up' then i - 1 else i + 1 end;
  if i is not null and j >= 1 and j <= array_length(ids, 1) then
    t := ids[i]; ids[i] := ids[j]; ids[j] := t;
  end if;
  if p_table = 'worlds' then
    update eq_worlds w set position = x.ord - 1 from unnest(ids) with ordinality as x(id, ord) where w.id = x.id;
  else
    update eq_questions q set position = x.ord - 1 from unnest(ids) with ordinality as x(id, ord) where q.id = x.id;
  end if;
end $$;

create or replace function eq_renumber(p_table text, p_scope bigint) returns void language plpgsql as $$
begin
  if p_table = 'worlds' then
    update eq_worlds w set position = x.rn - 1 from (select id, row_number() over (order by position, id) rn from eq_worlds) x where w.id = x.id;
  else
    update eq_questions q set position = x.rn - 1 from (select id, row_number() over (order by position, id) rn from eq_questions where world_id = p_scope) x where q.id = x.id;
  end if;
end $$;

-- ---------------------------------------------------------------------
--  Función única que atiende al juego y al panel (equivale a app.py)
-- ---------------------------------------------------------------------
create or replace function eq_api(p_method text, p_path text, p_body jsonb default '{}'::jsonb, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  body jsonb := coalesce(p_body, '{}'::jsonb);
  tk text; me record; s record; w record; q record; r record; u record;
  v_name text; v_cycle text; v_course text; v_id bigint; v_choice int; v_correct int; v_n int; v_pos int;
  v_opts jsonb; v_res jsonb; v_pw text; v_username text; v_label text; v_obj text; v_prompt text;
  v_theme text; v_medal text; v_desc text; v_cp text; v_ok boolean; v_sid text; k text; lim int;
begin
  if jsonb_typeof(body) <> 'object' then body := '{}'::jsonb; end if;

  -- ============================ PÚBLICO (estudiantes) ============================
  if p_method = 'GET' and p_path = '/api/game' then
    return eq_res(200, jsonb_build_object('settings', eq_settings_get(), 'worlds',
      coalesce((select jsonb_agg(x.v order by x.o) from jsonb_array_elements(eq_worlds_json(false)) with ordinality as x(v, o)
                where jsonb_array_length(x.v->'questions') > 0), '[]'::jsonb)));
  end if;

  if p_method = 'POST' and p_path in ('/api/start', '/api/world_done', '/api/check', '/api/finish') then
    tk := body->>'token';
    if tk is null or tk !~ '^[A-Za-z0-9_-]{16,64}$' then return eq_err(400, 'Sesión inválida.'); end if;
  end if;

  if p_method = 'POST' and p_path = '/api/start' then
    v_name := eq_clip(body->>'full_name', 120);
    if v_name = '' then return eq_err(400, 'Falta tu nombre completo.'); end if;
    if length(v_name) < 3 then return eq_err(400, 'Tu nombre completo es demasiado corto.'); end if;
    v_cycle := eq_clip(body->>'cycle', 30);
    if v_cycle = '' then return eq_err(400, 'Falta el ciclo.'); end if;
    v_course := eq_clip(body->>'course', 80);
    if v_course = '' then return eq_err(400, 'Falta el curso.'); end if;
    select * into s from eq_submissions where token = tk;
    if found and s.finished = 1 then return eq_err(409, 'Esta partida ya fue enviada.'); end if;
    if found then
      update eq_submissions set full_name = v_name, cycle = v_cycle, course = v_course, avatar = eq_char(body->'avatar') where token = tk;
    else
      select count(*) into v_n from eq_questions;
      insert into eq_submissions(token, full_name, cycle, course, avatar, first_try, total, attempts_count, created_at)
      values (tk, v_name, v_cycle, v_course, eq_char(body->'avatar'), 0, v_n, 0, eq_now());
    end if;
    return eq_res(200, '{"ok":true}'::jsonb);
  end if;

  if p_method = 'POST' and p_path = '/api/world_done' then
    select * into s from eq_submissions where token = tk;
    if not found then return eq_err(400, 'Primero escribe tus datos.'); end if;
    if s.finished = 1 then return eq_err(409, 'Esta partida ya fue enviada.'); end if;
    begin v_id := (body->>'world_id')::bigint; exception when others then v_id := null; end;
    select count(*) into v_n from eq_questions qq where qq.world_id = v_id
      and not exists (select 1 from eq_attempts a where a.token = tk and a.question_id = qq.id and a.is_correct = 1);
    if v_n > 0 or not exists (select 1 from eq_worlds where id = v_id) then
      return eq_err(400, 'Aún faltan preguntas por acertar en este mundo.');
    end if;
    v_res := eq_recompute(tk);
    return eq_res(200, jsonb_build_object('saved', true, 'first_try', v_res->'first', 'total', v_res->'total', 'worlds_done', v_res->'done'));
  end if;

  if p_method = 'POST' and p_path = '/api/check' then
    select * into s from eq_submissions where token = tk;
    if not found then return eq_err(400, 'Primero escribe tus datos.'); end if;
    if s.finished = 1 then return eq_err(409, 'Esta partida ya fue enviada.'); end if;
    begin v_id := (body->>'question_id')::bigint; exception when others then v_id := null; end;
    select qq.*, ww.name as wname into q from eq_questions qq join eq_worlds ww on ww.id = qq.world_id where qq.id = v_id;
    if not found then return eq_err(404, 'Pregunta no encontrada.'); end if;
    begin v_choice := (body->>'choice')::int; exception when others then return eq_err(400, 'Opción inválida.'); end;
    if v_choice is null or v_choice < 0 or v_choice >= jsonb_array_length(q.options) then return eq_err(400, 'Opción inválida.'); end if;
    v_ok := (v_choice = q.correct);
    if exists (select 1 from eq_attempts where token = tk and question_id = q.id and is_correct = 1) then
      return eq_res(200, jsonb_build_object('correct', v_ok, 'repeat', true));
    end if;
    select count(*) + 1 into v_n from eq_attempts where token = tk and question_id = q.id;
    insert into eq_attempts(token, question_id, world_name, label, prompt, chosen_text, correct_text, is_correct, attempt_no, created_at)
    values (tk, q.id, q.wname, q.label, q.prompt, q.options->>v_choice, q.options->>q.correct, case when v_ok then 1 else 0 end, v_n, eq_now());
    -- se guarda el avance en cada respuesta, así la profesora lo ve al instante
    perform eq_recompute(tk);
    return eq_res(200, jsonb_build_object('correct', v_ok, 'attempt', v_n));
  end if;

  if p_method = 'POST' and p_path = '/api/finish' then
    select * into s from eq_submissions where token = tk;
    if not found then return eq_err(400, 'Primero escribe tus datos.'); end if;
    if s.finished = 1 then return eq_err(409, 'Esta partida ya fue enviada.'); end if;
    if not exists (select 1 from eq_attempts where token = tk) then return eq_err(400, 'Aún no has respondido ninguna pregunta.'); end if;
    v_res := eq_recompute(tk);
    update eq_submissions set finished = 1, avatar = eq_char(body->'avatar') where token = tk;
    return eq_res(200, jsonb_build_object('ok', true, 'first_try', v_res->'first', 'total', v_res->'total'));
  end if;

  -- ============================ LOGIN ============================
  if p_method = 'POST' and p_path = '/api/admin/login' then
    delete from eq_fails where at < now() - interval '1 day';
    select count(*) into v_n from eq_fails where at > now() - interval '5 minutes';
    if v_n >= 20 then return eq_err(429, 'Demasiados intentos. Espera unos minutos.'); end if;
    select * into u from eq_users where username = eq_clip(body->>'username', 40);
    if not found or u.pwhash <> crypt(coalesce(body->>'password', ''), u.pwhash) then
      insert into eq_fails default values;
      return eq_err(401, 'Usuario o contraseña incorrectos.');
    end if;
    delete from eq_sessions where expires < now();
    v_sid := encode(gen_random_bytes(32), 'hex');
    insert into eq_sessions(sid, user_id, expires) values (v_sid, u.id, now() + interval '8 hours');
    return eq_res(200, jsonb_build_object('ok', true, 'token', v_sid));
  end if;

  -- ============================ ADMINISTRADORA (requiere sesión) ============================
  if p_path not like '/api/admin/%' then return eq_err(404, 'Ruta no encontrada.'); end if;
  select uu.* into me from eq_sessions ss join eq_users uu on uu.id = ss.user_id where ss.sid = p_token and ss.expires > now();
  if not found then return eq_err(401, 'Inicia sesión.'); end if;

  if p_method = 'POST' and p_path = '/api/admin/logout' then
    delete from eq_sessions where sid = p_token;
    return eq_res(200, '{"ok":true}'::jsonb);
  end if;

  if p_method = 'GET' and p_path = '/api/admin/me' then
    return eq_res(200, jsonb_build_object('id', me.id, 'username', me.username, 'display_name', me.display_name,
                                          'default_password', me.pwhash = crypt('admin123', me.pwhash)));
  end if;

  -- resultados
  if p_method = 'GET' and p_path = '/api/admin/submissions' then
    return eq_res(200, coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'full_name', x.full_name, 'cycle', x.cycle,
        'course', x.course, 'avatar', x.avatar, 'first_try', x.first_try, 'total', x.total, 'attempts_count', x.attempts_count,
        'created_at', x.created_at, 'worlds_done', x.worlds_done, 'finished', x.finished) order by x.id desc) from eq_submissions x), '[]'::jsonb));
  end if;

  if p_path ~ '^/api/admin/submissions/\d+$' then
    v_id := substring(p_path from '(\d+)$')::bigint;
    select * into s from eq_submissions where id = v_id;
    if not found then return eq_err(404, 'No existe.'); end if;
    if p_method = 'GET' then
      return eq_res(200, to_jsonb(s) || jsonb_build_object('attempts',
        coalesce((select jsonb_agg(to_jsonb(a) order by a.id) from eq_attempts a where a.token = s.token), '[]'::jsonb)));
    elsif p_method = 'DELETE' then
      delete from eq_attempts where token = s.token;
      delete from eq_submissions where id = v_id;
      return eq_res(200, '{"ok":true}'::jsonb);
    end if;
  end if;

  if p_method = 'GET' and p_path = '/api/admin/stats' then
    return eq_res(200, coalesce((select jsonb_agg(jsonb_build_object('world_name', t.world_name, 'label', t.label, 'prompt', t.prompt,
        'students', t.students, 'first_ok', t.first_ok, 'attempts', t.attempts) order by t.m) from (
        select a.world_name, a.label, a.prompt, count(distinct a.token) students,
               coalesce(sum(case when a.attempt_no = 1 and a.is_correct = 1 then 1 else 0 end), 0)::int first_ok,
               count(*) attempts, min(a.id) m
          from eq_attempts a join eq_submissions s2 on s2.token = a.token group by a.world_name, a.label, a.prompt) t), '[]'::jsonb));
  end if;

  if p_method = 'GET' and p_path = '/api/admin/export.csv' then
    return eq_res(200, jsonb_build_object('rows', coalesce((select jsonb_agg(jsonb_build_array(s3.full_name, s3.cycle, s3.course,
        a.created_at, a.world_name, a.label, a.prompt, a.chosen_text, a.correct_text,
        case when a.is_correct = 1 then 'Sí' else 'No' end, a.attempt_no) order by s3.id, a.id)
        from eq_attempts a join eq_submissions s3 on s3.token = a.token), '[]'::jsonb)));
  end if;

  -- mundos y preguntas
  if p_method = 'GET' and p_path = '/api/admin/worlds' then
    return eq_res(200, eq_worlds_json(true));
  end if;

  if p_path = '/api/admin/worlds' and p_method = 'POST' then
    v_name := eq_clip(body->>'name', 80);
    if v_name = '' then return eq_err(400, 'Falta el nombre del mundo.'); end if;
    v_theme := case when body->>'theme' = any(array['cielo','ciudad','noche','atardecer','bosque']) then body->>'theme' else 'cielo' end;
    v_medal := case when body->>'medal' = any(array['bronce','plata','oro','trofeo']) then body->>'medal' else 'bronce' end;
    select coalesce(max(position), -1) + 1 into v_pos from eq_worlds;
    insert into eq_worlds(position, name, description, theme, medal, checkpoint_text, character)
    values (v_pos, v_name, eq_clip(body->>'description', 120), v_theme, v_medal, eq_clip(body->>'checkpoint_text', 300), eq_char(body->'character'))
    returning id into v_id;
    return eq_res(200, jsonb_build_object('id', v_id));
  end if;

  if p_path ~ '^/api/admin/worlds/\d+(/move)?$' then
    v_id := substring(p_path from '^/api/admin/worlds/(\d+)')::bigint;
    if not exists (select 1 from eq_worlds where id = v_id) then return eq_err(404, 'No existe el mundo.'); end if;
    if p_path like '%/move' and p_method = 'POST' then
      perform eq_move('worlds', v_id, case when body->>'dir' = 'up' then 'up' else 'down' end);
    elsif p_method = 'PUT' then
      v_name := eq_clip(body->>'name', 80);
      if v_name = '' then return eq_err(400, 'Falta el nombre del mundo.'); end if;
      v_theme := case when body->>'theme' = any(array['cielo','ciudad','noche','atardecer','bosque']) then body->>'theme' else 'cielo' end;
      v_medal := case when body->>'medal' = any(array['bronce','plata','oro','trofeo']) then body->>'medal' else 'bronce' end;
      update eq_worlds set name = v_name, description = eq_clip(body->>'description', 120), theme = v_theme, medal = v_medal,
             checkpoint_text = eq_clip(body->>'checkpoint_text', 300), character = eq_char(body->'character') where id = v_id;
    elsif p_method = 'DELETE' then
      delete from eq_worlds where id = v_id;
      perform eq_renumber('worlds', null);
    else
      return eq_err(405, 'Método no permitido.');
    end if;
    return eq_res(200, '{"ok":true}'::jsonb);
  end if;

  if p_path ~ '^/api/admin/questions(/\d+(/move)?)?$' then
    -- validación común de pregunta (POST y PUT)
    if p_method in ('POST', 'PUT') and p_path !~ '/move$' then
      if jsonb_typeof(body->'options') is distinct from 'array' then return eq_err(400, 'Faltan las opciones.'); end if;
      select jsonb_agg(eq_clip(o, 200)), count(*), count(*) filter (where eq_clip(o, 200) = '')
        into v_opts, v_n, v_pos from jsonb_array_elements_text(body->'options') o;
      if v_n < 2 or v_n > 4 or v_pos > 0 then return eq_err(400, 'Debe haber entre 2 y 4 opciones, todas con texto.'); end if;
      begin v_correct := (body->>'correct')::int; exception when others then return eq_err(400, 'Indica cuál es la respuesta correcta.'); end;
      if v_correct is null then return eq_err(400, 'Indica cuál es la respuesta correcta.'); end if;
      if v_correct < 0 or v_correct >= v_n then return eq_err(400, 'Respuesta correcta inválida.'); end if;
      v_prompt := eq_clip(body->>'prompt', 500);
      if v_prompt = '' then return eq_err(400, 'Falta la pregunta.'); end if;
      v_label := eq_clip(body->>'label', 80); v_obj := eq_clip(body->>'objective', 300);
    end if;

    if p_path = '/api/admin/questions' and p_method = 'POST' then
      begin v_id := (body->>'world_id')::bigint; exception when others then v_id := null; end;
      if not exists (select 1 from eq_worlds where id = v_id) then return eq_err(404, 'No existe el mundo.'); end if;
      select coalesce(max(position), -1) + 1 into v_pos from eq_questions where world_id = v_id;
      insert into eq_questions(world_id, position, label, objective, prompt, options, correct)
      values (v_id, v_pos, v_label, v_obj, v_prompt, v_opts, v_correct) returning id into v_id;
      return eq_res(200, jsonb_build_object('id', v_id));
    end if;

    v_id := substring(p_path from '^/api/admin/questions/(\d+)')::bigint;
    select * into q from eq_questions where id = v_id;
    if not found then return eq_err(404, 'No existe la pregunta.'); end if;
    if p_path like '%/move' and p_method = 'POST' then
      perform eq_move('questions', v_id, case when body->>'dir' = 'up' then 'up' else 'down' end);
    elsif p_method = 'PUT' then
      update eq_questions set label = v_label, objective = v_obj, prompt = v_prompt, options = v_opts, correct = v_correct where id = v_id;
    elsif p_method = 'DELETE' then
      delete from eq_questions where id = v_id;
      perform eq_renumber('questions', q.world_id);
    else
      return eq_err(405, 'Método no permitido.');
    end if;
    return eq_res(200, '{"ok":true}'::jsonb);
  end if;

  -- textos
  if p_path = '/api/admin/settings' then
    if p_method = 'GET' then return eq_res(200, eq_settings_get()); end if;
    if p_method = 'PUT' then
      foreach k in array array['title','subtitle','instructions','final_message'] loop
        if body ? k then
          lim := case k when 'title' then 100 when 'subtitle' then 160 when 'instructions' then 600 else 400 end;
          v_label := eq_clip(body->>k, lim);
          if k = 'title' and v_label = '' then return eq_err(400, 'Falta title.'); end if;
          insert into eq_settings(key, value) values (k, v_label) on conflict (key) do update set value = excluded.value;
        end if;
      end loop;
      return eq_res(200, '{"ok":true}'::jsonb);
    end if;
  end if;

  -- administradores
  if p_path = '/api/admin/users' and p_method = 'GET' then
    return eq_res(200, coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'username', x.username,
        'display_name', x.display_name, 'created_at', x.created_at) order by x.id) from eq_users x), '[]'::jsonb));
  end if;

  if p_path = '/api/admin/users' and p_method = 'POST' then
    v_username := eq_clip(body->>'username', 32);
    if v_username = '' then return eq_err(400, 'Falta el usuario.'); end if;
    if v_username !~ '^[a-zA-Z0-9_.-]{3,32}$' then return eq_err(400, 'Usuario: 3 a 32 caracteres (letras, números, . _ -).'); end if;
    v_pw := coalesce(body->>'password', '');
    if length(v_pw) < 6 then return eq_err(400, 'La contraseña debe tener al menos 6 caracteres.'); end if;
    if exists (select 1 from eq_users where username = v_username) then return eq_err(409, 'Ese usuario ya existe.'); end if;
    v_name := eq_clip(body->>'display_name', 80);
    if v_name = '' then return eq_err(400, 'Falta el nombre.'); end if;
    insert into eq_users(username, display_name, pwhash, created_at) values (v_username, v_name, crypt(v_pw, gen_salt('bf', 8)), eq_now())
    returning id into v_id;
    return eq_res(200, jsonb_build_object('id', v_id));
  end if;

  if p_path ~ '^/api/admin/users/\d+(/password)?$' then
    v_id := substring(p_path from '^/api/admin/users/(\d+)')::bigint;
    if not exists (select 1 from eq_users where id = v_id) then return eq_err(404, 'No existe el usuario.'); end if;
    if p_path like '%/password' and p_method = 'PUT' then
      v_pw := coalesce(body->>'password', '');
      if length(v_pw) < 6 then return eq_err(400, 'La contraseña debe tener al menos 6 caracteres.'); end if;
      update eq_users set pwhash = crypt(v_pw, gen_salt('bf', 8)) where id = v_id;
    elsif p_method = 'DELETE' then
      if v_id = me.id then return eq_err(400, 'No puedes eliminar tu propia cuenta.'); end if;
      delete from eq_users where id = v_id;
    else
      return eq_err(405, 'Método no permitido.');
    end if;
    return eq_res(200, '{"ok":true}'::jsonb);
  end if;

  return eq_err(404, 'Ruta no encontrada.');
end $$;

revoke all on function eq_api(text, text, jsonb, text) from public;
grant execute on function eq_api(text, text, jsonb, text) to anon, authenticated;

-- Datos iniciales (solo si la base está vacía)
do $seed$ begin
  if not exists (select 1 from eq_users) then
    insert into eq_users(username, display_name, pwhash, created_at) values ('admin', 'Administrador', extensions.crypt('admin123', extensions.gen_salt('bf', 8)), eq_now());
  end if;
  if not exists (select 1 from eq_worlds) then
    with nw as (insert into eq_worlds(position,name,description,theme,medal,checkpoint_text,character) values (0, $q$Pasado y Voz Pasiva$q$, $q$Sesiones 1 a 4$q$, $q$cielo$q$, $q$bronce$q$, $q$¡Has superado el Bloque 1! Dominaste el Pasado Simple y la Voz Pasiva (Sesiones 1 a 4).$q$, $q${"skin": "#f2c9a0", "hair": "#8a4b2d", "hairStyle": "bun", "outfit": "#a3237c", "outfitStyle": "robe", "accessory": "none"}$q$::jsonb) returning id)
    insert into eq_questions(world_id,position,label,objective,prompt,options,correct) values
      ((select id from nw), 0, $q$Nivel 1 - Reto 1$q$, $q$Utiliza el Simple Past empleando verbos regulares e irregulares.$q$, $q$¿Cuál es la forma correcta en pasado del verbo code y el verbo be (para the server)?$q$, $q$["coded / were", "code / was", "coded / was"]$q$::jsonb, 2),
      ((select id from nw), 1, $q$Nivel 1 - Reto 2$q$, $q$Identifica la estructura de la voz pasiva en presente.$q$, $q$En tu carrera lees documentación técnica. ¿Cómo se dice "El código es compilado"?$q$, $q$["The code is compiled", "The code compiles", "The code was compiled"]$q$::jsonb, 0),
      ((select id from nw), 2, $q$Nivel 1 - Reto 3$q$, $q$Analiza un texto en voz pasiva del tiempo pasado.$q$, $q$Selecciona la oración redactada correctamente en voz pasiva pasada:$q$, $q$["The web pages were designed by the developer.", "The web pages was design by the developer.", "The web pages are designed yesterday."]$q$::jsonb, 0);
    with nw as (insert into eq_worlds(position,name,description,theme,medal,checkpoint_text,character) values (1, $q$Continuos y Futuros$q$, $q$Sesiones 5 a 7$q$, $q$ciudad$q$, $q$plata$q$, $q$¡Excelente trabajo! Ya dominas los tiempos continuos y los planes de desarrollo a futuro (Sesiones 5 a 7).$q$, $q${"skin": "#f2c9a0", "hair": "#8a4b2d", "hairStyle": "bun", "outfit": "#a3237c", "outfitStyle": "robe", "accessory": "none"}$q$::jsonb) returning id)
    insert into eq_questions(world_id,position,label,objective,prompt,options,correct) values
      ((select id from nw), 0, $q$Nivel 2 - Reto 1$q$, $q$Comprende la estructura del presente continuo y reglas de gerundio (-ing).$q$, $q$¿Cuál es la forma correcta del verbo debug (depurar código) en gerundio?$q$, $q$["debuging", "debugging", "debuged"]$q$::jsonb, 1),
      ((select id from nw), 1, $q$Nivel 2 - Reto 2$q$, $q$Expresa planes futuros con going to en situaciones cotidianas y laborales.$q$, $q$Completa la frase: "We _____ launch the new mobile app next week."$q$, $q$["is going to", "are going to", "will going to"]$q$::jsonb, 1),
      ((select id from nw), 2, $q$Nivel 2 - Reto 3$q$, $q$Auxiliar Will: promesas, predicciones y decisiones de momento.$q$, $q$Si un usuario reporta un error en la web y decides arreglarlo al instante, ¿qué dices?$q$, $q$["I will fix that bug right now!", "I am going to fix it yesterday.", "I fix it last week."]$q$::jsonb, 0);
    with nw as (insert into eq_worlds(position,name,description,theme,medal,checkpoint_text,character) values (2, $q$Modales e Imperativos$q$, $q$Sesiones 8 a 14$q$, $q$noche$q$, $q$oro$q$, $q$¡Impresionante avance! Has dominado la redacción de instrucciones de usuario y documentación técnica intermedia (Sesiones 8 a 14).$q$, $q${"skin": "#f2c9a0", "hair": "#8a4b2d", "hairStyle": "bun", "outfit": "#a3237c", "outfitStyle": "robe", "accessory": "none"}$q$::jsonb) returning id)
    insert into eq_questions(world_id,position,label,objective,prompt,options,correct) values
      ((select id from nw), 0, $q$Nivel 3 - Reto 1$q$, $q$Usa verbos modales (can, could, should, must) para expresar habilidades y obligaciones.$q$, $q$¿Qué modal indica una prohibición estricta de seguridad informática?$q$, $q$["Mustn't", "Can", "Might"]$q$::jsonb, 0),
      ((select id from nw), 1, $q$Nivel 3 - Reto 2$q$, $q$Emplea verbos imperativos elaborando instrucciones y advertencias (Don't + verb).$q$, $q$Traduce la advertencia de sistema: "No borre la base de datos".$q$, $q$["You don't delete the database.", "Don't delete the database!", "Let's delete the database."]$q$::jsonb, 1),
      ((select id from nw), 2, $q$Nivel 3 - Reto 3$q$, $q$Práctica intermedia integrando voz pasiva, will y going to.$q$, $q$¿Cuál de los siguientes enunciados redacta correctamente un objetivo de desarrollo web?$q$, $q$["\"Next month, I will optimize the website loading speed.\"", "\"Next month, I optimizing website speed.\"", "\"Next month, website speed was optimize.\""]$q$::jsonb, 0);
    with nw as (insert into eq_worlds(position,name,description,theme,medal,checkpoint_text,character) values (3, $q$Reported Speech y Cierre$q$, $q$Sesiones 15 a 17$q$, $q$atardecer$q$, $q$trofeo$q$, $q$¡Completaste el último mundo! Ya sabes reportar lo que dicen los clientes y redactar tu proyecto final.$q$, $q${"skin": "#f2c9a0", "hair": "#8a4b2d", "hairStyle": "bun", "outfit": "#a3237c", "outfitStyle": "robe", "accessory": "none"}$q$::jsonb) returning id)
    insert into eq_questions(world_id,position,label,objective,prompt,options,correct) values
      ((select id from nw), 0, $q$Nivel 4 - Reto 1$q$, $q$Analiza el discurso indirecto (Reported Speech) en tiempos presentes y pasados.$q$, $q$Si un cliente dice en presente: "I need an online store", ¿cómo cambia el verbo en reported speech (pasado)?$q$, $q$["needed (pasa a pasado simple)", "needing", "Se queda exactamente igual sin cambios."]$q$::jsonb, 0),
      ((select id from nw), 1, $q$Nivel 4 - Reto Final$q$, $q$Redacta un texto integrando las diversas estructuras gramaticales referidas a Diseño y Programación Web.$q$, $q$Para cerrar con éxito el curso, ¿qué debes demostrar en tu proyecto final?$q$, $q$["Solo memorizar etiquetas HTML sin gramática en inglés.", "Aplicar de forma coherente tiempos verbales, voz pasiva y redacción técnica vinculada al desarrollo web y móvil.", "No entregar nada."]$q$::jsonb, 1);
  end if;
end $seed$;
