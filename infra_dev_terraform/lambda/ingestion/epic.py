"""
Lambda de ingestao para a API "epic" da NASA.

Endpoint padrao de api.nasa.gov - funciona apenas com api_key.
"""
import json
import os
import time
import urllib.request
import urllib.error

import boto3

API_NAME = "epic"
ENDPOINT_PATH = os.environ["ENDPOINT_PATH"]
IMAGES_BUCKET = os.environ["IMAGES_BUCKET"]
API_DATA_TABLE = os.environ["API_DATA_TABLE"]
HISTORY_TABLE = os.environ["HISTORY_TABLE"]
NASA_API_KEY_SECRET_ARN = os.environ["NASA_API_KEY_SECRET_ARN"]

secrets_client = boto3.client("secretsmanager")
dynamodb = boto3.resource("dynamodb")
s3_client = boto3.client("s3")


def _get_api_key() -> str:
    resp = secrets_client.get_secret_value(SecretId=NASA_API_KEY_SECRET_ARN)
    return resp["SecretString"]


def _fetch_from_nasa(api_key: str) -> dict:
    # Este endpoint funciona so com api_key, sem parametros extras.
    url = f"https://api.nasa.gov{ENDPOINT_PATH}?api_key={api_key}"
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as e:
        raise RuntimeError(f"Falha ao chamar a API da NASA (epic): {e}")


def _baixar_e_salvar_imagem(dados: list, api_key: str) -> str:
    """
    A resposta do EPIC e uma LISTA de imagens do dia (uma a cada ~1-2h).
    Pra manter o escopo simples no MVP, baixamos so a mais recente (primeiro
    item da lista). A URL da imagem em si nao vem pronta na resposta -
    precisa ser montada a partir da data + nome do arquivo.
    """
    if not dados:
        return ""

    imagem = dados[0]
    nome_arquivo = imagem.get("image")
    data_completa = imagem.get("date")  # formato: "2026-09-20 00:31:00"
    if not nome_arquivo or not data_completa:
        return ""

    ano, mes, dia = data_completa.split(" ")[0].split("-")
    image_url = (
        f"https://epic.gsfc.nasa.gov/archive/natural/{ano}/{mes}/{dia}"
        f"/png/{nome_arquivo}.png?api_key={api_key}"
    )
    s3_key = f"epic/{nome_arquivo}.png"

    try:
        with urllib.request.urlopen(image_url, timeout=20) as response:
            imagem_bytes = response.read()
        s3_client.put_object(Bucket=IMAGES_BUCKET, Key=s3_key, Body=imagem_bytes)
        return s3_key
    except (urllib.error.URLError, Exception) as e:
        print(f"Aviso: falha ao baixar imagem do EPIC: {e}")
        return ""


def handler(event, context):
    api_key = _get_api_key()
    dados = _fetch_from_nasa(api_key)
    image_s3_key = _baixar_e_salvar_imagem(dados, api_key)

    agora = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    dados_serializados = json.dumps(dados)[:390000]  # limite de item do DynamoDB

    api_data_table = dynamodb.Table(API_DATA_TABLE)
    api_data_table.put_item(Item={
        "api_name": API_NAME,
        "updated_at": agora,
        "data": dados_serializados,
        "image_s3_key": image_s3_key,
    })

    history_table = dynamodb.Table(HISTORY_TABLE)
    history_table.put_item(Item={
        "api_name": API_NAME,
        "fetched_at": agora,
        "data": dados_serializados,
        "image_s3_key": image_s3_key,
    })

    return {"statusCode": 200, "api_name": API_NAME, "fetched_at": agora, "image_s3_key": image_s3_key}