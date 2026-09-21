"""
Lambda de ingestao para o NASA Exoplanet Archive.

NAO fica em api.nasa.gov, NAO usa api_key, e NAO e uma URL de endpoint fixa
como as outras - e um servico TAP (Table Access Protocol) que recebe uma
query em ADQL (dialeto de SQL). Aqui pedimos os 50 exoplanetas confirmados
mais recentes, ordenados por ano de descoberta.
Fonte: https://exoplanetarchive.ipac.caltech.edu/docs/TAP/usingTAP.html
"""
import json
import os
import time
import urllib.parse
import urllib.request
import urllib.error

import boto3

API_NAME = "exoplanet_archive"
IMAGES_BUCKET = os.environ["IMAGES_BUCKET"]
API_DATA_TABLE = os.environ["API_DATA_TABLE"]
HISTORY_TABLE = os.environ["HISTORY_TABLE"]

ADQL_QUERY = (
    "select top 50 pl_name,hostname,disc_year,discoverymethod "
    "from ps order by disc_year desc"
)
EXOPLANET_ARCHIVE_URL = (
    "https://exoplanetarchive.ipac.caltech.edu/TAP/sync?query="
    + urllib.parse.quote(ADQL_QUERY)
    + "&format=json"
)

dynamodb = boto3.resource("dynamodb")


def _fetch_from_exoplanet_archive() -> dict:
    try:
        with urllib.request.urlopen(EXOPLANET_ARCHIVE_URL, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as e:
        raise RuntimeError(f"Falha ao chamar o NASA Exoplanet Archive: {e}")


def handler(event, context):
    dados = _fetch_from_exoplanet_archive()

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