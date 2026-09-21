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


def handler(event, context):
    api_key = _get_api_key()
    dados = _fetch_from_nasa(api_key)

    agora = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    dados_serializados = json.dumps(dados)[:390000]  # limite de item do DynamoDB

    api_data_table = dynamodb.Table(API_DATA_TABLE)
    api_data_table.put_item(Item={
        "api_name": API_NAME,
        "updated_at": agora,
        "data": dados_serializados,
    })

    history_table = dynamodb.Table(HISTORY_TABLE)
    history_table.put_item(Item={
        "api_name": API_NAME,
        "fetched_at": agora,
        "data": dados_serializados,
    })

    # TODO: se a resposta contiver imagem (EPIC, Mars Rover Photos, APOD com
    # media_type=image), baixar e salvar no bucket IMAGES_BUCKET aqui.

    return {"statusCode": 200, "api_name": API_NAME, "fetched_at": agora}