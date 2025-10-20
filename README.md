# PullMed

Aplicativo Flutter para dados médicos pessoais e gravação em NFC.

## Preparar repositório antes do push

1. Remova chaves sensíveis do código. Em particular, remova ou substitua o `anonKey` do Supabase em `lib/main.dart`.
	- Preferível: armazenar chaves em variáveis de ambiente e passar via `--dart-define` no build.

2. Confirme que `.gitignore` está presente (ele já foi atualizado).

3. Opcional: crie um arquivo `.env` local para variáveis e não o comite.

## Criar repositório remoto e enviar

No terminal, execute (substitua o email/nome conforme necessário):

```powershell
git config user.name "Gabriela"
git config user.email "gabriela@example.com"
# crie o repo no GitHub (ou use a UI do GitHub)
# localmente:
git add .
git commit -m "Prepare project for GitHub"
# adicione o remote (SSH)
git remote add origin git@github.com:gabiciancia/PULLMED.git
# ou com HTTPS:
# git remote add origin https://github.com/gabiciancia/PULLMED.git

git push -u origin main
```

Se o push falhar por autenticação, configure o SSH (adicionar chave pública no GitHub) ou use `gh auth login`.

## Build para iOS

Abra `ios/Runner.xcworkspace` no Xcode e rode no dispositivo.

## Notas
- Remova chaves sensíveis antes de publicar. O projeto contém o `anonKey` atualmente; substitua por uma variável de ambiente antes de mandar pro GitHub.

