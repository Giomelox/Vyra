"""
Lambda de ingestao para SSD/CNEOS - Close Approach Data (asteroides).

NAO fica em api.nasa.gov e NAO usa api_key - e um servico publico da JPL.
Defaults da propria API ja fazem sentido para o nosso caso (aproximacoes
de NEOs a menos de 0.05 au nos proximos 60 dias).
Fonte: https://ssd-api.jpl.nasa.gov/doc/cad.html
"""
import json
import os
import time
import urllib.request
import urllib.error

import boto3

API_NAME = "ssd_cneos"
IMAGES_BUCKET = os.environ["IMAGES_BUCKET"]
API_DATA_TABLE = os.environ["API_DATA_TABLE"]
HISTORY_TABLE = os.environ["HISTORY_TABLE"]

CNEOS_URL = "https://ssd-api.jpl.nasa.gov/cad.api"

dynamodb = boto3.resource("dynamodb")


def _fetch_from_cneos() -> dict:
    try:
        with urllib.request.urlopen(CNEOS_URL, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as e:
        raise RuntimeError(f"Falha ao chamar a API SSD/CNEOS: {e}")


def handler(event, context):
    dados = _fetch_from_cneos()

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