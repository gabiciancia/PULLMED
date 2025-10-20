import 'package:nfc_manager/nfc_manager.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'your url for supabase',
    anonKey: 'anon ket for your database',
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

  Future<void> verificarLogin() async {
    final supabase = Supabase.instance.client;
    final login = loginController.text.trim();
    final senha = senhaController.text.trim();
    final response = await supabase
        .from('d_usuario')
        .select()
        .eq('login', login)
        .maybeSingle();
    if (response == null) {
      setState(() {
        mensagemErro = 'Usuário não encontrado.';
        mostrarCriarConta = true;
      });
    } else if (response['senha'] != senha) {
      setState(() {
        mensagemErro = 'Senha incorreta.';
        mostrarCriarConta = false;
      });
    } else {
      setState(() {
        mensagemErro = null;
        mostrarCriarConta = false;
      });
      // Buscar dados preenchidos na tabela anamnese
    final dadosAnamnese = await supabase
      .from('anamnese')
      .select()
      .eq('login', login)
      .limit(1)
      .maybeSingle();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => InformacoesScreen(
            login: login,
            dadosPreenchidos: dadosAnamnese,
          ),
        ),
      );
    }
  }

  Future<void> criarConta() async {
    final supabase = Supabase.instance.client;
    final login = loginController.text.trim();
    final senha = senhaController.text.trim();
    final confirmaSenha = confirmaSenhaController.text.trim();
    if (senha != confirmaSenha) {
      setState(() {
        mensagemErro = 'As senhas não conferem.';
      });
      return;
    }
    // Verifica se login já existe
    final existe = await supabase
        .from('d_usuario')
        .select()
        .eq('login', login)
        .maybeSingle();
    if (existe != null) {
      setState(() {
        mensagemErro = 'Usuário já existe.';
      });
      return;
    }
    final link = 'www.pullmed.netlify.app/$login';
    final dadosUsuario = {
      'login': login,
      'senha': senha,
      'link': link,
    };
    await supabase.from('d_usuario').insert(dadosUsuario);
    setState(() {
      mensagemErro = null;
      mostrarCriarConta = false;
      criandoConta = false;
    });
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => InformacoesScreen(login: login)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
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
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            if (mostrarCriarConta || criandoConta)
              Column(
                children: [
                  const SizedBox(height: 16),
                  TextField(
                    controller: senhaController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                      border: OutlineInputBorder(),
                    ),
                  ),
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
                      onPressed: criarConta,
                      child: const Text('Criar conta'),
                    ),
                  ),
                ],
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: verificarLogin,
                child: const Text('Entrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InformacoesScreen extends StatefulWidget {
  final String login;
  final Map<String, dynamic>? dadosPreenchidos;
  const InformacoesScreen({super.key, required this.login, this.dadosPreenchidos});
  @override
  State<InformacoesScreen> createState() => _InformacoesScreenState();
}


class _InformacoesScreenState extends State<InformacoesScreen> {
  final List<String> vacinas = [
    'BCG', 'Hepatite A', 'Hepatite B', 'Penta (DTP/Hib/Hep. B)', 'Pneumocócica 10-valente',
    'Vacina Inativada Poliomielite (VIP)', 'Vacina Oral Poliomielite (VOP)', 'Vacina Rotavírus Humano (VRH)',
    'Meningocócica C (conjugada)', 'Menigocócica ACWY', 'Febre amarela', 'Tríplice viral',
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

  // Controllers para todos os campos
  final nomeController = TextEditingController();
  final nascimentoController = TextEditingController();
  final idadeController = TextEditingController();
  final pesoController = TextEditingController();
  final alturaController = TextEditingController();
  final contatoNomeController = TextEditingController();
  final contatoTelefoneController = TextEditingController();
  final contatoParentescoController = TextEditingController();
  final sangueController = TextEditingController();
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
    for (var v in vacinas) {
      vacinasStatus[v] = false;
    }
    // Preencher controllers se dadosPreenchidos existir
    final dados = widget.dadosPreenchidos;
    if (dados != null) {
      nomeController.text = (dados['nome'] ?? '').toString();
      nascimentoController.text = (dados['data_nascimento'] ?? '').toString();
      idadeController.text = (dados['idade'] ?? '').toString();
      pesoController.text = (dados['peso'] ?? '').toString();
      alturaController.text = (dados['altura'] ?? '').toString();
      contatoNomeController.text = (dados['contato_emerg_nome'] ?? '').toString();
      contatoTelefoneController.text = (dados['contato_emerg'] ?? '').toString();
      contatoParentescoController.text = (dados['contato_emerg_grau'] ?? '').toString();
      tipoSanguineoSelecionado = (dados['sangue'] ?? 'A+').toString();
      // Converte bool do banco para 'Sim'/'Não'
      final transfusaoBanco = dados['transfusao'];
      autorizacaoTransfusao = (transfusaoBanco == true) ? 'Sim' : 'Não';
      final doacaoBanco = dados['doacao_orgaos'];
      autorizacaoDoacaoOrgaos = (doacaoBanco == true) ? 'Sim' : 'Não';
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
      for (var vacina in vacinas) {
        vacinasStatus[vacina] = dados[vacina] ?? false;
      }
    }
  }

  Future<void> salvarNoBanco() async {
    final supabase = Supabase.instance.client;
    int? parseIntOrNull(String value) {
      final v = value.trim();
      if (v.isEmpty) return null;
      return int.tryParse(v);
    }
    final dados = {
      'login': widget.login,
      'nome': nomeController.text,
      'data_nascimento': nascimentoController.text,
      'idade': parseIntOrNull(idadeController.text),
      'peso': parseIntOrNull(pesoController.text),
      'altura': parseIntOrNull(alturaController.text),
      'contato_emerg_nome': contatoNomeController.text,
      'contato_emerg': contatoTelefoneController.text,
      'contato_emerg_grau': contatoParentescoController.text,
      'sangue': tipoSanguineoSelecionado,
      // Salva como bool
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
      'doses_cov': parseIntOrNull(dosesCovidController.text),
      'fabricante_cov': fabricanteCovidController.text,
      'data_h1n1': dataH1n1Controller.text,
      'vac_outras': outrasVacinaController.text,
      // Cada vacina como campo separado
      for (var vacina in vacinas)
        vacina: vacinasStatus[vacina] ?? false,
    };
  await supabase.from('anamnese').upsert(dados);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informações')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dados Pessoais', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // Campo de login removido
            TextField(controller: nomeController, decoration: const InputDecoration(labelText: 'Nome completo')),
            TextField(controller: nascimentoController, decoration: const InputDecoration(labelText: 'Data de nascimento')),
            TextField(controller: idadeController, decoration: const InputDecoration(labelText: 'Idade')),
            TextField(controller: pesoController, decoration: const InputDecoration(labelText: 'Peso')),
            TextField(controller: alturaController, decoration: const InputDecoration(labelText: 'Altura')),
            const SizedBox(height: 16),
            const Text('Contato de Emergência', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(controller: contatoNomeController, decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: contatoTelefoneController, decoration: const InputDecoration(labelText: 'Telefone')),
            TextField(controller: contatoParentescoController, decoration: const InputDecoration(labelText: 'Grau de parentesco')),
            const SizedBox(height: 16),
            const Text('Dados Médicos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            const Text('Assistência Médica', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Dispositivos Médicos', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(controller: dispositivosController, decoration: const InputDecoration(labelText: 'Implantes e outros dispositivos médicos')),
            const SizedBox(height: 16),
            const Text('Observações Médicas', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(controller: observacoesController, decoration: const InputDecoration(labelText: 'Informações adicionais relevantes')),
            const SizedBox(height: 24),
            const Text('Carteira de Vacinação', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                    TextField(controller: dataH1n1Controller, decoration: const InputDecoration(labelText: 'Data da última aplicação')),
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
                onPressed: () async {
                  await salvarNoBanco();
                  final link = 'www.pullmed.netlify.app/${widget.login}';
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => GravarNfcScreen(link: link)),
                  );
                },
                child: const Text('Avançar para Gravar NFC'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GravarNfcScreen extends StatefulWidget {
  final String link;
  const GravarNfcScreen({super.key, required this.link});
  @override
  State<GravarNfcScreen> createState() => _GravarNfcScreenState();
}

class _GravarNfcScreenState extends State<GravarNfcScreen> {
  bool _nfcGravado = false;
  bool _gravando = false;
  String? _erroNfc;

  void _iniciarGravacao() async {
    setState(() {
      _gravando = true;
      _erroNfc = null;
    });
    try {
      bool isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) throw Exception('NFC não disponível neste dispositivo');

      await NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
        try {
          final link = widget.link;
          final ndef = Ndef.from(tag);
          if (ndef != null && ndef.isWritable) {
            final ndefMessage = NdefMessage([
              NdefRecord.createUri(Uri.parse(link)),
            ]);
            await ndef.write(ndefMessage);
            setState(() {
              _gravando = false;
              _nfcGravado = true;
              _erroNfc = null;
            });
          }
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo_pullmed.png', width: 120),
            const SizedBox(height: 32),
            if (_nfcGravado)
              const Icon(Icons.check_circle, color: Colors.green, size: 64)
            else if (_gravando)
              const Icon(Icons.fiber_manual_record, color: Colors.orange, size: 64)
            else
              const Icon(Icons.fiber_manual_record, color: Colors.red, size: 64),
            const SizedBox(height: 32),
            if (_gravando)
              const Text('Aproxime a pulseira com a tag NFC...', style: TextStyle(fontSize: 16, color: Colors.orange, fontWeight: FontWeight.bold))
            else if (_nfcGravado)
              const Text('Gravação com sucesso!', style: TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.bold))
            else if (_erroNfc != null)
              Column(
                children: [
                  Text(_erroNfc!, style: const TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold)),
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
    );
  }
}
