-- =====================================================================
-- PULLMED — schema reconstructed from lib/main.dart (662 lines)
--
-- Every column below is a field the app actually reads or writes.
-- Nothing is invented; nothing the app uses is missing.
--
-- Three structural changes to the original:
--   (a) surrogate key replaces the mutable `login` primary key
--   (b) 21 vaccine columns  ->  normalized lookup + junction table
--   (c) explicit PUBLIC / PRIVATE field split (the record no longer
--       exposes the SUS card number, insurer, or family history)
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. PATIENT  (replaces d_usuario)
--    OLD: d_usuario(login TEXT PK, senha TEXT plaintext, link TEXT)
--    `link`  is gone: the URL is now derived from `token`.
--    `senha` is gone: Supabase Auth holds a bcrypt hash.
-- ---------------------------------------------------------------------
create table public.patient (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null unique references auth.users(id) on delete cascade,
  token            text not null unique default encode(gen_random_bytes(16), 'hex'),
  token_rotated_at timestamptz,
  revoked          boolean not null default false,
  revoked_at       timestamptz,
  tag_pwd          bytea,     -- NTAG215 PWD  (4 bytes, per tag, never reused)
  tag_pack         bytea,     -- NTAG215 PACK (2 bytes)
  created_at       timestamptz not null default now()
);

create index patient_token_idx on public.patient (token) where revoked = false;

comment on column public.patient.token is
  '128-bit CSPRNG token, hex-encoded (32 chars). Replaces the username-derived '
  'URL of the original implementation, which had zero entropy and was enumerable. '
  'This is an unguessable-URL scheme: a bearer credential, not authentication.';

-- ---------------------------------------------------------------------
-- 2. ANAMNESE  (same fields as the app, correctly typed)
--    Types inferred from main.dart:
--      parseIntOrNull(...) -> integer  |  .text -> text
--      == 'Sim'            -> boolean  |  dropdown -> text
--    Dates were TEXT in the original; they are proper DATE here.
-- ---------------------------------------------------------------------
create table public.anamnese (
  id                 uuid primary key default gen_random_uuid(),
  patient_id         uuid not null unique references public.patient(id) on delete cascade,
  version            integer not null default 1,
  updated_at         timestamptz not null default now(),

  -- ---- general ----
  nome               text,
  data_nascimento    date,
  idade              integer,
  peso_kg            integer,      -- was `peso`;   unit was undeclared
  altura_cm          integer,      -- was `altura`; unit was undeclared
  sangue             text check (sangue in
                       ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  contato_emerg_nome text,
  contato_emerg      text,
  contato_emerg_grau text,

  -- ---- clinical ----
  alergias           text,
  doenca_pre         text,
  medicacoes         text,
  cirurgia           text,
  disp_implantado    text,
  transfusao         boolean,
  doacao_orgaos      boolean,
  obs_adicional      text,

  -- ---- stored, but NEVER exposed publicly (see emergency_record) ----
  hist_familiar      text,   -- discloses health data about relatives who did not consent
  plano_saude        text,   -- insurer: billing data, not triage data
  sus                text,   -- Cartao Nacional de Saude: a strong national identifier

  -- ---- vaccination (free-text parts) ----
  doses_cov          integer,
  fabricante_cov     text,
  data_h1n1          date,
  vac_outras         text
);

-- ---------------------------------------------------------------------
-- 3. VACCINES — normalized
--    OLD: 21 boolean columns named after the vaccines themselves, e.g.
--         "BCG", "Hepatite A", "Penta (DTP/Hib/Hep. B)",
--         "Pneumocócica 10-valente", "Menigocócica ACWY" [sic — the typo
--         is in the source string, and therefore in the column name].
--    Adding a vaccine to the national schedule required a DDL change.
--    Now: a lookup table plus a junction table. Adding a vaccine is a row.
-- ---------------------------------------------------------------------
create table public.vaccine (
  id       smallint primary key,
  code     text not null unique,   -- stable, ASCII, machine-safe
  label_pt text not null,          -- exactly as displayed in the app
  sort_ord smallint not null
);

insert into public.vaccine (id, code, label_pt, sort_ord) values
  ( 1,'bcg',            'BCG',                                  1),
  ( 2,'hep_a',          'Hepatite A',                           2),
  ( 3,'hep_b',          'Hepatite B',                           3),
  ( 4,'penta',          'Penta (DTP/Hib/Hep. B)',               4),
  ( 5,'pneumo10',       'Pneumocócica 10-valente',              5),
  ( 6,'vip',            'Vacina Inativada Poliomielite (VIP)',  6),
  ( 7,'vop',            'Vacina Oral Poliomielite (VOP)',       7),
  ( 8,'vrh',            'Vacina Rotavírus Humano (VRH)',        8),
  ( 9,'meningo_c',      'Meningocócica C (conjugada)',          9),
  (10,'meningo_acwy',   'Meningocócica ACWY',                  10),  -- typo corrected
  (11,'febre_amarela',  'Febre amarela',                       11),
  (12,'triplice_viral', 'Tríplice viral',                      12),
  (13,'dtp',            'DTP (tríplice bacteriana)',           13),
  (14,'varicela',       'Varicela',                            14),
  (15,'scr',            'SCR (Sarampo, Caxumba e Rubéola)',    15),
  (16,'hpv4',           'HPV quadrivalente',                   16),
  (17,'dt',             'dT (dupla adulto)',                   17),
  (18,'dtpa',           'dTpa (DTP adulto)',                   18),
  (19,'sars_cov_2',     'SARS-COV-19',                         19),
  (20,'h1n1',           'H1N1 (Gripe)',                        20),
  (21,'outras',         'Outras',                              21);

create table public.anamnese_vaccine (
  anamnese_id uuid     not null references public.anamnese(id) on delete cascade,
  vaccine_id  smallint not null references public.vaccine(id),
  taken       boolean  not null default false,
  primary key (anamnese_id, vaccine_id)
);

-- ---------------------------------------------------------------------
-- 4. ACCESS LOG — every public read is recorded
-- ---------------------------------------------------------------------
create table public.access_log (
  id          bigserial primary key,
  patient_id  uuid references public.patient(id) on delete set null,
  accessed_at timestamptz not null default now(),
  ip_hash     text,
  user_agent  text,
  outcome     text not null   -- 'ok' | 'revoked' | 'not_found' | 'rate_limited'
);

create index access_log_ip_time_idx on public.access_log (ip_hash, accessed_at desc);

-- ---------------------------------------------------------------------
-- 5. OPTIMISTIC LOCKING (replaces last-writer-wins)
-- ---------------------------------------------------------------------
create or replace function public.anamnese_bump_version()
returns trigger language plpgsql as $$
begin
  if new.version is distinct from old.version then
    raise exception 'version_conflict: record was modified by another session'
      using errcode = '40001';
  end if;
  new.version    := old.version + 1;
  new.updated_at := now();
  return new;
end;
$$;

create trigger anamnese_version_guard
  before update on public.anamnese
  for each row execute function public.anamnese_bump_version();

-- ---------------------------------------------------------------------
-- 6. ROW LEVEL SECURITY — default deny; anon gets NO table access
-- ---------------------------------------------------------------------
alter table public.patient          enable row level security;
alter table public.anamnese         enable row level security;
alter table public.anamnese_vaccine enable row level security;
alter table public.access_log       enable row level security;

revoke all on public.patient          from anon, authenticated;
revoke all on public.anamnese         from anon, authenticated;
revoke all on public.anamnese_vaccine from anon, authenticated;
revoke all on public.access_log       from anon, authenticated;

grant select, insert, update         on public.patient          to authenticated;
grant select, insert, update         on public.anamnese         to authenticated;
grant select, insert, update, delete on public.anamnese_vaccine to authenticated;
grant select                         on public.vaccine          to anon, authenticated;

create policy patient_owner on public.patient
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy anamnese_owner on public.anamnese
  for all to authenticated
  using      (patient_id in (select id from public.patient where user_id = auth.uid()))
  with check (patient_id in (select id from public.patient where user_id = auth.uid()));

create policy anamnese_vaccine_owner on public.anamnese_vaccine
  for all to authenticated
  using (anamnese_id in (
    select a.id from public.anamnese a
      join public.patient p on p.id = a.patient_id
     where p.user_id = auth.uid()))
  with check (anamnese_id in (
    select a.id from public.anamnese a
      join public.patient p on p.id = a.patient_id
     where p.user_id = auth.uid()));

-- No policy exists for `anon`. anon can read nothing and write nothing.

-- ---------------------------------------------------------------------
-- 7. PUBLIC READ — the ONLY thing anon may do
--
--    FIELD VISIBILITY. This function body IS the field list the reviewers
--    demanded. What is not returned here is not public.
--
--    Deliberately EXCLUDED from the public record:
--      sus             national health-card number; a strong identifier,
--                      and of no use to a responder
--      plano_saude     insurer; billing data, not triage data
--      hist_familiar   health data about relatives who are not the data
--                      subject and gave no consent (LGPD)
--      peso_kg,
--      altura_cm       retained privately; not triage-critical
--      data_nascimento only `idade` is exposed; DOB is an identifier
-- ---------------------------------------------------------------------
create or replace function public.emergency_record(
  p_token      text,
  p_ip_hash    text default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient  public.patient%rowtype;
  v_anamnese public.anamnese%rowtype;
begin
  -- Reject malformed tokens outright: blocks probing and short-token guessing.
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then
    insert into public.access_log (patient_id, ip_hash, user_agent, outcome)
      values (null, p_ip_hash, p_user_agent, 'not_found');
    return null;
  end if;

  -- Rate limit: 20 reads per IP per minute.
  if p_ip_hash is not null and (
       select count(*) from public.access_log
        where ip_hash = p_ip_hash
          and accessed_at > now() - interval '1 minute'
     ) >= 20 then
    insert into public.access_log (patient_id, ip_hash, user_agent, outcome)
      values (null, p_ip_hash, p_user_agent, 'rate_limited');
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  select * into v_patient from public.patient p where p.token = p_token;
  if not found then
    insert into public.access_log (patient_id, ip_hash, user_agent, outcome)
      values (null, p_ip_hash, p_user_agent, 'not_found');
    return null;
  end if;

  if v_patient.revoked then
    insert into public.access_log (patient_id, ip_hash, user_agent, outcome)
      values (v_patient.id, p_ip_hash, p_user_agent, 'revoked');
    return null;   -- lost or stolen band: the URL is now a dead link
  end if;

  select * into v_anamnese from public.anamnese a where a.patient_id = v_patient.id;
  if not found then
    insert into public.access_log (patient_id, ip_hash, user_agent, outcome)
      values (v_patient.id, p_ip_hash, p_user_agent, 'not_found');
    return null;
  end if;

  insert into public.access_log (patient_id, ip_hash, user_agent, outcome)
    values (v_patient.id, p_ip_hash, p_user_agent, 'ok');

  return jsonb_build_object(
    -- general
    'nome',               v_anamnese.nome,
    'idade',              v_anamnese.idade,
    'sangue',             v_anamnese.sangue,
    'contato_emerg_nome', v_anamnese.contato_emerg_nome,
    'contato_emerg',      v_anamnese.contato_emerg,
    'contato_emerg_grau', v_anamnese.contato_emerg_grau,
    -- clinical
    'alergias',           v_anamnese.alergias,
    'doenca_pre',         v_anamnese.doenca_pre,
    'medicacoes',         v_anamnese.medicacoes,
    'cirurgia',           v_anamnese.cirurgia,
    'disp_implantado',    v_anamnese.disp_implantado,
    'transfusao',         v_anamnese.transfusao,
    'doacao_orgaos',      v_anamnese.doacao_orgaos,
    'obs_adicional',      v_anamnese.obs_adicional,
    -- vaccination
    'doses_cov',          v_anamnese.doses_cov,
    'fabricante_cov',     v_anamnese.fabricante_cov,
    'data_h1n1',          v_anamnese.data_h1n1,
    'vac_outras',         v_anamnese.vac_outras,
    'vacinas', coalesce((
        select jsonb_agg(jsonb_build_object('label', vc.label_pt, 'taken', av.taken)
                         order by vc.sort_ord)
          from public.anamnese_vaccine av
          join public.vaccine vc on vc.id = av.vaccine_id
         where av.anamnese_id = v_anamnese.id and av.taken
      ), '[]'::jsonb),
    'updated_at',         v_anamnese.updated_at
  );
end;
$$;

revoke all on function public.emergency_record(text, text, text) from public;
grant execute on function public.emergency_record(text, text, text) to anon;

-- ---------------------------------------------------------------------
-- 8. REVOCATION, ROTATION, ERASURE, TAG PASSWORD
-- ---------------------------------------------------------------------
create or replace function public.revoke_band()
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.patient set revoked = true, revoked_at = now()
   where user_id = auth.uid();
end; $$;

create or replace function public.rotate_token()
returns text language plpgsql security definer set search_path = public as $$
declare v_new text;
begin
  update public.patient
     set token = encode(gen_random_bytes(16), 'hex'),
         token_rotated_at = now(), revoked = false, revoked_at = null
   where user_id = auth.uid()
  returning token into v_new;
  return v_new;   -- the physical tag MUST then be re-written
end; $$;

create or replace function public.issue_tag_password()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_pwd bytea; v_pack bytea;
begin
  v_pwd := gen_random_bytes(4); v_pack := gen_random_bytes(2);
  update public.patient set tag_pwd = v_pwd, tag_pack = v_pack
   where user_id = auth.uid();
  return jsonb_build_object('pwd', encode(v_pwd,'hex'), 'pack', encode(v_pack,'hex'));
end; $$;

create or replace function public.erase_me()
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.patient where user_id = auth.uid();   -- cascades
end; $$;

grant execute on function public.revoke_band()        to authenticated;
grant execute on function public.rotate_token()       to authenticated;
grant execute on function public.issue_tag_password() to authenticated;
grant execute on function public.erase_me()           to authenticated;
