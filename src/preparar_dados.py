"""Extrai as tabelas do modelo do Power BI e grava CSVs limpos em dados/.

Uso:
    python src/preparar_dados.py

Os arquivos originais (orders.csv e a planilha de apoio) não existem mais; a
cópia mais completa dos dados é o modelo dentro do .pbix do dashboard.
"""
from pathlib import Path

import pandas as pd
from pbixray import PBIXRay

RAIZ = Path(__file__).resolve().parents[1]
PBIX = RAIZ / "dashboard" / "monitoramento-entregas.pbix"
SAIDA = RAIZ / "dados"


def dinheiro(s: pd.Series) -> pd.Series:
    """'$1,234.56' -> 1234.56"""
    return s.astype(str).str.replace("$", "", regex=False).str.replace(",", "", regex=False).astype(float)


def main() -> None:
    modelo = PBIXRay(str(PBIX))
    SAIDA.mkdir(exist_ok=True)

    # Pedidos -------------------------------------------------------------
    ped = modelo.get_table("Pedidos").rename(columns={
        "Data": "order_date", "Id do Pedido": "order_id", "Valor do Pedido": "order_amount",
        "Região": "region", "Itens Entregues": "items_delivered", "Itens Perdidos": "items_missing",
        "Hora da Entrega": "delivery_hour", "Id do Entregador": "driver_id", "Id do Cliente": "customer_id",
    })
    ped["order_date"] = pd.to_datetime(ped["order_date"]).dt.date
    # o Power BI guarda hora como data-base 1899-12-30 + fração; arredonda para o segundo
    ped["delivery_hour"] = pd.to_datetime(ped["delivery_hour"]).dt.round("s").dt.strftime("%H:%M:%S")
    ped["order_amount"] = dinheiro(ped["order_amount"])
    ped = ped[["order_id", "order_date", "delivery_hour", "region", "driver_id", "customer_id",
               "items_delivered", "items_missing", "order_amount"]].sort_values(["order_date", "delivery_hour"])

    # Entregadores --------------------------------------------------------
    ent = modelo.get_table("Entregadores").rename(columns={
        "Id do Entregador": "driver_id", "Nome do Entregador": "driver_name",
        "Idade do Entregador": "age", "Total de Viagens": "trips",
    })[["driver_id", "driver_name", "age", "trips"]]

    # Itens perdidos: a planilha foi importada sem cabeçalho, então a linha de
    # títulos virou dado ("order_id", "Id produto 1"...). Remove.
    ip = modelo.get_table("Itens Perdidos").rename(columns={
        "Id do Pedido": "order_id", "Id do Produto 1": "product_id_1",
        "Id do Produto 2": "product_id_2", "Id do Produto 3": "product_id_3",
    })
    ip = ip[ip["order_id"].isin(ped["order_id"])]

    # Produtos: mesma linha de cabeçalho perdida; a coluna de id veio com o nome
    # errado na origem (produc_id) e as categorias, exceto Electronics, estão
    # trocadas (ex.: Pepsi como Dairy). A análise usa só Eletrônicos x Mercado.
    prod = modelo.get_table("Produtos").rename(columns={
        "Id do Pedido": "product_id", "Nome do Produto": "product_name",
        "Categoria": "category_original", "Preço do Produto": "price",
    })
    prod = prod[prod["product_id"].str.startswith("PWPX")].copy()
    prod["price"] = dinheiro(prod["price"])
    prod["product_group"] = prod["category_original"].map(lambda c: "Eletrônicos" if c == "Electronics" else "Mercado")
    prod = prod[["product_id", "product_name", "product_group", "category_original", "price"]]

    for nome, df in {"pedidos": ped, "entregadores": ent, "itens_perdidos": ip, "produtos": prod}.items():
        df.to_csv(SAIDA / f"{nome}.csv", index=False, encoding="utf-8")
        print(f"{nome}.csv: {len(df)} linhas")


if __name__ == "__main__":
    main()
