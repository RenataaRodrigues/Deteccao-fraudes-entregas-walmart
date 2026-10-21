-- Detecção de fraudes em entregas - consultas da análise
-- Tabelas: pedidos, entregadores, itens_perdidos, produtos (ver dados/*.csv)
-- Dialeto: SQLite (funções de data com strftime, o resto é SQL padrão)


-- 1. Visão geral ------------------------------------------------------------
SELECT
    COUNT(*)                                               AS total_pedidos,
    SUM(CASE WHEN items_missing > 0 THEN 1 ELSE 0 END)     AS pedidos_com_perda,
    SUM(items_missing)                                     AS itens_perdidos,
    ROUND(AVG(CASE WHEN items_missing > 0 THEN 1.0 ELSE 0 END) * 100, 1) AS pct_pedidos_com_perda
FROM pedidos;


-- 2. Taxa de pedidos com perda por região --------------------------------------
-- Comparar taxas, não totais: Winter Park tem mais pedidos que Clermont.
SELECT
    region,
    COUNT(*)                                               AS pedidos,
    SUM(items_missing)                                     AS itens_perdidos,
    ROUND(AVG(CASE WHEN items_missing > 0 THEN 1.0 ELSE 0 END) * 100, 1) AS pct_pedidos_com_perda
FROM pedidos
GROUP BY region
ORDER BY pct_pedidos_com_perda DESC;


-- 3. Taxa por dia da semana (0 = domingo) ----------------------------------------
SELECT
    CAST(strftime('%w', order_date) AS INTEGER)            AS dia_semana,
    COUNT(*)                                               AS pedidos,
    ROUND(AVG(CASE WHEN items_missing > 0 THEN 1.0 ELSE 0 END) * 100, 1) AS pct_pedidos_com_perda
FROM pedidos
GROUP BY dia_semana
ORDER BY dia_semana;


-- 4. Quantos entregadores concentram as perdas? -----------------------------------
-- Distribuição dos entregadores pelo total de itens perdidos.
WITH por_entregador AS (
    SELECT driver_id, COUNT(*) AS pedidos, SUM(items_missing) AS itens_perdidos
    FROM pedidos
    GROUP BY driver_id
)
SELECT
    itens_perdidos,
    COUNT(*)            AS entregadores,
    ROUND(AVG(pedidos), 1) AS media_pedidos
FROM por_entregador
GROUP BY itens_perdidos
ORDER BY itens_perdidos;


-- 5. Ranking de entregadores -----------------------------------------------------
-- Agrupa por driver_id (há nomes repetidos: dois "Timothy Brown" diferentes) e
-- usa a taxa como critério, com desempate explícito.
SELECT
    p.driver_id,
    e.driver_name,
    e.age,
    COUNT(*)                                               AS pedidos,
    SUM(CASE WHEN p.items_missing > 0 THEN 1 ELSE 0 END)   AS pedidos_com_perda,
    SUM(p.items_missing)                                   AS itens_perdidos,
    ROUND(AVG(CASE WHEN p.items_missing > 0 THEN 1.0 ELSE 0 END) * 100, 1) AS pct_pedidos_com_perda
FROM pedidos p
JOIN entregadores e ON e.driver_id = p.driver_id
GROUP BY p.driver_id, e.driver_name, e.age
ORDER BY pct_pedidos_com_perda DESC, itens_perdidos DESC, p.driver_id
LIMIT 10;


-- 6. Perfil: entregadores com e sem perda ------------------------------------------
WITH por_entregador AS (
    SELECT driver_id, COUNT(*) AS pedidos, SUM(items_missing) AS itens_perdidos
    FROM pedidos
    GROUP BY driver_id
)
SELECT
    CASE WHEN pe.itens_perdidos > 0 THEN 'com perda' ELSE 'sem perda' END AS grupo,
    COUNT(*)                     AS entregadores,
    ROUND(AVG(e.age), 1)         AS idade_media,
    ROUND(AVG(pe.pedidos), 1)    AS pedidos_medios,
    SUM(pe.pedidos)              AS pedidos_total
FROM por_entregador pe
JOIN entregadores e ON e.driver_id = pe.driver_id
GROUP BY grupo;


-- 7. Itens perdidos por produto ---------------------------------------------------
-- Cada pedido pode listar até 3 produtos perdidos. "Desempilha" as três colunas
-- com UNION ALL. Um JOIN com OR contaria só uma vez o produto repetido na linha
-- e, na versão original, deixava de fora o product_id_3.
WITH perdidos AS (
    SELECT order_id, product_id_1 AS product_id FROM itens_perdidos WHERE product_id_1 <> ''
    UNION ALL
    SELECT order_id, product_id_2 FROM itens_perdidos WHERE product_id_2 <> ''
    UNION ALL
    SELECT order_id, product_id_3 FROM itens_perdidos WHERE product_id_3 <> ''
)
SELECT
    pr.product_name,
    pr.product_group,
    COUNT(*)                     AS vezes_perdido,
    pr.price                     AS preco,
    ROUND(COUNT(*) * pr.price, 2) AS valor_perdido
FROM perdidos pd
JOIN produtos pr ON pr.product_id = pd.product_id
GROUP BY pr.product_name, pr.product_group, pr.price
ORDER BY valor_perdido DESC
LIMIT 10;


-- 8. Eletrônicos x mercado: quantidade e valor ----------------------------------------
WITH perdidos AS (
    SELECT order_id, product_id_1 AS product_id FROM itens_perdidos WHERE product_id_1 <> ''
    UNION ALL
    SELECT order_id, product_id_2 FROM itens_perdidos WHERE product_id_2 <> ''
    UNION ALL
    SELECT order_id, product_id_3 FROM itens_perdidos WHERE product_id_3 <> ''
)
SELECT
    pr.product_group,
    COUNT(*)                                                       AS itens,
    ROUND(SUM(pr.price), 2)                                        AS valor,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)             AS pct_itens,
    ROUND(SUM(pr.price) * 100.0 / SUM(SUM(pr.price)) OVER (), 1)   AS pct_valor
FROM perdidos pd
JOIN produtos pr ON pr.product_id = pd.product_id
GROUP BY pr.product_group;


-- 9. Taxa de perda por faixa de valor do pedido (quartis) -----------------------------
WITH q AS (
    SELECT *, NTILE(4) OVER (ORDER BY order_amount) AS quartil
    FROM pedidos
)
SELECT
    quartil,
    ROUND(MIN(order_amount), 2) AS de,
    ROUND(MAX(order_amount), 2) AS ate,
    COUNT(*)                    AS pedidos,
    ROUND(AVG(CASE WHEN items_missing > 0 THEN 1.0 ELSE 0 END) * 100, 1) AS pct_pedidos_com_perda
FROM q
GROUP BY quartil
ORDER BY quartil;
