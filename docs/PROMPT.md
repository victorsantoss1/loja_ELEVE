# Prompt — Eleve · Balcão (controle de estoque e vendas)

> Cole este texto na ferramenta que vai construir o app (Lovable, Bolt, Claude Code, Cursor…), com este repositório importado. Os arquivos citados existem nele.

---

## 1. O que construir

Um app web responsivo, **de uso interno**, para a equipe da loja do **Eleve** (ministério de igreja) registrar vendas no balcão e consultar o estoque. **Não é loja virtual**: o cliente nunca acessa. O uso principal é no **celular pessoal de cada voluntário**, com uma mão só e fila no balcão, antes e depois do culto de sábado. Também precisa funcionar bem no computador.

## 2. Referências no repositório (siga à risca)

- `prototipo/index.html`: protótipo navegável com todas as telas, textos, estados e interações. Abra no navegador. Use `?cenario=…&perfil=admin` para ver cada estado; `prototipo/telas.html` mostra todas as telas lado a lado. **É a referência de layout e comportamento.**
- `design/canvas/Main.dc.html`: fonte do protótipo. A classe JS no fim do arquivo tem os cálculos, validações e textos de exemplo. Use como especificação; **não** reaproveite o mini-runtime de `prototipo/dc-runtime.js` no app real.
- `design/referencias/`: logo e artes do Eleve.
- `supabase/migrations/20261013000000_esquema_inicial.sql`: **banco completo** (tabelas, segurança, função de venda). Testado em PostgreSQL 16. Rode como está.
- `supabase/seed.sql`: produtos de exemplo (opcional).

## 3. Stack

React + TypeScript + Vite + Tailwind + Supabase (Auth, Postgres, Storage, Edge Functions). Sem servidor próprio: as regras críticas ficam no banco (RLS + função `registrar_venda`). Pode ser PWA instalável (ícone na tela inicial), mas **sem venda offline**.

## 4. Perfis e acesso

- **Vendedor:** entra, registra vendas, consulta estoque e histórico (vê as vendas de todos).
- **Admin:** tudo do vendedor, mais: cadastrar, editar, desativar e reativar produtos; ver produtos inativos; gerenciar a equipe; definir o limite de desconto.
- **Sem cadastro aberto.** Quem cria as contas é o admin. Login com e-mail e senha; a sessão fica salva no celular até a pessoa tocar em "Sair".
- **Conta desativada** (`perfis.ativo = false`) perde o acesso na hora. Se a leitura do próprio perfil vier vazia depois do login, deslogue e mostre "Seu acesso foi removido. Fale com o administrador."

## 5. Navegação

- **Celular (< 900px):** no topo, o logo, "BALCÃO", a etiqueta do papel e o avatar (o menu do avatar tem nome, e-mail, papel e Sair). Embaixo, uma barra fixa com 3 abas: **Venda · Estoque · Vendas**. A aba Venda mostra um badge com o número de unidades no carrinho.
- **Desktop (≥ 900px):** menu lateral escuro com as mesmas abas e, embaixo, o cartão do usuário com Sair.
- A tela inicial é **Venda**.

## 6. Telas

### Login
E-mail; senha com mostrar/ocultar; botão "Entrar" com estado de carregando. Erro "E-mail ou senha incorretos" em bloco vermelho. Valida campo vazio e e-mail inválido. Textos: "Você continua conectado neste celular até tocar em Sair" e "Não tem acesso? As contas são criadas pelo administrador da loja."

### Nova venda (a tela mais importante)
- **Busca só pelo nome** (não existe código/SKU). Ignora acento e maiúscula e aceita palavras em qualquer ordem: "moletom g" encontra "Moletom Eleve amarelo – G". No celular, os resultados aparecem enquanto a pessoa digita (no máximo 6). No desktop, a lista de produtos ativos fica sempre à esquerda e o carrinho à direita.
- **Cada resultado** mostra foto (ou ícone da categoria), nome, categoria, quantidade em estoque (em âmbar se estiver baixa), preço e o botão "Adicionar". Produto esgotado: botão "Esgotado" desabilitado. Se todo o estoque já está no carrinho: botão "No limite".
- **Carrinho:** nome, "R$ X cada", botões − quantidade +, subtotal do item e remover. O "+" desabilita quando chega no estoque, com o aviso amarelo "Só há N unidades em estoque. Não é possível adicionar mais." O "−" desabilita em 1. Tem também "Limpar venda".
- **"Tem desconto?"** Não / Sim (o padrão é Não). Com Sim, aparece o campo de valor e a troca entre % e R$. Mostre ao vivo: "Desconto de R$ X · Total: R$ Y". Erros: percentual acima de 100%, valor em R$ maior que o subtotal, e campo vazio com Sim marcado.
- **Forma de pagamento (obrigatória):** Pix, Débito, Crédito ou Dinheiro, em botões grandes 2×2, um selecionado por vez. Sem parcelas.
- **Resumo** (bloco verde-petróleo): Subtotal, Desconto (negativo) e **TOTAL FINAL** grande em amarelo.
- **"Finalizar venda":** no celular, fica numa barra fixa acima das abas, junto com o total. No desktop, abaixo do resumo. Fica desabilitado mostrando o motivo: "Adicione pelo menos 1 item", "Escolha a forma de pagamento", "Corrija o valor do desconto" ou "Informe o desconto ou marque Não".
- **Ao finalizar:** chame `supabase.rpc('registrar_venda', …)` (seção 9). O botão mostra "Registrando…". Use os valores que o servidor devolver, não o cálculo local. Se der erro, traduza a mensagem (seção 10), **mantenha o carrinho** e recarregue o estoque.

### Venda registrada
"Venda registrada", número da venda, TOTAL FINAL grande, forma de pagamento, **data e hora (dd/mm/aaaa HH:mm, fuso America/Sao_Paulo)**, vendedor, itens, subtotal e desconto. Botões "Nova venda" (principal) e "Ver no histórico".

### Estoque
- Faixa amarela no topo: "N produtos com estoque baixo · Toque para ver só esses · M esgotados". Tocar filtra só os baixos. Com o filtro ativo, a faixa vira "Só estoque baixo (N) · Ver todos".
- Busca por nome e filtro por categoria (chips).
- **Card do produto:** foto ou ícone, nome, "categoria · mín. X", preço, quantidade em número grande e etiqueta **Em estoque / Baixo / Esgotado** (cor e texto).
- **Baixo** = quantidade maior que 0 e menor ou igual ao estoque mínimo. **Esgotado** = 0 (não pode ser vendido).
- **Só para admin:** botão "Novo produto", "Editar" em cada card, e produtos inativos no fim da lista com a etiqueta "Inativo" e o botão "Editar / reativar".

### Cadastro e edição de produto (admin)
- **Campos:** foto (opcional; câmera ou galeria, salva no bucket `produtos`), nome, categoria, preço, quantidade em estoque e estoque mínimo. **Não existe código/SKU.**
- **Ajuda abaixo do nome:** "Tem tamanho ou cor? Coloque no nome. Ex.: Moletom Eleve amarelo – G".
- **Validação** (ao tocar em salvar e, a partir daí, ao vivo): nome obrigatório com pelo menos 3 letras; nome repetido, ignorando acento, maiúscula e pontuação; categoria; preço maior que 0; quantidade 0 ou mais; mínimo 0 ou mais. Mostre um resumo: "Corrija N campos destacados".
- **Na edição:** bloco "Produto ativo · Desativar produto" (ou "Reativar"). **Nunca apagar produto.**

### Vendas (histórico)
- Da mais recente para a mais antiga, agrupadas por dia ("sáb., 10/10/2026 · N vendas").
- **Card:** data e hora, forma de pagamento, vendedor, número, itens com quantidade, subtotal, desconto e total.
- Carregue de 30 em 30 (rolagem infinita).
- **Tocar no card abre o detalhe:** data e hora, vendedor, pagamento, número de unidades, itens (qtd × preço = subtotal), subtotal, desconto (com o % quando houver) e total.

### Equipe (admin) — **não está no protótipo; precisa ser criada no mesmo estilo**
- Lista de pessoas: nome, e-mail, papel e se está ativa.
- **Adicionar pessoa** (nome, e-mail, senha inicial, papel): faça por uma Edge Function `criar-membro` com a service role. Ela confere se quem chamou é admin ativo (tabela `perfis`) e chama `auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { nome }, app_metadata: { papel } })`. O perfil é criado sozinho por um gatilho no banco.
- **Desativar e reativar:** `update perfis set ativo = …` (a RLS só permite isso para admin).
- Campo **"Desconto máximo do vendedor (%)"**, que grava em `configuracoes.desconto_max_vendedor_pct` (100 = sem limite).

## 7. Estados obrigatórios

- **Carregando:** esqueleto pulsando e o texto "Carregando estoque…".
- **Erro de conexão:** "Sem conexão" e o botão "Tentar novamente".
- **Busca sem resultado ou lista vazia:** botão "Limpar busca e filtros".
- **Histórico vazio:** botão "Fazer uma venda".
- **Carrinho vazio, produto esgotado e aviso de limite de estoque.**
- **Aviso curto de confirmação** ("Adicionado: …", "Produto cadastrado"), que some ao finalizar a venda.

## 8. Identidade visual (Eleve)

**Cores**
- **Fundo:** papel creme `#EDE5CE` com quadriculado leve (linhas `rgba(34,27,22,.07)` a cada 24px).
- **Cards:** `#FBF6E8`, borda de 1,5 a 2px `#221B16`, cantos de 10 a 12px, sem sombra borrada.
- **Tinta** (texto e bordas): `#221B16`. Texto secundário: `#4E4235`.
- **Amarelo-limão do logo `#FBFF0C`:** botões principais e seleção. Sempre texto escuro e borda `#221B16`; **nunca texto branco sobre amarelo**. Os botões principais têm uma sombra em degrau: `0 4px 0 #221B16`.
- **Laranja-tomate `#DE4C24`:** blocos de título, com texto creme `#F6ECD8`, e só com letras de 28px para cima (por contraste).
- **Verde-petróleo `#105F52`:** etiquetas e bloco do total (texto creme; o valor do total em amarelo).
- **Estoque:** normal com fundo `#D2E5DD` e texto `#0B4A40`; baixo com fundo `#FBFF0C` e texto `#221B16`; esgotado com fundo `#FAD5C8` e texto `#9E2F12`; inativo com fundo `#E2D8C6`.
- **Erro:** `#B3361A`. O lilás `#AC63D5` e o azul-ardósia `#47566A` são só decoração.

**Fontes** (empacote junto com o app; não dependa do Google Fonts no salão)
- **Anton:** títulos, botões grandes e total, em caixa alta.
- **Archivo:** texto corrido.
- **Space Mono:** etiquetas, preços, datas e rótulos, em caixa alta.
- **Permanent Marker:** só para as poucas anotações decorativas.

**Composição**
- **Título de cada tela:** bloco tomate levemente inclinado (−1,5°) com uma etiqueta verde-petróleo encostada embaixo.
- **Decoração** (inclinação, anotação à mão, fita lilás, pincelada) só no login, nos títulos, na confirmação e nos estados vazios. **Carrinho, listas e formulários ficam retos e limpos.**
- **Logo:** `design/referencias/eleve-logo.png`. Tem só 153×147px, então não amplie acima de uns 96px.

**Acessibilidade**
- Área de toque de no mínimo 44px e contraste AA.
- `<label>` de verdade em todos os campos e `aria-label` nos botões que só têm ícone.
- Ícones de traço (por exemplo, Lucide).

## 9. Banco de dados (Supabase)

Rode **`supabase/migrations/20261013000000_esquema_inicial.sql`** inteiro no SQL Editor. Ele cria:

**perfis** — uma linha por pessoa da equipe (o e-mail fica em `auth.users`)
| coluna | tipo | regra |
|---|---|---|
| id | uuid PK | = `auth.users.id` |
| nome | text | 2 a 80 caracteres |
| papel | text | `vendedor` ou `admin` (padrão `vendedor`) |
| ativo | boolean | `false` = sem acesso |
| criado_em | timestamptz | |

Um gatilho cria o perfil quando uma conta é criada. O nome vem de `user_metadata.nome`. O papel vem de `app_metadata.papel`, que só o servidor consegue definir.

**categorias** — `id`, `nome` (único), `ordem`. Já vem com: Camisetas, Moletons, Bíblias, Livros, Acessórios.

**produtos**
| coluna | tipo | regra |
|---|---|---|
| id | bigint PK | automático |
| nome | text | ≥ 3 letras; **único** ignorando acento, maiúscula e pontuação; tamanho e cor vão no nome |
| categoria_id | bigint FK → categorias | obrigatório |
| preco | numeric(10,2) | > 0 |
| quantidade | integer | ≥ 0 (nunca negativa) |
| estoque_minimo | integer | ≥ 0 |
| foto_url | text | opcional |
| ativo | boolean | desativar em vez de apagar |
| criado_em, atualizado_em | timestamptz | `atualizado_em` é automático |

A view **produtos_status** traz o produto junto com `categoria`, `categoria_ordem` e `status_estoque` (`normal`/`baixo`/`esgotado`). Use essa view nas telas.

**vendas**
| coluna | tipo | regra |
|---|---|---|
| id | bigint PK | é o "Venda #N" (pode pular números; não é nota fiscal) |
| vendedor_id | uuid FK → perfis | quem vendeu |
| criado_em | timestamptz | data e hora |
| subtotal | numeric(10,2) | > 0 |
| desconto_tipo | text | `percentual`, `valor` ou null |
| desconto_informado | numeric(10,2) | o que foi digitado (10 = 10%, ou R$ 10,00) |
| desconto | numeric(10,2) | desconto em R$; ≤ subtotal |
| total | numeric(10,2) | = subtotal − desconto |
| forma_pagamento | text | `pix`, `debito`, `credito` ou `dinheiro` |

**venda_itens** — `id`, `venda_id` (FK), `produto_id` (FK), **`nome_produto` e `preco_unitario` copiados na hora da venda** (o histórico não muda se o produto mudar depois), `quantidade` (> 0) e `subtotal` (= preço × quantidade).

**movimentacoes_estoque** (auditoria automática) — `produto_id`, `tipo` (`cadastro`/`venda`/`ajuste`), `quantidade` (variação ±), `saldo`, `venda_id`, `usuario_id` e `criado_em`. É preenchida por gatilho em toda mudança de quantidade. Só o admin lê.

**configuracoes** (sempre 1 linha) — `desconto_max_vendedor_pct` (0 a 100; o padrão 100 significa sem limite; o admin não tem limite).

**Função `registrar_venda`** — a **única** forma de gravar uma venda:
```ts
const { data: venda, error } = await supabase.rpc('registrar_venda', {
  p_itens: [{ produto_id: 1, quantidade: 2 }, { produto_id: 8, quantidade: 1 }],
  p_forma_pagamento: 'pix',          // pix | debito | credito | dinheiro
  p_desconto_tipo: 'percentual',     // 'percentual' | 'valor' | null
  p_desconto_informado: 10,          // 10 (%) ou 20.00 (R$); 0 se não houver desconto
});
```
- Pega o preço e o nome do banco (nunca confia no preço enviado pelo celular).
- Trava os produtos enquanto grava, para dois celulares não venderem a mesma última peça.
- Confere estoque, produto ativo, desconto e o limite do vendedor.
- Grava a venda, os itens e a baixa de estoque de uma vez só: ou entra tudo, ou nada.
- Devolve a linha da venda.

**Segurança (RLS, já incluída)**
- Só quem está logado e ativo lê qualquer coisa.
- O vendedor vê só produtos ativos; o admin vê todos e é o único que cadastra e edita.
- Ninguém apaga produto, venda ou pessoa.
- Ninguém grava venda direto na tabela; só pela função.
- Só o admin altera perfis e configurações e lê as movimentações.
- Usuário anônimo não vê nada.

**Storage:** bucket público `produtos`, para as fotos. Só o admin envia, troca e apaga.

**Configuração manual no painel do Supabase**
1. Authentication › Sign In / Providers: **desligue "Allow new users to sign up"**.
2. Crie o primeiro admin: Authentication › Add user (com e-mail confirmado). Depois rode `update perfis set papel = 'admin' where id = (select id from auth.users where email = 'SEU_EMAIL');`
3. Database › Publications: inclua `produtos` no `supabase_realtime` e assine as mudanças no app. Assim, quando um celular vende, os outros veem o estoque atualizado sem recarregar.

## 10. Erros de `registrar_venda` → mensagem para quem está vendendo

A mensagem do erro começa com um código:
| código | mostrar |
|---|---|
| `ESTOQUE_INSUFICIENTE` | "O estoque de {produto} mudou: só há {n}. Ajuste a quantidade." (recarregue o estoque) |
| `PRODUTO_INDISPONIVEL` | "{produto} não está mais disponível. Remova do carrinho." |
| `DESCONTO_ACIMA_DO_LIMITE` | "Seu limite de desconto é {x}%. Peça a um admin." |
| `DESCONTO_INVALIDO` | "Confira o valor do desconto." |
| `PAGAMENTO_INVALIDO` | "Escolha a forma de pagamento." |
| `VENDA_SEM_ITENS` / `QUANTIDADE_INVALIDA` | "Confira os itens da venda." |
| `USUARIO_INVALIDO` | deslogar: "Seu acesso foi removido ou expirou. Entre de novo." |
| falha de rede | "Sem conexão. A venda NÃO foi registrada. Tente de novo." (mantenha o carrinho) |

## 11. Regras gerais

- **Dinheiro:** `numeric(10,2)` no banco. Mostre com `Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })`. O app calcula para mostrar; quem calcula o valor que vale é o banco.
- **Datas:** `timestamptz` no banco. Mostre como `dd/mm/aaaa HH:mm` no fuso America/Sao_Paulo.
- **Nada se apaga:** produto e pessoa se desativam; venda não se edita.
- **Busca:** ignore acento e maiúscula e aceite palavras em qualquer ordem. O catálogo é pequeno (centenas de itens), então pode filtrar no próprio app.

## 12. Fora do escopo agora

Cancelamento e estorno de venda, relatórios e filtros avançados, parcelamento, pagamento dividido, área do cliente, código de barras ou SKU, cálculo de troco.

## 13. Decisões em aberto (pergunte antes de inventar)

1. Tamanhos e cores como **variações de um mesmo produto** (hoje cada tamanho é um produto separado).
2. **Estorno de venda** (deve ser a próxima prioridade, senão o estoque perde a confiabilidade).
3. Calcular troco quando o pagamento for em Dinheiro.
4. **Fechamento de caixa** por culto: quanto entrou em Pix, cartão e dinheiro.

## 14. Critérios de aceite

- [ ] Vendedor não vê o botão "Novo produto", não vê produtos inativos e não consegue editar produto (a interface esconde e o banco bloqueia).
- [ ] "Finalizar venda" fica desabilitado sem item ou sem forma de pagamento, e mostra o motivo.
- [ ] Não dá para colocar no carrinho mais do que há em estoque; produto esgotado não pode ser adicionado.
- [ ] Desconto em % e em R$ atualiza Subtotal, Desconto e Total ao vivo; desconto acima do subtotal é bloqueado.
- [ ] A venda grava via `registrar_venda`; a confirmação mostra o total e a data e hora do servidor; o estoque baixa.
- [ ] Dois celulares vendendo a última peça ao mesmo tempo: um consegue, o outro vê "estoque mudou".
- [ ] O histórico mostra data e hora, vendedor, itens, subtotal, desconto, total e pagamento, da venda mais nova para a mais antiga.
- [ ] Admin cadastra produto sem código; nome repetido é recusado.
- [ ] Admin desativa uma pessoa e ela perde o acesso na próxima ação.
- [ ] Funciona com uma mão num celular de 360px de largura e com menu lateral no computador.
