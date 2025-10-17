# Guia de Contribuição / Contributing Guide

Obrigado por considerar contribuir para o PULLMED! / Thank you for considering contributing to PULLMED!

## 📁 Como Adicionar Arquivos do Projeto / How to Add Project Files

Se você tem seu projeto em uma pasta e quer adicioná-lo ao GitHub, siga estes passos:

### Passo 1: Preparar os Arquivos

```bash
# Copie os arquivos do seu projeto para o repositório clonado
# Copy your project files to the cloned repository
cp -r /caminho/para/sua/pasta/* /caminho/para/PULLMED/

# Ou mova os arquivos
# Or move the files
mv /caminho/para/sua/pasta/* /caminho/para/PULLMED/
```

### Passo 2: Verificar os Arquivos

```bash
# Entre no diretório do repositório
cd /caminho/para/PULLMED/

# Verifique o status dos arquivos
git status
```

### Passo 3: Adicionar os Arquivos

```bash
# Adicione todos os arquivos novos
git add .

# Ou adicione arquivos específicos
git add src/
git add index.html
```

### Passo 4: Fazer Commit

```bash
# Faça commit das mudanças
git commit -m "Add project files"
```

### Passo 5: Enviar para o GitHub

```bash
# Envie para o GitHub
git push origin main
```

## 📂 Estrutura de Pastas Sugerida / Suggested Folder Structure

```
PULLMED/
├── README.md
├── .gitignore
├── package.json
├── src/
│   ├── frontend/
│   │   ├── index.html
│   │   ├── css/
│   │   │   └── styles.css
│   │   ├── js/
│   │   │   └── app.js
│   │   └── images/
│   ├── backend/
│   │   ├── server.js
│   │   ├── routes/
│   │   ├── controllers/
│   │   └── models/
│   └── database/
│       └── schema.sql
├── tests/
│   ├── frontend/
│   └── backend/
├── docs/
│   └── API.md
└── config/
    └── config.js
```

## 🔄 Fluxo de Trabalho / Workflow

1. **Fork** o repositório
2. Crie uma **branch** para sua funcionalidade (`git checkout -b feature/nova-funcionalidade`)
3. **Commit** suas mudanças (`git commit -m 'Adiciona nova funcionalidade'`)
4. **Push** para a branch (`git push origin feature/nova-funcionalidade`)
5. Abra um **Pull Request**

## ✅ Checklist antes de Fazer Commit / Pre-Commit Checklist

- [ ] Código está formatado corretamente
- [ ] Todos os testes passam
- [ ] Documentação foi atualizada se necessário
- [ ] Commits têm mensagens descritivas
- [ ] Código segue o estilo do projeto

## 💡 Dicas / Tips

- **Commits Pequenos**: Faça commits frequentes com mudanças pequenas e focadas
- **Mensagens Claras**: Use mensagens de commit descritivas
- **Teste Antes**: Sempre teste seu código antes de fazer commit
- **Documente**: Mantenha a documentação atualizada

## 🐛 Reportando Bugs / Reporting Bugs

Ao reportar um bug, inclua:

- Descrição clara do problema
- Passos para reproduzir
- Comportamento esperado vs atual
- Screenshots se aplicável
- Informações do sistema/navegador

## 💬 Perguntas? / Questions?

Se você tiver dúvidas, abra uma issue ou entre em contato!

---

**Nota**: Este é um guia vivo e pode ser atualizado conforme o projeto evolui.
