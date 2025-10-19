# PullMed (Flutter)

Projeto Flutter para gerenciamento de dados médicos com gravação em NFC e integração com Supabase.

## Preparar para desenvolvimento

- Instale Flutter e configure o ambiente (https://flutter.dev/docs/get-started/install).
- Execute `flutter pub get` para instalar dependências.

## Rodar no Android

- Conecte um dispositivo ou use um emulador.
- `flutter run`

## Rodar no iOS (via Xcode)

- Abra `ios/Runner.xcworkspace` no Xcode.
- Ajuste o signing (Team) nas configurações do projeto.
- Rode no dispositivo físico (NFC não funciona no simulador).

## Segurança / Segredos

O projeto atualmente contém uma `anonKey` do Supabase no código para facilitar testes. Antes de publicar no GitHub, mova essa chave para variáveis de ambiente e remova do código.

Sugestão rápida:

1. Crie um arquivo `.env` (não comitar) e defina `SUPABASE_ANON_KEY=...`.
2. Use um pacote como `flutter_dotenv` para carregar a variável em tempo de execução.
# flutter_application_1

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-start ed/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
