-- Produtos de exemplo (os mesmos do protótipo). Opcional: rode depois da migration
-- só se quiser começar com dados para testar. Apague antes de usar de verdade.
insert into public.produtos (nome, categoria_id, preco, quantidade, estoque_minimo, ativo)
select v.nome, c.id, v.preco, v.quantidade, v.minimo, v.ativo
from (values
  ( 1, 'Camiseta Eleve preta – P',          'Camisetas',  59.90,  6, 3, true),
  ( 2, 'Camiseta Eleve preta – M',          'Camisetas',  59.90,  2, 4, true),
  ( 3, 'Camiseta Eleve preta – G',          'Camisetas',  59.90,  8, 4, true),
  ( 4, 'Camiseta O Dia do Senhor – M',      'Camisetas',  69.90,  0, 3, true),
  ( 5, 'Camiseta O Dia do Senhor – G',      'Camisetas',  69.90,  5, 3, true),
  ( 6, 'Moletom Eleve amarelo – M',         'Moletons',  149.90,  4, 2, true),
  ( 7, 'Moletom Eleve amarelo – G',         'Moletons',  149.90,  1, 2, true),
  ( 8, 'Bíblia NVI capa dura preta',        'Bíblias',    89.90, 12, 5, true),
  ( 9, 'Bíblia de estudo NAA',              'Bíblias',   189.90,  3, 3, true),
  (10, 'Livro Cristianismo puro e simples', 'Livros',     49.90,  7, 3, true),
  (11, 'Livro O peregrino',                 'Livros',     39.90,  0, 2, true),
  (12, 'Devocional Pão Diário 2027',        'Livros',     34.90, 15, 5, true),
  (13, 'Caneca Eleve 350 ml',               'Acessórios', 39.90,  9, 4, true),
  (14, 'Boné Eleve verde',                  'Acessórios', 69.90,  2, 3, true),
  (15, 'Ecobag Eleve',                      'Acessórios', 34.90,  4, 2, true),
  (16, 'Pulseira Sábado 18h30',             'Acessórios', 14.90,  0, 5, false)
) as v(ordem, nome, categoria, preco, quantidade, minimo, ativo)
join public.categorias c on c.nome = v.categoria
order by v.ordem;
