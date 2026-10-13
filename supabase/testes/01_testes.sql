-- Testes da migration (rodar depois de 00_simula_supabase.sql, da migration e do seed).
-- NÃO rode no Supabase de produção: cria usuários de teste.
\pset footer off
-- auxiliares só do teste
create function pid(text) returns bigint language sql stable security definer as $$ select id from public.produtos where nome = $1 $$;
create function item(text, int) returns jsonb language sql stable as $$ select jsonb_build_object('produto_id', pid($1), 'quantidade', $2) $$;
create function qtd(text) returns int language sql stable security definer as $$ select quantidade from public.produtos where nome = $1 $$;
grant execute on function pid(text), item(text,int), qtd(text) to authenticated, anon;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
 ('00000000-0000-0000-0000-00000000000a', 'ana@eleve.com.br',   '{"nome":"Ana Souza"}',    '{}'),
 ('00000000-0000-0000-0000-00000000000b', 'bruno@eleve.com.br', '{"nome":"Bruno Lima"}',   '{}'),
 ('00000000-0000-0000-0000-00000000000c', 'carla@eleve.com.br', '{"nome":"Carla Mendes"}', '{"papel":"admin"}'),
 ('00000000-0000-0000-0000-00000000000d', 'tenta@eleve.com.br', '{"nome":"Tenta","papel":"admin"}', '{}');
\echo '== T1 perfis (papel admin só via app_metadata; "Tenta" pôs admin no user_metadata e virou vendedor)'
select nome, papel from perfis order by nome;
\echo '== T1b ids do seed seguem a ordem da lista'
select id, nome from produtos where id in (1, 8, 16) order by id;

set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
\echo '== T2 vendedora vê só ativos (esperado 15 / 4 baixos / 2 esgotados)'
select count(*) visiveis, count(*) filter (where status_estoque='baixo') baixos, count(*) filter (where status_estoque='esgotado') esgotados from produtos_status;
\echo '== T3 vendedora não cadastra produto (espera erro RLS)'
insert into produtos (nome, categoria_id, preco) values ('Hackeado', 1, 1);
\echo '== T4 vendedora não grava venda direto (espera erro RLS)'
insert into vendas (vendedor_id, subtotal, total, forma_pagamento) values ('00000000-0000-0000-0000-00000000000a', 10, 10, 'pix');
\echo '== T5 vendedora não muda estoque direto (UPDATE 0 e quantidade segue 6)'
update produtos set quantidade = 999 where nome = 'Camiseta Eleve preta – P';
select qtd('Camiseta Eleve preta – P') as camiseta_p;

\echo '== T6 venda: 2x Camiseta P (em 2 linhas) + 1x Bíblia NVI, 10%, Pix => subtotal 209,70, desc 20,97, total 188,73'
select subtotal, desconto, total, forma_pagamento from registrar_venda(jsonb_build_array(item('Camiseta Eleve preta – P',1), item('Bíblia NVI capa dura preta',1), item('Camiseta Eleve preta – P',1)), 'pix', 'percentual', 10);
select nome_produto, preco_unitario, quantidade, subtotal from venda_itens order by id;
select qtd('Camiseta Eleve preta – P') camiseta_p_era_6, qtd('Bíblia NVI capa dura preta') biblia_era_12;

\echo '== T7 estoque insuficiente: Moletom G tem 1, pede 2'
select registrar_venda(jsonb_build_array(item('Moletom Eleve amarelo – G',2)), 'pix');
\echo '== T7b nada foi gravado pela venda recusada (Moletom G segue 1)'
select qtd('Moletom Eleve amarelo – G') moletom_g;
\echo '== T8 produto esgotado: O peregrino'
select registrar_venda(jsonb_build_array(item('Livro O peregrino',1)), 'pix');
\echo '== T9 produto inativo: Pulseira'
select registrar_venda(jsonb_build_array(item('Pulseira Sábado 18h30',1)), 'pix');
\echo '== T10 desconto em R$ maior que subtotal (Caneca 39,90 com R$ 50)'
select registrar_venda(jsonb_build_array(item('Caneca Eleve 350 ml',1)), 'dinheiro', 'valor', 50);
\echo '== T10b desconto em R$ válido: Caneca 39,90 - 9,90 = 30,00 em dinheiro'
select subtotal, desconto_tipo, desconto_informado, desconto, total from registrar_venda(jsonb_build_array(item('Caneca Eleve 350 ml',1)), 'dinheiro', 'valor', 9.90);
\echo '== T11 sem itens / pagamento inválido / quantidade zero'
select registrar_venda('[]', 'pix');
select registrar_venda(jsonb_build_array(item('Caneca Eleve 350 ml',1)), 'cheque');
select registrar_venda(jsonb_build_array(item('Caneca Eleve 350 ml',0)), 'pix');

\echo '== T12 Carla (admin) limita desconto de vendedor a 10%'
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
update configuracoes set desconto_max_vendedor_pct = 10;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
\echo '   Ana tenta 15% (espera DESCONTO_ACIMA_DO_LIMITE … 10%)'
select registrar_venda(jsonb_build_array(item('Ecobag Eleve',1)), 'pix', 'percentual', 15);
\echo '   Ana tenta R$ 5 em 34,90 (14%, espera bloqueio)'
select registrar_venda(jsonb_build_array(item('Ecobag Eleve',1)), 'pix', 'valor', 5);
\echo '   Ana com 10% passa'
select total from registrar_venda(jsonb_build_array(item('Ecobag Eleve',1)), 'pix', 'percentual', 10);
\echo '   Carla (admin) dá 15% (sem limite)'
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select total from registrar_venda(jsonb_build_array(item('Ecobag Eleve',1)), 'pix', 'percentual', 15);

\echo '== T13 admin vê inativos (16), cadastra e ajusta'
select count(*) produtos_admin from produtos;
insert into produtos (nome, categoria_id, preco, quantidade, estoque_minimo) values ('Agenda Eleve 2027', 5, 29.90, 10, 3);
update produtos set quantidade = quantidade + 5 where nome = 'Livro O peregrino';
\echo '== T14 nome repetido ignorando acento/maiúscula/pontuação (2 erros esperados)'
insert into produtos (nome, categoria_id, preco) values ('caneca eleve — 350 ML', 5, 10);
insert into produtos (nome, categoria_id, preco) values ('Biblia NVI capa dura preta', 3, 10);
\echo '== T14b quantidade negativa bloqueada'
update produtos set quantidade = -1 where nome = 'Ecobag Eleve';

\echo '== T15 movimentações (vendas, cadastro novo e ajuste)'
select p.nome, m.tipo, m.quantidade, m.saldo, m.venda_id, pf.nome usuario
from movimentacoes_estoque m join produtos p on p.id = m.produto_id left join perfis pf on pf.id = m.usuario_id
where m.tipo <> 'cadastro' or p.nome = 'Agenda Eleve 2027' order by m.id;

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
\echo '== T16 Bruno vê todas as vendas com vendedor'
select v.id, pf.nome vendedor, v.subtotal, v.desconto, v.total, v.forma_pagamento from vendas v join perfis pf on pf.id = v.vendedor_id order by v.id desc;
\echo '   Bruno não lê movimentações (0)'
select count(*) from movimentacoes_estoque;
\echo '   Bruno não se promove a admin (UPDATE 0)'
update perfis set papel = 'admin' where id = '00000000-0000-0000-0000-00000000000b';
\echo '   Bruno não apaga venda (DELETE 0)'
delete from vendas;

\echo '== T17 Carla desativa Ana; Ana perde acesso'
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
update perfis set ativo = false where id = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select (select count(*) from produtos) produtos, (select count(*) from vendas) vendas, (select count(*) from perfis) perfis;
select registrar_venda(jsonb_build_array(item('Ecobag Eleve',1)), 'pix');

\echo '== T18 anônimo: sem função e sem dados'
reset role; set role anon;
select registrar_venda(jsonb_build_array(item('Ecobag Eleve',1)), 'pix');
select count(*) produtos_anon from produtos;
reset role;
