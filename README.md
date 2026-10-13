# Eleve · Balcão — controle de estoque e vendas

App interno para a equipe da loja do Eleve consultar o estoque e registrar vendas no balcão, pelo celular. Este repositório tem o **design aprovado**, um **protótipo navegável**, o **banco de dados pronto para o Supabase** e o **prompt** para construir o app de verdade.

## Por onde começar

1. **Ver o protótipo:** abra `prototipo/index.html` no navegador (duplo clique; não precisa instalar nada). Para ver todas as telas e estados lado a lado, abra `prototipo/telas.html`.
   - Contas de teste do protótipo, senha `eleve123`: `ana@eleve.com.br` (vendedora), `bruno@eleve.com.br` (vendedor), `carla@eleve.com.br` (admin).
   - Cada estado tem um endereço próprio: `index.html?cenario=estoque&perfil=admin`. Os cenários são `login`, `login-erro`, `login-carregando`, `venda`, `venda-vazia`, `venda-esgotado`, `confirmacao`, `estoque`, `estoque-carregando`, `estoque-erro`, `estoque-vazio`, `produto`, `historico`, `historico-vazio` e `detalhe`.
   - As fontes vêm do Google Fonts; sem internet, o protótipo usa fontes reserva.
2. **Construir o app:** cole `docs/PROMPT.md` na ferramenta que vai programar (Lovable, Bolt, Claude Code…).
3. **Criar o banco:** no Supabase, abra SQL Editor, cole `supabase/migrations/20261013000000_esquema_inicial.sql` e rode. Depois siga a seção 9 do prompt (desligar o cadastro aberto e criar o primeiro admin). O `supabase/seed.sql` é opcional e só serve para ter produtos de exemplo.

## O que tem aqui

| Pasta | Conteúdo |
|---|---|
| `docs/PROMPT.md` | Resumo completo do projeto: telas, regras, identidade visual, banco, erros e critérios de aceite |
| `prototipo/` | Protótipo que roda direto no navegador (gerado a partir do design) |
| `design/canvas/` | Arquivos-fonte do canvas de design (`Main.dc.html` tem todas as telas; os outros são os quadros de cada estado) |
| `design/referencias/` | Logo e artes do Eleve usadas como referência visual |
| `supabase/migrations/` | Banco completo: tabelas, segurança (RLS), auditoria de estoque e a função `registrar_venda` |
| `supabase/seed.sql` | 16 produtos de exemplo (camisetas, moletons, Bíblias, livros, acessórios) |
| `supabase/testes/` | Testes do banco num PostgreSQL local |
| `tools/build-prototipo.mjs` | Regera o `prototipo/` a partir de `design/canvas/` |

## Banco de dados em uma olhada

- `perfis`: equipe (vendedor/admin, ativo)
- `categorias`: categorias dos produtos
- `produtos`: estoque, sem código/SKU; o nome é único
- `vendas`: cabeçalho de cada venda (vendedor, data e hora, subtotal, desconto, total, pagamento)
- `venda_itens`: itens de cada venda, com nome e preço copiados na hora da venda
- `movimentacoes_estoque`: quem mexeu no estoque, quanto e por quê (automático)
- `configuracoes`: limite de desconto do vendedor

A venda só entra pela função `registrar_venda`, que confere o estoque no servidor e grava tudo de uma vez. Detalhes completos estão na seção 9 do `docs/PROMPT.md`.

### Como o banco foi testado

A migration e o seed rodaram num PostgreSQL 16 local, com `supabase/testes/00_simula_supabase.sql` imitando a parte de autenticação do Supabase. O `supabase/testes/01_testes.sql` confere:
- permissões de vendedor e de admin;
- venda com desconto em % e em R$;
- recusa por estoque insuficiente, produto inativo ou desconto acima do limite;
- nome repetido;
- registro das movimentações;
- conta desativada e acesso anônimo.

Também foi testado que, com duas vendas simultâneas da última peça, uma passa e a outra recebe `ESTOQUE_INSUFICIENTE`.

**O que não foi testado:** rodar dentro de um projeto Supabase real. Rode a migration num projeto novo antes de usar com dados de verdade.

Para repetir os testes localmente (requer PostgreSQL 15+ com `unaccent`; não rode isso no Supabase):

```bash
createdb eleve_teste
psql -d eleve_teste -f supabase/testes/00_simula_supabase.sql
psql -d eleve_teste -f supabase/migrations/20261013000000_esquema_inicial.sql
psql -d eleve_teste -f supabase/seed.sql
psql -d eleve_teste -f supabase/testes/01_testes.sql
```

## Regerar o protótipo depois de mudar o design

```bash
node tools/build-prototipo.mjs
```

Lê `design/canvas/Main.dc.html` e `canvas.json` e reescreve `prototipo/index.html` e `prototipo/telas.html`. O `prototipo/dc-runtime.js` é um interpretador mínimo do formato do canvas, feito só para visualizar; o app real não deve usá-lo.
