"""
Lambda de ingestao para a API "apod" da NASA.

Endpoint padrao de api.nasa.gov - funciona apenas com api_key.
"""
import json
import os
import time
import urllib.request
import urllib.error

import boto3

API_NAME = "apod"
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
        raise RuntimeError(f"Falha ao chamar a API da NASA (apod): {e}")


def _baixar_e_salvar_imagem(dados: dict) -> str:
    """
    APOD pode ser foto ou video (campo media_type). So baixamos quando for
    imagem. Usa hdurl (alta resolucao) se existir, senao url.
    Retorna a chave no S3, ou string vazia se nao havia imagem pra baixar.
    """
    if dados.get("media_type") != "image":
        return ""

    image_url = dados.get("hdurl") or dados.get("url")
    if not image_url:
        return ""

    data_da_foto = dados.get("date", time.strftime("%Y-%m-%d", time.gmtime()))
    extensao = image_url.split(".")[-1].split("?")[0][:4] or "jpg"
    s3_key = f"apod/{data_da_foto}.{extensao}"

    try:
        with urllib.request.urlopen(image_url, timeout=20) as response:
            imagem_bytes = response.read()
        s3_client.put_object(Bucket=IMAGES_BUCKET, Key=s3_key, Body=imagem_bytes)
        return s3_key
    except (urllib.error.URLError, Exception) as e:
        # Falha ao baixar imagem nao deveria derrubar a ingestao dos dados -
        # os dados textuais (titulo, explicacao) ja foram obtidos e valem
        # a pena salvar mesmo sem a imagem.
        print(f"Aviso: falha ao baixar imagem do APOD: {e}")
        return ""


def handler(event, context):
    api_key = _get_api_key()
    dados = _fetch_from_nasa(api_key)
    image_s3_key = _baixar_e_salvar_imagem(dados)

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