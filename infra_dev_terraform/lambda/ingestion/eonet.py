"""
Lambda de ingestao para a API EONET (eventos naturais) da NASA.

EONET NAO fica em api.nasa.gov e NAO usa api_key - e um servico publico
separado, hospedado pela NASA Goddard. Por isso esta Lambda nao chama o
Secrets Manager (diferente das outras 8).
Fonte: https://eonet.gsfc.nasa.gov/api/v3/events
"""
import json
import os
import time
import urllib.request
import urllib.error

import boto3

API_NAME = "eonet"
IMAGES_BUCKET = os.environ["IMAGES_BUCKET"]
API_DATA_TABLE = os.environ["API_DATA_TABLE"]
HISTORY_TABLE = os.environ["HISTORY_TABLE"]

EONET_URL = "https://eonet.gsfc.nasa.gov/api/v3/events?status=open&limit=50"

dynamodb = boto3.resource("dynamodb")


def _fetch_from_eonet() -> dict:
    try:
        with urllib.request.urlopen(EONET_URL, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as e:
        raise RuntimeError(f"Falha ao chamar a API EONET: {e}")


def handler(event, context):
    dados = _fetch_from_eonet()

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