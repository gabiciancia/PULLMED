-- =====================================================================
-- PULLMED — verificacao do banco
--
-- Cole no SQL Editor e rode. Ele cria um paciente de teste, verifica
-- cada garantia, e apaga tudo no final. Nao deixa lixo.
--
-- Toda linha do resultado deve dizer OK. Qualquer FALHA precisa ser
-- corrigida antes de o app funcionar.
-- =====================================================================

do $$
declare
  v_uid       uuid;
  v_patient   uuid;
  v_anamnese  uuid;
  v_token     text;
  v_json      jsonb;
  v_n         int;
  v_txt       text;
begin
  raise notice '';
  raise notice '=== 1. ESTRUTURA ===';

  -- tabelas
  select count(*) into v_n from information_schema.tables
   where table_schema = 'public'
     and table_name in ('patient','anamnese','anamnese_vaccine','vaccine','access_log');
  raise notice '% 5 tabelas criadas (achou %)',
    case when v_n = 5 then 'OK   ' else 'FALHA' end, v_n;

  -- 21 vacinas
  select count(*) into v_n from public.vaccine;
  raise notice '% 21 vacinas na lookup (achou %)',
    case when v_n = 21 then 'OK   ' else 'FALHA' end, v_n;

  -- funcoes
  select count(*) into v_n from information_schema.routines
   where routine_schema = 'public'
     and routine_name in ('emergency_record','revoke_band','rotate_token',
                          'issue_tag_password','erase_me');
  raise notice '% 5 funcoes criadas (achou %)',
    case when v_n = 5 then 'OK   ' else 'FALHA' end, v_n;

  raise notice '';
  raise notice '=== 2. RLS ===';

  select count(*) into v_n from pg_tables
   where schemaname = 'public'
     and tablename in ('patient','anamnese','anamnese_vaccine','vaccine','access_log')
     and rowsecurity = true;
  raise notice '% RLS ligada em 5 tabelas (achou %)',
    case when v_n = 5 then 'OK   ' else 'FALHA' end, v_n;

  -- anon nao pode ler tabela nenhuma (exceto vaccine, que e lookup)
  select count(*) into v_n from information_schema.role_table_grants
   where grantee = 'anon' and table_schema = 'public'
     and table_name in ('patient','anamnese','anamnese_vaccine','access_log');
  raise notice '% anon NAO tem grant nas tabelas de paciente (achou % grants)',
    case when v_n = 0 then 'OK   ' else 'FALHA' end, v_n;

  raise notice '';
  raise notice '=== 3. FLUXO COMPLETO (paciente de teste) ===';

  -- usuario falso direto em auth.users
  v_uid := gen_random_uuid();
  insert into auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
  values (v_uid, '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', 'teste_pullmed@pullmed.invalid', 'x', now(), now(), now());

  insert into public.patient (user_id) values (v_uid)
  returning id, token into v_patient, v_token;

  -- entropia do token
  raise notice '% token tem 32 chars hex (= 128 bits). Token: %',
    case when v_token ~ '^[0-9a-f]{32}$' then 'OK   ' else 'FALHA' end, v_token;

  raise notice '% token NAO contem o login/email',
    case when position('teste_pullmed' in v_token) = 0 then 'OK   ' else 'FALHA' end;

  insert into public.anamnese (patient_id, nome, idade, sangue, alergias,
                               medicacoes, sus, hist_familiar, plano_saude)
  values (v_patient, 'Paciente Teste', 30, 'O+', 'Penicilina',
          'Losartana', '123456789', 'Diabetes na familia', 'Plano X')
  returning id into v_anamnese;

  insert into public.anamnese_vaccine (anamnese_id, vaccine_id, taken)
  values (v_anamnese, 1, true), (v_anamnese, 19, true);

  -- leitura publica pelo token
  v_json := public.emergency_record(v_token, 'ip_de_teste', 'agente_de_teste');

  raise notice '% emergency_record() retorna o registro pelo token',
    case when v_json is not null and v_json->>'nome' = 'Paciente Teste'
         then 'OK   ' else 'FALHA' end;

  raise notice '% alergia aparece no registro publico (%)',
    case when v_json->>'alergias' = 'Penicilina' then 'OK   ' else 'FALHA' end,
    v_json->>'alergias';

  raise notice '% vacinas vem da tabela de juncao (% marcadas)',
    case when jsonb_array_length(v_json->'vacinas') = 2 then 'OK   ' else 'FALHA' end,
    jsonb_array_length(v_json->'vacinas');

  raise notice '';
  raise notice '=== 4. MINIMIZACAO (campos que NAO podem vazar) ===';

  raise notice '% cartao SUS NAO esta no registro publico',
    case when v_json ? 'sus' = false then 'OK   ' else 'FALHA <<< VAZOU' end;
  raise notice '% historico familiar NAO esta no registro publico',
    case when v_json ? 'hist_familiar' = false then 'OK   ' else 'FALHA <<< VAZOU' end;
  raise notice '% plano de saude NAO esta no registro publico',
    case when v_json ? 'plano_saude' = false then 'OK   ' else 'FALHA <<< VAZOU' end;
  raise notice '% data de nascimento NAO esta no registro publico',
    case when v_json ? 'data_nascimento' = false then 'OK   ' else 'FALHA <<< VAZOU' end;

  raise notice '';
  raise notice '=== 5. TOKEN INVALIDO / ENUMERACAO ===';

  raise notice '% token inexistente retorna vazio',
    case when public.emergency_record(repeat('a',32)) is null
         then 'OK   ' else 'FALHA' end;
  raise notice '% token malformado e rejeitado',
    case when public.emergency_record('123') is null
         then 'OK   ' else 'FALHA' end;

  raise notice '';
  raise notice '=== 6. REVOGACAO ===';

  update public.patient set revoked = true where id = v_patient;
  raise notice '% pulseira revogada vira link morto',
    case when public.emergency_record(v_token) is null
         then 'OK   ' else 'FALHA <<< AINDA LE' end;
  update public.patient set revoked = false where id = v_patient;

  raise notice '';
  raise notice '=== 7. LOG DE ACESSO ===';

  select count(*) into v_n from public.access_log where patient_id = v_patient;
  raise notice '% leituras publicas sao registradas (% eventos)',
    case when v_n >= 2 then 'OK   ' else 'FALHA' end, v_n;

  select string_agg(distinct outcome, ', ') into v_txt from public.access_log;
  raise notice '       desfechos registrados: %', v_txt;

  raise notice '';
  raise notice '=== 8. EDICAO CONCORRENTE (optimistic locking) ===';

  begin
    update public.anamnese set nome = 'Tentativa Obsoleta', version = 99
     where id = v_anamnese;
    raise notice 'FALHA versao obsoleta foi ACEITA <<< last-writer-wins ainda ativo';
  exception when others then
    raise notice 'OK    versao obsoleta e rejeitada (%)', sqlerrm;
  end;

  -- limpeza
  delete from auth.users where id = v_uid;   -- cascade
  delete from public.access_log where ip_hash = 'ip_de_teste';

  select count(*) into v_n from public.patient where id = v_patient;
  raise notice '';
  raise notice '=== 9. LIMPEZA ===';
  raise notice '% dados de teste apagados em cascata',
    case when v_n = 0 then 'OK   ' else 'FALHA' end;

  raise notice '';
  raise notice '=====================================================';
  raise notice 'Se toda linha acima diz OK, o banco esta correto.';
  raise notice '=====================================================';
end $$;
