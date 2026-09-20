"""
Lambda de ingestao para a API "eonet" da NASA.

ATENCAO - isto e um esqueleto funcional, nao uma integracao final:
cada API da NASA tem particularidades proprias (parametros obrigatorios,
as vezes dominio diferente de api.nasa.gov) que precisam ser ajustadas
aqui antes de ir pra producao. Ver comentario TODO abaixo.
"""
import json
import os
import time
import urllib.request
import urllib.error

import boto3

API_NAME = "eonet"
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
    # TODO: cada API tem parametros proprios (ex: NeoWs precisa de
    # start_date/end_date; EONET nao usa api_key; SSD/CNEOS fica em
    # ssd-api.jpl.nasa.gov, nao em api.nasa.gov). Ajustar por API.
    url = f"https://api.nasa.gov{ENDPOINT_PATH}?api_key={api_key}"
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as e:
        raise RuntimeError(f"Falha ao chamar a API da NASA (eonet): {e}")


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