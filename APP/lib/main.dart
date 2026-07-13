import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


/// Injected at compile time. See .vscode/launch.json or --dart-define.
const String kSupabaseUrl =
    String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const String kSupabaseAnonKey =
    String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

/// Base of the public record URL. The token is appended.
const String kRecordBaseUrl = 'https://pullmed.digital/r';

/// The Login field is a username, not an e-mail. Supabase Auth requires an
/// e-mail, so one is synthesised. This keeps the existing screen intact.
const String kSyntheticEmailDomain = 'pullmed.invalid';

String _loginToEmail(String login) =>
    '${login.trim().toLowerCase()}@$kSyntheticEmailDomain';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fail loudly. A silent fallback to hard-coded credentials is exactly how
  // keys end up in a public repository.
  if (kSupabaseUrl.isEmpty || kSupabaseAnonKey.isEmpty) {
    throw StateError(
      'SUPABASE_URL / SUPABASE_ANON_KEY nao foram fornecidos.\n'
      'Rode com --dart-define, ou use a configuracao "PULLMED" no VS Code (F5).',
    );
  }

  await Supabase.initialize(
    url: kSupabaseUrl,
    anonKey: kSupabaseAnonKey,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'PullMed',
      home: LoginScreen(),
    );
  }
}

// =====================================================================
// LOGIN
// =====================================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final loginController = TextEditingController();
  final senhaController = TextEditingController();
  final confirmaSenhaController = TextEditingController();
  String? mensagemErro;
  bool mostrarCriarConta = false;
  bool criandoConta = false;
  bool _ocupado = false;

  /// Ensures the patient row exists and returns it (id + token).
  /// RLS admits this only because user_id = auth.uid().
  Future<Map<String, dynamic>> _garantirPaciente() async {
    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser!.id;

    await supabase.from('patient').upsert(
      {'user_id': uid},
      onConflict: 'user_id',
      ignoreDuplicates: true,
    );

    return await supabase
        .from('patient')
        .select('id, token, revoked')
        .eq('user_id', uid)
        .single();
  }

  /// Loads the record and its vaccination rows, if any.
  Future<Map<String, dynamic>?> _carregarAnamnese(String patientId) async {
    final supabase = Supabase.instance.client;

    final anamnese = await supabase
        .from('anamnese')
        .select()
        .eq('patient_id', patientId)
        .maybeSingle();

    if (anamnese == null) return null;

    // Vaccination now lives in a junction table, not in 21 columns whose
    // names were the vaccine labels themselves.
    final marcadas = await supabase
        .from('anamnese_vaccine')
        .select('taken, vaccine(code, label_pt)')
        .eq('anamnese_id', anamnese['id'])
        .eq('taken', true);

    final labels = <String>[];
    for (final row in (marcadas as List)) {
      final v = row['vaccine'];
      if (v != null && v['label_pt'] != null) {
        labels.add(v['label_pt'] as String);
      }
    }

    return {...anamnese, '_vacinas_marcadas': labels};
  }

  Future<void> _prosseguir() async {
    final paciente = await _garantirPaciente();
    final patientId = paciente['id'] as String;
    final token = paciente['token'] as String;
    final dados = await _carregarAnamnese(patientId);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InformacoesScreen(
          patientId: patientId,
          token: token,
          dadosPreenchidos: dados,
        ),
      ),
    );
  }

  Future<void> verificarLogin() async {
    final supabase = Supabase.instance.client;
    final login = loginController.text.trim();
    final senha = senhaController.text;

    if (login.isEmpty || senha.isEmpty) {
      setState(() => mensagemErro = 'Preencha login e senha.');
      return;
    }

    setState(() {
      _ocupado = true;
      mensagemErro = null;
    });

    try {
      // The password goes to Supabase Auth, which compares it against a
      // bcrypt hash server-side. It is never fetched into the client.
      await supabase.auth.signInWithPassword(
        email: _loginToEmail(login),
        password: senha,
      );
      await _prosseguir();
    } on AuthException catch (e) {
      // Supabase returns the same error for "no such user" and "wrong
      // password", by design: distinguishing them would let an attacker
      // enumerate valid logins.
      setState(() {
        mensagemErro = 'Login ou senha incorretos.';
        mostrarCriarConta = true;
      });
      debugPrint('AuthException: ${e.message}');
    } catch (e) {
      setState(() => mensagemErro = 'Erro ao entrar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> criarConta() async {
    final supabase = Supabase.instance.client;
    final login = loginController.text.trim();
    final senha = senhaController.text;
    final confirmaSenha = confirmaSenhaController.text;

    if (senha != confirmaSenha) {
      setState(() => mensagemErro = 'As senhas não conferem.');
      return;
    }
    if (senha.length < 8) {
      setState(() => mensagemErro = 'A senha deve ter ao menos 8 caracteres.');
      return;
    }

    setState(() {
      _ocupado = true;
      mensagemErro = null;
    });

    try {
      await supabase.auth.signUp(
        email: _loginToEmail(login),
        password: senha,
      );

      // With e-mail confirmation disabled (required, since the address is
      // synthetic), signUp already returns an active session.
      if (supabase.auth.currentUser == null) {
        await supabase.auth.signInWithPassword(
          email: _loginToEmail(login),
          password: senha,
        );
      }

      setState(() {
        mostrarCriarConta = false;
        criandoConta = false;
      });
      await _prosseguir();
    } on AuthException catch (e) {
      setState(() => mensagemErro = e.message.toLowerCase().contains('already')
          ? 'Usuário já existe.'
          : 'Erro ao criar conta: ${e.message}');
    } catch (e) {
      setState(() => mensagemErro = 'Erro ao criar conta: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/logo_pullmed.png', width: 200),
              const SizedBox(height: 32),
              TextField(
                controller: loginController,
                decoration: const InputDecoration(
                  labelText: 'Login',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: senhaController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              if (mensagemErro != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    mensagemErro!,
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              if (mostrarCriarConta || criandoConta)
                Column(
                  children: [
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmaSenhaController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmação de Senha',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _ocupado ? null : criarConta,
                        child: const Text('Criar conta'),
                      ),
                    ),
                  ],
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _ocupado ? null : verificarLogin,
                  child: _ocupado
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Entrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// INFORMAÇÕES  (form — content unchanged)
// =====================================================================

class InformacoesScreen extends StatefulWidget {
  final String patientId;
  final String token;
  final Map<String, dynamic>? dadosPreenchidos;

  const InformacoesScreen({
    super.key,
    required this.patientId,
    required this.token,
    this.dadosPreenchidos,
  });

  @override
  State<InformacoesScreen> createState() => _InformacoesScreenState();
}

class _InformacoesScreenState extends State<InformacoesScreen> {
  final List<String> vacinas = [
    'BCG', 'Hepatite A', 'Hepatite B', 'Penta (DTP/Hib/Hep. B)', 'Pneumocócica 10-valente',
    'Vacina Inativada Poliomielite (VIP)', 'Vacina Oral Poliomielite (VOP)', 'Vacina Rotavírus Humano (VRH)',
    'Meningocócica C (conjugada)', 'Meningocócica ACWY', 'Febre amarela', 'Tríplice viral',
    'DTP (tríplice bacteriana)', 'Varicela', 'SCR (Sarampo, Caxumba e Rubéola)', 'HPV quadrivalente',
    'dT (dupla adulto)', 'dTpa (DTP adulto)', 'SARS-COV-19', 'H1N1 (Gripe)', 'Outras'
  ];

  Map<String, bool> vacinasStatus = {};
  String autorizacaoTransfusao = 'Não';
  String autorizacaoDoacaoOrgaos = 'Não';

  final List<String> tiposSanguineos = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
  ];
  String tipoSanguineoSelecionado = 'A+';

  /// Row id and version of the record, for optimistic locking.
  String? _anamneseId;
  int _version = 0;
  late String _token;
  bool _salvando = false;

  /// label_pt -> vaccine.id, loaded once from the lookup table.
  final Map<String, int> _vaccineIds = {};

  // Controllers para todos os campos
  final nomeController = TextEditingController();
  final nascimentoController = TextEditingController();
  final idadeController = TextEditingController();
  final pesoController = TextEditingController();
  final alturaController = TextEditingController();
  final contatoNomeController = TextEditingController();
  final contatoTelefoneController = TextEditingController();
  final contatoParentescoController = TextEditingController();
  final alergiasController = TextEditingController();
  final doencasController = TextEditingController();
  final medicacoesController = TextEditingController();
  final cirurgiasController = TextEditingController();
  final historicoFamiliarController = TextEditingController();
  final planoSaudeController = TextEditingController();
  final susController = TextEditingController();
  final dispositivosController = TextEditingController();
  final observacoesController = TextEditingController();
  final dosesCovidController = TextEditingController();
  final fabricanteCovidController = TextEditingController();
  final dataH1n1Controller = TextEditingController();
  final outrasVacinaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _token = widget.token;

    for (var v in vacinas) {
      vacinasStatus[v] = false;
    }

    final dados = widget.dadosPreenchidos;
    if (dados != null) {
      _anamneseId = dados['id'] as String?;
      _version = (dados['version'] as int?) ?? 0;

      nomeController.text = (dados['nome'] ?? '').toString();
      nascimentoController.text = (dados['data_nascimento'] ?? '').toString();
      idadeController.text = (dados['idade'] ?? '').toString();
      pesoController.text = (dados['peso_kg'] ?? '').toString();
      alturaController.text = (dados['altura_cm'] ?? '').toString();
      contatoNomeController.text = (dados['contato_emerg_nome'] ?? '').toString();
      contatoTelefoneController.text = (dados['contato_emerg'] ?? '').toString();
      contatoParentescoController.text = (dados['contato_emerg_grau'] ?? '').toString();
      tipoSanguineoSelecionado = (dados['sangue'] ?? 'A+').toString();
      autorizacaoTransfusao = (dados['transfusao'] == true) ? 'Sim' : 'Não';
      autorizacaoDoacaoOrgaos = (dados['doacao_orgaos'] == true) ? 'Sim' : 'Não';
      alergiasController.text = (dados['alergias'] ?? '').toString();
      doencasController.text = (dados['doenca_pre'] ?? '').toString();
      medicacoesController.text = (dados['medicacoes'] ?? '').toString();
      cirurgiasController.text = (dados['cirurgia'] ?? '').toString();
      historicoFamiliarController.text = (dados['hist_familiar'] ?? '').toString();
      planoSaudeController.text = (dados['plano_saude'] ?? '').toString();
      susController.text = (dados['sus'] ?? '').toString();
      dispositivosController.text = (dados['disp_implantado'] ?? '').toString();
      observacoesController.text = (dados['obs_adicional'] ?? '').toString();
      dosesCovidController.text = (dados['doses_cov'] ?? '').toString();
      fabricanteCovidController.text = (dados['fabricante_cov'] ?? '').toString();
      dataH1n1Controller.text = (dados['data_h1n1'] ?? '').toString();
      outrasVacinaController.text = (dados['vac_outras'] ?? '').toString();

      for (final label in (dados['_vacinas_marcadas'] as List? ?? const [])) {
        if (vacinasStatus.containsKey(label)) {
          vacinasStatus[label as String] = true;
        }
      }
    }

    _carregarIdsVacinas();
  }

  Future<void> _carregarIdsVacinas() async {
    final rows =
        await Supabase.instance.client.from('vaccine').select('id, label_pt');
    for (final r in (rows as List)) {
      _vaccineIds[r['label_pt'] as String] = r['id'] as int;
    }
  }

  int? _parseIntOrNull(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    return int.tryParse(v);
  }

  /// An empty string is not a valid DATE in Postgres; send null instead.
  String? _parseDateOrNull(String value) {
    final v = value.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> salvarNoBanco() async {
    final supabase = Supabase.instance.client;

    final dados = <String, dynamic>{
      'patient_id': widget.patientId,
      'nome': nomeController.text,
      'data_nascimento': _parseDateOrNull(nascimentoController.text),
      'idade': _parseIntOrNull(idadeController.text),
      'peso_kg': _parseIntOrNull(pesoController.text),
      'altura_cm': _parseIntOrNull(alturaController.text),
      'contato_emerg_nome': contatoNomeController.text,
      'contato_emerg': contatoTelefoneController.text,
      'contato_emerg_grau': contatoParentescoController.text,
      'sangue': tipoSanguineoSelecionado,
      'transfusao': autorizacaoTransfusao == 'Sim',
      'doacao_orgaos': autorizacaoDoacaoOrgaos == 'Sim',
      'alergias': alergiasController.text,
      'doenca_pre': doencasController.text,
      'medicacoes': medicacoesController.text,
      'cirurgia': cirurgiasController.text,
      'hist_familiar': historicoFamiliarController.text,
      'plano_saude': planoSaudeController.text,
      'sus': susController.text,
      'disp_implantado': dispositivosController.text,
      'obs_adicional': observacoesController.text,
      'doses_cov': _parseIntOrNull(dosesCovidController.text),
      'fabricante_cov': fabricanteCovidController.text,
      'data_h1n1': _parseDateOrNull(dataH1n1Controller.text),
      'vac_outras': outrasVacinaController.text,
    };

    // Optimistic locking. The trigger rejects a stale version rather than
    // silently overwriting a concurrent edit (last-writer-wins).
    if (_anamneseId != null) {
      dados['version'] = _version;
    }

    final saved = await supabase
        .from('anamnese')
        .upsert(dados, onConflict: 'patient_id')
        .select('id, version')
        .single();

    _anamneseId = saved['id'] as String;
    _version = saved['version'] as int;

    // Vaccination: junction table, not 21 columns named after the vaccines.
    if (_vaccineIds.isEmpty) await _carregarIdsVacinas();

    final linhas = <Map<String, dynamic>>[];
    vacinasStatus.forEach((label, marcada) {
      final vid = _vaccineIds[label];
      if (vid != null) {
        linhas.add({
          'anamnese_id': _anamneseId,
          'vaccine_id': vid,
          'taken': marcada,
        });
      }
    });
    if (linhas.isNotEmpty) {
      await supabase
          .from('anamnese_vaccine')
          .upsert(linhas, onConflict: 'anamnese_id,vaccine_id');
    }
  }

  // ---- band management: revocation, rotation, erasure -----------------

  Future<void> _revogarPulseira() async {
    final ok = await _confirmar(
      'Revogar pulseira',
      'A URL atual deixará de funcionar imediatamente. Use isto se a pulseira '
          'foi perdida ou roubada.\n\nQuem já tiver copiado a URL não conseguirá '
          'mais abrir o registro.',
    );
    if (!ok) return;

    await Supabase.instance.client.rpc('revoke_band');
    if (!mounted) return;
    _aviso('Pulseira revogada. A URL antiga agora é um link morto.');
  }

  Future<void> _rotacionarUrl() async {
    final ok = await _confirmar(
      'Gerar nova URL',
      'Um novo endereço será gerado e o antigo deixará de funcionar.\n\n'
          'Você precisará REGRAVAR a pulseira com a nova URL, senão ela deixará '
          'de abrir o registro.',
    );
    if (!ok) return;

    final novo = await Supabase.instance.client.rpc('rotate_token') as String;
    if (!mounted) return;
    setState(() => _token = novo);
    _aviso('Nova URL gerada. Regrave a pulseira agora.');
  }

  Future<void> _excluirDados() async {
    final ok = await _confirmar(
      'Excluir meus dados',
      'Todos os seus dados serão apagados permanentemente e a pulseira deixará '
          'de funcionar. Esta ação não pode ser desfeita.\n\n'
          '(LGPD, Art. 18 — direito à eliminação)',
    );
    if (!ok) return;

    await Supabase.instance.client.rpc('erase_me');
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<bool> _confirmar(String titulo, String corpo) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(corpo),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  void _aviso(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informações'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'revogar') _revogarPulseira();
              if (v == 'rotacionar') _rotacionarUrl();
              if (v == 'excluir') _excluirDados();
              if (v == 'sair') {
                Supabase.instance.client.auth.signOut();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'revogar',
                child: Text('Revogar pulseira (perdida/roubada)'),
              ),
              PopupMenuItem(value: 'rotacionar', child: Text('Gerar nova URL')),
              PopupMenuItem(value: 'excluir', child: Text('Excluir meus dados')),
              PopupMenuItem(value: 'sair', child: Text('Sair')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dados Pessoais',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: nomeController, decoration: const InputDecoration(labelText: 'Nome completo')),
            TextField(controller: nascimentoController, decoration: const InputDecoration(labelText: 'Data de nascimento (AAAA-MM-DD)')),
            TextField(controller: idadeController, decoration: const InputDecoration(labelText: 'Idade')),
            TextField(controller: pesoController, decoration: const InputDecoration(labelText: 'Peso (kg)')),
            TextField(controller: alturaController, decoration: const InputDecoration(labelText: 'Altura (cm)')),
            const SizedBox(height: 16),
            const Text('Contato de Emergência', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(controller: contatoNomeController, decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: contatoTelefoneController, decoration: const InputDecoration(labelText: 'Telefone')),
            TextField(controller: contatoParentescoController, decoration: const InputDecoration(labelText: 'Grau de parentesco')),
            const SizedBox(height: 16),
            const Text('Dados Médicos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Row(
              children: [
                const Text('Tipo sanguíneo: '),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: tipoSanguineoSelecionado,
                  items: tiposSanguineos.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      tipoSanguineoSelecionado = newValue ?? 'A+';
                    });
                  },
                ),
              ],
            ),
            Row(
              children: [
                const Text('Autorização para transfusão: '),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: autorizacaoTransfusao,
                  items: ['Sim', 'Não'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      autorizacaoTransfusao = newValue ?? 'Não';
                    });
                  },
                ),
              ],
            ),
            Row(
              children: [
                const Text('Autorização para doação de órgãos: '),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: autorizacaoDoacaoOrgaos,
                  items: ['Sim', 'Não'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      autorizacaoDoacaoOrgaos = newValue ?? 'Não';
                    });
                  },
                ),
              ],
            ),
            TextField(controller: alergiasController, decoration: const InputDecoration(labelText: 'Alergias')),
            TextField(controller: doencasController, decoration: const InputDecoration(labelText: 'Doenças preexistentes')),
            TextField(controller: medicacoesController, decoration: const InputDecoration(labelText: 'Medicações contínuas')),
            const SizedBox(height: 16),
            const Text('Histórico de Saúde', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(controller: cirurgiasController, decoration: const InputDecoration(labelText: 'Cirurgias')),
            TextField(controller: historicoFamiliarController, decoration: const InputDecoration(labelText: 'Histórico familiar')),
            const SizedBox(height: 16),

            // These two controllers existed and were saved, but had no input
            // field on screen: they could never be filled. Fields added so the
            // stored columns are reachable. Neither appears on the public
            // record (see emergency_record() in the database).
            const Text('Assistência Médica', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(controller: planoSaudeController, decoration: const InputDecoration(labelText: 'Plano de saúde')),
            TextField(controller: susController, decoration: const InputDecoration(labelText: 'Cartão SUS')),
            const SizedBox(height: 16),

            const Text('Dispositivos Médicos', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(controller: dispositivosController, decoration: const InputDecoration(labelText: 'Implantes e outros dispositivos médicos')),
            const SizedBox(height: 16),
            const Text('Observações Médicas', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(controller: observacoesController, decoration: const InputDecoration(labelText: 'Informações adicionais relevantes')),
            const SizedBox(height: 24),
            const Text('Carteira de Vacinação',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...vacinas.map((vacina) {
              if (vacina == 'SARS-COV-19') {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: vacinasStatus[vacina] ?? false,
                          onChanged: (v) {
                            setState(() {
                              vacinasStatus[vacina] = v ?? false;
                            });
                          },
                        ),
                        Text(vacina),
                      ],
                    ),
                    TextField(controller: dosesCovidController, decoration: const InputDecoration(labelText: 'Número de doses tomadas')),
                    TextField(controller: fabricanteCovidController, decoration: const InputDecoration(labelText: 'Fabricante')),
                  ],
                );
              } else if (vacina == 'H1N1 (Gripe)') {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: vacinasStatus[vacina] ?? false,
                          onChanged: (v) {
                            setState(() {
                              vacinasStatus[vacina] = v ?? false;
                            });
                          },
                        ),
                        Text(vacina),
                      ],
                    ),
                    TextField(controller: dataH1n1Controller, decoration: const InputDecoration(labelText: 'Data da última aplicação (AAAA-MM-DD)')),
                  ],
                );
              } else if (vacina == 'Outras') {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: vacinasStatus[vacina] ?? false,
                          onChanged: (v) {
                            setState(() {
                              vacinasStatus[vacina] = v ?? false;
                            });
                          },
                        ),
                        Text(vacina),
                      ],
                    ),
                    TextField(controller: outrasVacinaController, decoration: const InputDecoration(labelText: 'Especificar')),
                  ],
                );
              } else {
                return Row(
                  children: [
                    Checkbox(
                      value: vacinasStatus[vacina] ?? false,
                      onChanged: (v) {
                        setState(() {
                          vacinasStatus[vacina] = v ?? false;
                        });
                      },
                    ),
                    Text(vacina),
                  ],
                );
              }
            }),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _salvando
                    ? null
                    : () async {
                        setState(() => _salvando = true);
                        try {
                          await salvarNoBanco();

                          // The URL is NOT built from user input. The token is
                          // 128 bits of server-side CSPRNG entropy.
                          final link = '$kRecordBaseUrl/$_token';

                          if (!mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GravarNfcScreen(link: link),
                            ),
                          );
                        } on PostgrestException catch (e) {
                          if (e.code == '40001' ||
                              e.message.contains('version_conflict')) {
                            _aviso('O registro foi alterado em outra sessão. '
                                'Recarregue antes de salvar.');
                          } else {
                            _aviso('Erro ao salvar: ${e.message}');
                          }
                        } catch (e) {
                          _aviso('Erro ao salvar: $e');
                        } finally {
                          if (mounted) setState(() => _salvando = false);
                        }
                      },
                child: _salvando
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Avançar para Gravar NFC'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// GRAVAR NFC
// =====================================================================

class GravarNfcScreen extends StatefulWidget {
  final String link;
  const GravarNfcScreen({super.key, required this.link});

  @override
  State<GravarNfcScreen> createState() => _GravarNfcScreenState();
}

class _GravarNfcScreenState extends State<GravarNfcScreen> {
  bool _nfcGravado = false;
  bool _gravando = false;
  bool _protegido = false;
  String? _erroNfc;

  // NTAG215 configuration pages (NXP NTAG213/215/216 datasheet, Rev. 3.2).
  static const int _pageCfg0 = 0x83; // byte 3 = AUTH0
  static const int _pageCfg1 = 0x84; // byte 0 = ACCESS
  static const int _pagePwd = 0x85;
  static const int _pagePack = 0x86;

  static const int _cmdRead = 0x30;
  static const int _cmdWrite = 0xA2;

  Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// Enables NTAG215 password protection for WRITES.
  ///
  /// Deliberately does NOT set lock bits. Lock bits are irreversible: once
  /// set, the tag can never be rewritten, which would make token rotation —
  /// and therefore revocation of a lost band — impossible.
  ///
  /// PROT = 0 -> the password protects writing only; reading stays public,
  /// which is what the emergency use case requires.
  ///
  /// This deters casual tampering. It is NOT a confidentiality control: the
  /// NTAG215 password is a 32-bit value transmitted in the clear.
  Future<void> _protegerEscrita(
      NfcTag tag, Uint8List pwd, Uint8List pack) async {
    final nfcA = NfcA.from(tag);
    if (nfcA == null) return; // iOS: use MiFare.sendMiFareCommand

    // 1. PWD -> page 0x85
    await nfcA.transceive(
        data: Uint8List.fromList(
            [_cmdWrite, _pagePwd, pwd[0], pwd[1], pwd[2], pwd[3]]));

    // 2. PACK -> page 0x86 (2 bytes + 2 padding)
    await nfcA.transceive(
        data: Uint8List.fromList(
            [_cmdWrite, _pagePack, pack[0], pack[1], 0x00, 0x00]));

    // 3. CFG1: clear PROT, CFGLCK and AUTHLIM.
    final cfg1 =
        await nfcA.transceive(data: Uint8List.fromList([_cmdRead, _pageCfg1]));
    await nfcA.transceive(
        data: Uint8List.fromList(
            [_cmdWrite, _pageCfg1, 0x00, cfg1[1], cfg1[2], cfg1[3]]));

    // 4. CFG0: AUTH0 = 0x04 -> protect pages 4 and above. Do this LAST.
    final cfg0 =
        await nfcA.transceive(data: Uint8List.fromList([_cmdRead, _pageCfg0]));
    await nfcA.transceive(
        data: Uint8List.fromList(
            [_cmdWrite, _pageCfg0, cfg0[0], cfg0[1], cfg0[2], 0x04]));
  }

  void _iniciarGravacao() async {
    setState(() {
      _gravando = true;
      _erroNfc = null;
    });

    try {
      final isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) throw Exception('NFC não disponível neste dispositivo');

      // A fresh, random password is issued per tag and held server-side.
      // A constant compiled into the app would mean that extracting the APK
      // yields the password for every wristband ever made.
      final creds = await Supabase.instance.client.rpc('issue_tag_password')
          as Map<String, dynamic>;
      final pwd = _hexToBytes(creds['pwd'] as String);
      final pack = _hexToBytes(creds['pack'] as String);

      await NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null || !ndef.isWritable) {
            throw Exception('Tag não gravável');
          }

          // Write the NDEF URI record first, while the tag is unprotected.
          await ndef.write(NdefMessage([
            NdefRecord.createUri(Uri.parse(widget.link)),
          ]));

          // Then enable write protection.
          var protegido = false;
          try {
            await _protegerEscrita(tag, pwd, pack);
            protegido = true;
          } catch (e) {
            // The URL was written; protection failed. Report this honestly
            // rather than claiming a protection that is not there.
            debugPrint('Proteção de escrita falhou: $e');
          }

          setState(() {
            _gravando = false;
            _nfcGravado = true;
            _protegido = protegido;
            _erroNfc = null;
          });
          NfcManager.instance.stopSession();
        } catch (e) {
          setState(() {
            _gravando = false;
            _nfcGravado = false;
            _erroNfc = 'Erro ao gravar na NFC: $e';
          });
          NfcManager.instance.stopSession();
        }
      });
    } catch (e) {
      setState(() {
        _gravando = false;
        _nfcGravado = false;
        _erroNfc = 'Erro ao iniciar sessão NFC: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gravar na NFC')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/logo_pullmed.png', width: 120),
              const SizedBox(height: 32),
              if (_nfcGravado)
                const Icon(Icons.check_circle, color: Colors.green, size: 64)
              else if (_gravando)
                const Icon(Icons.fiber_manual_record,
                    color: Colors.orange, size: 64)
              else
                const Icon(Icons.fiber_manual_record,
                    color: Colors.red, size: 64),
              const SizedBox(height: 32),
              if (_gravando)
                const Text('Aproxime a pulseira com a tag NFC...',
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold))
              else if (_nfcGravado)
                Column(
                  children: [
                    const Text('Gravação com sucesso!',
                        style: TextStyle(
                            fontSize: 18,
                            color: Colors.green,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      _protegido
                          ? 'Escrita protegida por senha.'
                          : 'Atenção: a URL foi gravada, mas a proteção de escrita falhou.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: _protegido
                            ? Colors.green.shade700
                            : Colors.orange.shade800,
                      ),
                    ),
                  ],
                )
              else if (_erroNfc != null)
                Column(
                  children: [
                    Text(_erroNfc!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16,
                            color: Colors.red,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _iniciarGravacao,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                )
              else
                ElevatedButton(
                  onPressed: _iniciarGravacao,
                  child: const Text('Iniciar gravação'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
