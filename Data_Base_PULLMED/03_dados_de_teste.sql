-- =====================================================================
-- PULLMED — dados de teste
--
-- Gera N pacientes FICTICIOS para testar o site, o app e o comissionamento
-- das tags no protocolo S1.
--
-- ATENCAO: estes registros ficam PUBLICAMENTE LEGIVEIS em
--          https://pullmed.digital/r/<token>
--          Por isso todos os nomes sao 'Paciente Teste NN'. Nao substitua
--          por nomes reais, nem seus, nem dos coautores.
--
-- Para apagar tudo depois, veja o bloco no final do arquivo.
-- =====================================================================

-- ---- quantos pacientes? ---------------------------------------------
\set n_pacientes 10

do $$
declare
  v_n          int := 10;   -- ajuste aqui se nao usar psql
  i            int;
  v_uid        uuid;
  v_patient    uuid;
  v_anamnese   uuid;

  -- pools de valores plausiveis
  sangues      text[] := array['A+','A-','B+','B-','AB+','AB-','O+','O-'];
  alergias     text[] := array[
    'Penicilina', 'Dipirona', 'Frutos do mar', 'Latex', 'Amendoim',
    'Sulfa', 'Anti-inflamatorios (AINEs)', 'Nenhuma conhecida',
    'Contraste iodado', 'Acaros e poeira'];
  doencas      text[] := array[
    'Hipertensao arterial', 'Diabetes mellitus tipo 2', 'Asma',
    'Epilepsia', 'Insuficiencia renal cronica', 'Nenhuma',
    'Fibrilacao atrial', 'Hipotireoidismo', 'DPOC', 'Anemia falciforme'];
  medicacoes   text[] := array[
    'Losartana 50mg 1x/dia', 'Metformina 850mg 2x/dia',
    'Varfarina 5mg 1x/dia (ANTICOAGULADO)', 'Levotiroxina 75mcg',
    'Salbutamol inalatorio SOS', 'Carbamazepina 200mg 2x/dia',
    'Nenhuma', 'Enalapril 10mg 2x/dia', 'Insulina NPH', 'AAS 100mg'];
  cirurgias    text[] := array[
    'Apendicectomia (2015)', 'Cesariana (2019)', 'Nenhuma',
    'Colecistectomia (2021)', 'Artroscopia de joelho (2018)',
    'Safenectomia (2020)'];
  dispositivos text[] := array[
    'Nenhum', 'Marca-passo cardiaco', 'Protese de quadril metalica',
    'Stent coronariano', 'Nenhum', 'Implante coclear'];
  parentescos  text[] := array['Mae','Pai','Conjuge','Irmao','Irma','Filho','Filha'];
  fabricantes  text[] := array['Pfizer','CoronaVac','AstraZeneca','Janssen'];

  v_token text;
begin
  for i in 1..v_n loop
    v_uid := gen_random_uuid();

    insert into auth.users (
      id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at
    ) values (
      v_uid, '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated',
      format('teste%s@pullmed.invalid', lpad(i::text, 2, '0')),
      crypt('teste1234', gen_salt('bf')),   -- senha: teste1234
      now(), now(), now()
    );

    insert into public.patient (user_id)
    values (v_uid)
    returning id, token into v_patient, v_token;

    insert into public.anamnese (
      patient_id, nome, data_nascimento, idade, peso_kg, altura_cm, sangue,
      contato_emerg_nome, contato_emerg, contato_emerg_grau,
      alergias, doenca_pre, medicacoes, cirurgia, disp_implantado,
      transfusao, doacao_orgaos, obs_adicional,
      hist_familiar, plano_saude, sus,
      doses_cov, fabricante_cov, data_h1n1, vac_outras
    ) values (
      v_patient,
      format('Paciente Teste %s', lpad(i::text, 2, '0')),
      (date '1955-01-01' + (random() * 20000)::int),
      18 + (random() * 65)::int,
      50 + (random() * 45)::int,
      150 + (random() * 45)::int,
      sangues[1 + floor(random() * array_length(sangues, 1))::int],
      format('Contato Teste %s', lpad(i::text, 2, '0')),
      format('(11) 9%s-%s',
             lpad((random() * 9999)::int::text, 4, '0'),
             lpad((random() * 9999)::int::text, 4, '0')),
      parentescos[1 + floor(random() * array_length(parentescos, 1))::int],
      alergias[1 + floor(random() * array_length(alergias, 1))::int],
      doencas[1 + floor(random() * array_length(doencas, 1))::int],
      medicacoes[1 + floor(random() * array_length(medicacoes, 1))::int],
      cirurgias[1 + floor(random() * array_length(cirurgias, 1))::int],
      dispositivos[1 + floor(random() * array_length(dispositivos, 1))::int],
      (random() > 0.3),
      (random() > 0.5),
      case when random() > 0.6
           then 'Portador de cartao de anticoagulacao. Contatar hematologista.'
           else 'Sem observacoes adicionais.' end,
      -- campos PRIVADOS: preenchidos de proposito, para provar que nao vazam
      'DADO PRIVADO - NAO DEVE APARECER NO REGISTRO PUBLICO',
      'DADO PRIVADO - NAO DEVE APARECER NO REGISTRO PUBLICO',
      'DADO PRIVADO - NAO DEVE APARECER NO REGISTRO PUBLICO',
      (random() * 4)::int,
      fabricantes[1 + floor(random() * array_length(fabricantes, 1))::int],
      (date '2024-03-01' + (random() * 400)::int),
      case when random() > 0.7 then 'Raiva (pos-exposicao, 2023)' else '' end
    ) returning id into v_anamnese;

    -- vacinas: marca um subconjunto aleatorio dos 21
    insert into public.anamnese_vaccine (anamnese_id, vaccine_id, taken)
    select v_anamnese, v.id, (random() > 0.35)
      from public.vaccine v;

  end loop;

  raise notice '% pacientes de teste criados.', v_n;
  raise notice 'Senha de todos: teste1234';
  raise notice 'Login no app: teste01, teste02, ... (sem o dominio)';
end $$;


-- =====================================================================
-- AS URLs PUBLICAS — use estas para gravar as tags e testar o site
-- =====================================================================
select
  a.nome,
  a.sangue                              as tipo_sanguineo,
  left(a.alergias, 20)                  as alergia,
  'https://pullmed.digital/r/' || p.token  as url_publica,
  p.token
from public.patient p
join public.anamnese a on a.patient_id = p.id
where a.nome like 'Paciente Teste%'
order by a.nome;


-- =====================================================================
-- CONFERIR A MINIMIZACAO
-- Os tres campos marcados 'DADO PRIVADO' NAO podem aparecer aqui.
-- =====================================================================
select
  a.nome,
  public.emergency_record(p.token) as registro_publico
from public.patient p
join public.anamnese a on a.patient_id = p.id
where a.nome = 'Paciente Teste 01';


-- =====================================================================
-- APAGAR TUDO  (rode antes de qualquer uso real)
-- =====================================================================
-- delete from auth.users
--  where email like 'teste%@pullmed.invalid';    -- cascata apaga o resto
-- delete from public.access_log where patient_id is null;
