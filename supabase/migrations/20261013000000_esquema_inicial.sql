-- =====================================================================
-- Eleve · Balcão — esquema inicial do banco (Supabase / PostgreSQL 15+)
--
-- Como usar: Supabase › SQL Editor › colar tudo › Run.
-- (ou `supabase db push` se você usa a CLI)
--
-- Tabelas:
--   perfis                 1 por pessoa da equipe (liga com auth.users)
--   categorias             Camisetas, Moletons, Bíblias, Livros, Acessórios
--   produtos               o estoque
--   vendas                 cabeçalho de cada venda
--   venda_itens            itens de cada venda (com nome e preço da época)
--   movimentacoes_estoque  histórico de toda mudança de quantidade (auditoria)
--   configuracoes          1 linha com ajustes da loja (limite de desconto)
--
-- Regra de ouro: vendas só entram pela função registrar_venda(), que confere
-- o estoque no servidor e baixa tudo de uma vez. O app nunca grava direto
-- em vendas, venda_itens ou na quantidade dos produtos.
-- =====================================================================

create extension if not exists unaccent with schema extensions;

-- ---------------------------------------------------------------------
-- Funções auxiliares
-- ---------------------------------------------------------------------

-- Normaliza nomes para comparar: sem acento, minúsculo, só letras e números.
-- "Bíblia NVI – Capa Dura" e "biblia nvi capa dura" viram o mesmo texto.
create or replace function public.normalizar(t text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select btrim(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(t, ''))), '[^a-z0-9]+', ' ', 'g'));
$$;

create or replace function public.tocar_atualizado_em()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 1) Perfis da equipe
-- ---------------------------------------------------------------------
create table public.perfis (
  id         uuid primary key references auth.users (id) on delete cascade,
  nome       text not null check (char_length(btrim(nome)) between 2 and 80),
  papel      text not null default 'vendedor' check (papel in ('vendedor', 'admin')),
  ativo      boolean not null default true,       -- false = voluntário saiu; perde acesso na hora
  criado_em  timestamptz not null default now()
);

comment on table public.perfis is 'Pessoas da equipe. O e-mail fica em auth.users. Nunca apague: desative (ativo = false).';

-- Pessoa logada e ativa?
create or replace function public.usuario_ativo()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.perfis where id = auth.uid() and ativo);
$$;

-- Pessoa logada, ativa e admin?
create or replace function public.eh_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.perfis where id = auth.uid() and ativo and papel = 'admin');
$$;

-- Cria o perfil automaticamente quando uma conta é criada no Supabase Auth.
-- Nome vem de user_metadata.nome; papel vem de app_metadata.papel (só o servidor
-- consegue definir app_metadata, então ninguém se promove a admin sozinho).
create or replace function public.criar_perfil()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.perfis (id, nome, papel)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'nome'), ''), split_part(new.email, '@', 1)),
    case when new.raw_app_meta_data ->> 'papel' = 'admin' then 'admin' else 'vendedor' end
  );
  return new;
end;
$$;

create trigger ao_criar_usuario
  after insert on auth.users
  for each row execute function public.criar_perfil();

-- ---------------------------------------------------------------------
-- 2) Categorias
-- ---------------------------------------------------------------------
create table public.categorias (
  id     bigint generated always as identity primary key,
  nome   text not null unique check (char_length(btrim(nome)) >= 2),
  ordem  integer not null default 0
);

insert into public.categorias (nome, ordem) values
  ('Camisetas', 1),
  ('Moletons', 2),
  ('Bíblias', 3),
  ('Livros', 4),
  ('Acessórios', 5);

-- ---------------------------------------------------------------------
-- 3) Configurações da loja (sempre 1 linha)
-- ---------------------------------------------------------------------
create table public.configuracoes (
  id                         boolean primary key default true check (id),
  desconto_max_vendedor_pct  numeric(5, 2) not null default 100
                             check (desconto_max_vendedor_pct between 0 and 100)
);

comment on column public.configuracoes.desconto_max_vendedor_pct is
  'Maior desconto que um vendedor pode dar, em % do subtotal. 100 = sem limite. Admin não tem limite.';

insert into public.configuracoes default values;

-- ---------------------------------------------------------------------
-- 4) Produtos
-- ---------------------------------------------------------------------
create table public.produtos (
  id              bigint generated always as identity primary key,
  nome            text not null check (char_length(btrim(nome)) >= 3),  -- tamanho/cor vão no nome: "Camiseta Eleve preta – M"
  categoria_id    bigint not null references public.categorias (id),
  preco           numeric(10, 2) not null check (preco > 0),
  quantidade      integer not null default 0 check (quantidade >= 0),  -- nunca negativa
  estoque_minimo  integer not null default 0 check (estoque_minimo >= 0),
  foto_url        text,                                                 -- opcional (bucket "produtos")
  ativo           boolean not null default true,                        -- desativar em vez de apagar
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);

-- Sem código/SKU: o nome identifica o produto, então ele não pode repetir
-- (ignorando acentos, maiúsculas e pontuação).
create unique index produtos_nome_unico on public.produtos (public.normalizar(nome));
create index produtos_categoria_idx on public.produtos (categoria_id);

create trigger produtos_atualizado_em
  before update on public.produtos
  for each row execute function public.tocar_atualizado_em();

-- Produto + nome da categoria + situação do estoque, pronto para as telas.
-- "baixo" = quantidade no mínimo ou abaixo (e maior que zero); "esgotado" = zero.
create view public.produtos_status
with (security_invoker = true)
as
select
  p.*,
  c.nome  as categoria,
  c.ordem as categoria_ordem,
  case
    when p.quantidade = 0 then 'esgotado'
    when p.quantidade <= p.estoque_minimo then 'baixo'
    else 'normal'
  end as status_estoque
from public.produtos p
join public.categorias c on c.id = p.categoria_id;

-- ---------------------------------------------------------------------
-- 5) Vendas
-- ---------------------------------------------------------------------
create table public.vendas (
  id                  bigint generated always as identity primary key,  -- é o "Venda #123" das telas
  vendedor_id         uuid not null references public.perfis (id),
  criado_em           timestamptz not null default now(),               -- data e hora da venda
  subtotal            numeric(10, 2) not null check (subtotal > 0),
  desconto_tipo       text check (desconto_tipo in ('percentual', 'valor')),  -- null = sem desconto
  desconto_informado  numeric(10, 2) not null default 0 check (desconto_informado >= 0),  -- o que foi digitado: 10 (%) ou 20,00 (R$)
  desconto            numeric(10, 2) not null default 0 check (desconto >= 0),  -- desconto em R$
  total               numeric(10, 2) not null check (total >= 0),
  forma_pagamento     text not null check (forma_pagamento in ('pix', 'debito', 'credito', 'dinheiro')),
  check (desconto <= subtotal),
  check (total = subtotal - desconto),
  check (desconto_tipo is not null or (desconto = 0 and desconto_informado = 0))
);

create index vendas_criado_em_idx on public.vendas (criado_em desc);
create index vendas_vendedor_idx on public.vendas (vendedor_id);

create table public.venda_itens (
  id              bigint generated always as identity primary key,
  venda_id        bigint not null references public.vendas (id) on delete cascade,
  produto_id      bigint not null references public.produtos (id),
  nome_produto    text not null,                 -- cópia do nome na hora da venda
  preco_unitario  numeric(10, 2) not null check (preco_unitario > 0),  -- cópia do preço na hora da venda
  quantidade      integer not null check (quantidade > 0),
  subtotal        numeric(10, 2) not null,
  check (subtotal = preco_unitario * quantidade)
);

create index venda_itens_venda_idx on public.venda_itens (venda_id);
create index venda_itens_produto_idx on public.venda_itens (produto_id);

-- ---------------------------------------------------------------------
-- 6) Movimentações de estoque (quem mexeu, quanto e por quê)
-- ---------------------------------------------------------------------
create table public.movimentacoes_estoque (
  id          bigint generated always as identity primary key,
  produto_id  bigint not null references public.produtos (id),
  tipo        text not null check (tipo in ('cadastro', 'venda', 'ajuste')),
  quantidade  integer not null,          -- variação: positiva entra, negativa sai
  saldo       integer not null,          -- quantidade do produto depois da mudança
  venda_id    bigint references public.vendas (id),
  usuario_id  uuid references public.perfis (id),
  criado_em   timestamptz not null default now()
);

create index movimentacoes_produto_idx on public.movimentacoes_estoque (produto_id, criado_em desc);

-- Registra sozinho toda mudança de quantidade. Dentro de registrar_venda o
-- tipo é 'venda'; qualquer edição feita pelo admin vira 'ajuste'.
create or replace function public.registrar_movimentacao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tipo   text;
  v_venda  bigint;
begin
  if tg_op = 'INSERT' then
    if new.quantidade <> 0 then
      insert into public.movimentacoes_estoque (produto_id, tipo, quantidade, saldo, usuario_id)
      values (new.id, 'cadastro', new.quantidade, new.quantidade, auth.uid());
    end if;
    return new;
  end if;

  if new.quantidade = old.quantidade then
    return new;
  end if;

  v_tipo  := coalesce(nullif(current_setting('eleve.mov_tipo', true), ''), 'ajuste');
  v_venda := nullif(current_setting('eleve.venda_id', true), '')::bigint;

  insert into public.movimentacoes_estoque (produto_id, tipo, quantidade, saldo, venda_id, usuario_id)
  values (new.id, v_tipo, new.quantidade - old.quantidade, new.quantidade, v_venda, auth.uid());
  return new;
end;
$$;

create trigger produtos_movimentacao
  after insert or update of quantidade on public.produtos
  for each row execute function public.registrar_movimentacao();

-- ---------------------------------------------------------------------
-- 7) registrar_venda — a ÚNICA forma de gravar uma venda
--
-- Chamada pelo app:
--   supabase.rpc('registrar_venda', {
--     p_itens: [{ produto_id: 1, quantidade: 2 }, { produto_id: 8, quantidade: 1 }],
--     p_forma_pagamento: 'pix',                 -- pix | debito | credito | dinheiro
--     p_desconto_tipo: 'percentual',            -- percentual | valor | null
--     p_desconto_informado: 10                  -- 10 (%) ou 20.00 (R$); 0 se sem desconto
--   })
--
-- O que ela garante:
--   * pega preço e nome do banco (nunca confia no preço que veio do celular);
--   * trava os produtos enquanto vende (dois celulares não vendem a mesma última peça);
--   * recusa se faltar estoque, se o produto estiver inativo ou se o desconto passar do limite;
--   * grava venda + itens + baixa de estoque juntos (ou nada).
--
-- Erros que o app deve traduzir para o vendedor (vêm no início da mensagem):
--   USUARIO_INVALIDO, VENDA_SEM_ITENS, QUANTIDADE_INVALIDA, PAGAMENTO_INVALIDO,
--   PRODUTO_INDISPONIVEL, ESTOQUE_INSUFICIENTE, DESCONTO_INVALIDO, DESCONTO_ACIMA_DO_LIMITE
-- ---------------------------------------------------------------------
create or replace function public.registrar_venda(
  p_itens               jsonb,
  p_forma_pagamento     text,
  p_desconto_tipo       text default null,
  p_desconto_informado  numeric default 0
)
returns public.vendas
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario   uuid := auth.uid();
  v_papel     text;
  v_item      record;
  v_produto   public.produtos;
  v_subtotal  numeric(10, 2) := 0;
  v_desconto  numeric(10, 2) := 0;
  v_max_pct   numeric;
  v_venda     public.vendas;
begin
  select papel into v_papel from public.perfis where id = v_usuario and ativo;
  if v_papel is null then
    raise exception 'USUARIO_INVALIDO: faça login novamente';
  end if;

  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'VENDA_SEM_ITENS: adicione pelo menos 1 item';
  end if;

  if p_forma_pagamento is null or p_forma_pagamento not in ('pix', 'debito', 'credito', 'dinheiro') then
    raise exception 'PAGAMENTO_INVALIDO: escolha a forma de pagamento';
  end if;

  -- 1ª passada: agrupa itens repetidos, trava os produtos (em ordem de id,
  -- para não haver deadlock) e confere estoque.
  for v_item in
    select (e ->> 'produto_id')::bigint as produto_id, sum((e ->> 'quantidade')::integer)::integer as quantidade
    from jsonb_array_elements(p_itens) as e
    group by 1
    order by 1
  loop
    if v_item.produto_id is null or v_item.quantidade is null or v_item.quantidade <= 0 then
      raise exception 'QUANTIDADE_INVALIDA: quantidade precisa ser maior que zero';
    end if;

    select * into v_produto from public.produtos where id = v_item.produto_id for update;

    if not found or not v_produto.ativo then
      raise exception 'PRODUTO_INDISPONIVEL: %', coalesce(v_produto.nome, 'produto ' || v_item.produto_id);
    end if;

    if v_produto.quantidade < v_item.quantidade then
      raise exception 'ESTOQUE_INSUFICIENTE: % (disponível: %)', v_produto.nome, v_produto.quantidade;
    end if;

    v_subtotal := v_subtotal + v_produto.preco * v_item.quantidade;
  end loop;

  -- Desconto
  if p_desconto_tipo is null then
    if coalesce(p_desconto_informado, 0) <> 0 then
      raise exception 'DESCONTO_INVALIDO: informe o tipo do desconto';
    end if;
  elsif p_desconto_tipo = 'percentual' then
    if p_desconto_informado is null or p_desconto_informado <= 0 or p_desconto_informado > 100 then
      raise exception 'DESCONTO_INVALIDO: o percentual precisa ser entre 0 e 100';
    end if;
    v_desconto := round(v_subtotal * p_desconto_informado / 100, 2);
  elsif p_desconto_tipo = 'valor' then
    if p_desconto_informado is null or p_desconto_informado <= 0 or p_desconto_informado > v_subtotal then
      raise exception 'DESCONTO_INVALIDO: o desconto não pode passar do subtotal';
    end if;
    v_desconto := round(p_desconto_informado, 2);
  else
    raise exception 'DESCONTO_INVALIDO: tipo de desconto desconhecido';
  end if;

  if v_papel = 'vendedor' and v_desconto > 0 then
    select desconto_max_vendedor_pct into v_max_pct from public.configuracoes;
    if v_desconto > round(v_subtotal * coalesce(v_max_pct, 100) / 100, 2) then
      raise exception '%', 'DESCONTO_ACIMA_DO_LIMITE: vendedor pode dar no máximo '
        || replace(trim_scale(v_max_pct)::text, '.', ',') || '%';
    end if;
  end if;

  -- Grava a venda
  insert into public.vendas (vendedor_id, subtotal, desconto_tipo, desconto_informado, desconto, total, forma_pagamento)
  values (
    v_usuario,
    v_subtotal,
    p_desconto_tipo,
    case when p_desconto_tipo is null then 0 else p_desconto_informado end,
    v_desconto,
    v_subtotal - v_desconto,
    p_forma_pagamento
  )
  returning * into v_venda;

  -- Avisa o gatilho de movimentação que esta baixa é de uma venda
  perform set_config('eleve.mov_tipo', 'venda', true);
  perform set_config('eleve.venda_id', v_venda.id::text, true);

  -- 2ª passada: itens com nome/preço da época e baixa do estoque
  for v_item in
    select (e ->> 'produto_id')::bigint as produto_id, sum((e ->> 'quantidade')::integer)::integer as quantidade
    from jsonb_array_elements(p_itens) as e
    group by 1
    order by 1
  loop
    select * into v_produto from public.produtos where id = v_item.produto_id;

    insert into public.venda_itens (venda_id, produto_id, nome_produto, preco_unitario, quantidade, subtotal)
    values (v_venda.id, v_produto.id, v_produto.nome, v_produto.preco, v_item.quantidade, v_produto.preco * v_item.quantidade);

    update public.produtos set quantidade = quantidade - v_item.quantidade where id = v_item.produto_id;
  end loop;

  perform set_config('eleve.mov_tipo', '', true);
  perform set_config('eleve.venda_id', '', true);

  return v_venda;
end;
$$;

revoke all on function public.registrar_venda(jsonb, text, text, numeric) from public, anon;
grant execute on function public.registrar_venda(jsonb, text, text, numeric) to authenticated;

-- Estas funções só existem para os gatilhos; ninguém precisa chamá-las pela API.
revoke all on function public.criar_perfil() from public, anon, authenticated;
revoke all on function public.registrar_movimentacao() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 8) Segurança (RLS): quem pode ler e escrever o quê
-- ---------------------------------------------------------------------
alter table public.perfis                 enable row level security;
alter table public.categorias             enable row level security;
alter table public.configuracoes          enable row level security;
alter table public.produtos               enable row level security;
alter table public.vendas                 enable row level security;
alter table public.venda_itens            enable row level security;
alter table public.movimentacoes_estoque  enable row level security;

-- Perfis: equipe ativa vê a equipe (o histórico mostra quem vendeu); só admin altera.
-- Conta desativada não lê nem o próprio perfil: o app deve tratar isso como "acesso removido".
create policy "equipe vê a equipe" on public.perfis
  for select to authenticated using (public.usuario_ativo());
create policy "admin altera perfis" on public.perfis
  for update to authenticated using (public.eh_admin()) with check (public.eh_admin());

-- Categorias: todos leem; só admin mexe.
create policy "equipe lê categorias" on public.categorias
  for select to authenticated using (public.usuario_ativo());
create policy "admin cria categorias" on public.categorias
  for insert to authenticated with check (public.eh_admin());
create policy "admin altera categorias" on public.categorias
  for update to authenticated using (public.eh_admin()) with check (public.eh_admin());

-- Configurações: todos leem (o app mostra o limite de desconto); só admin altera.
create policy "equipe lê configurações" on public.configuracoes
  for select to authenticated using (public.usuario_ativo());
create policy "admin altera configurações" on public.configuracoes
  for update to authenticated using (public.eh_admin()) with check (public.eh_admin());

-- Produtos: vendedor vê só os ativos; admin vê todos, cadastra e edita. Ninguém apaga.
create policy "equipe vê produtos" on public.produtos
  for select to authenticated using (public.usuario_ativo() and (ativo or public.eh_admin()));
create policy "admin cadastra produtos" on public.produtos
  for insert to authenticated with check (public.eh_admin());
create policy "admin edita produtos" on public.produtos
  for update to authenticated using (public.eh_admin()) with check (public.eh_admin());

-- Vendas e itens: equipe ativa lê tudo; gravar só via registrar_venda(); ninguém edita nem apaga.
create policy "equipe vê vendas" on public.vendas
  for select to authenticated using (public.usuario_ativo());
create policy "equipe vê itens das vendas" on public.venda_itens
  for select to authenticated using (public.usuario_ativo());

-- Movimentações: só admin consulta.
create policy "admin vê movimentações" on public.movimentacoes_estoque
  for select to authenticated using (public.eh_admin());

-- ---------------------------------------------------------------------
-- 9) Fotos dos produtos (Supabase Storage, bucket público "produtos")
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('produtos', 'produtos', true)
on conflict (id) do nothing;

create policy "admin envia fotos" on storage.objects
  for insert to authenticated with check (bucket_id = 'produtos' and public.eh_admin());
create policy "admin troca fotos" on storage.objects
  for update to authenticated using (bucket_id = 'produtos' and public.eh_admin());
create policy "admin apaga fotos" on storage.objects
  for delete to authenticated using (bucket_id = 'produtos' and public.eh_admin());
