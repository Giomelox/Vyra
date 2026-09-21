/**
 * Earth Imagery sob demanda.
 *
 * Fluxo:
 * 1. Recebe lat/lon via query string.
 * 2. Arredonda a coordenada (2 casas decimais, ~1km) e monta uma chave S3 
 *    deterministica - isso É o cache: mesma coordenada = mesma chave.
 * 3. Checa se essa chave ja existe no S3 (HeadObject). Se existir, gera uma
 *    URL assinada e retorna direto, sem gastar chamada na API da NASA.
 * 4. Se nao existir: busca a api_key no Secrets Manager, chama a API da
 *    NASA, salva a imagem no S3, grava um registro no DynamoDB (history)
 *    e retorna a URL assinada da imagem recem-salva.
 *
 * Este arquivo assume que a task role do ECS ja tem permissao para:
 * s3:GetObject/PutObject no bucket de imagens, dynamodb:PutItem na tabela
 * de historico, e secretsmanager:GetSecretValue no secret da API key
 * (ver iam.tf / compute.tf no Terraform).
 */
import { NextRequest, NextResponse } from "next/server";
import { S3Client, HeadObjectCommand, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";

const REGION = process.env.AWS_REGION!;
const IMAGES_BUCKET = process.env.IMAGES_BUCKET!;
const HISTORY_TABLE = process.env.HISTORY_TABLE!;
const NASA_API_KEY_SECRET_ARN = process.env.NASA_API_KEY_SECRET_ARN!;

const s3 = new S3Client({ region: REGION });
const secretsManager = new SecretsManagerClient({ region: REGION });
const dynamo = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));

// Cache simples em memoria do processo - evita ler o secret a cada request.
// Se o secret for rotacionado, a task precisa reiniciar (aceitavel pro MVP).
let cachedApiKey: string | null = null;

async function getNasaApiKey(): Promise<string> {
  if (cachedApiKey) return cachedApiKey;
  const resp = await secretsManager.send(
    new GetSecretValueCommand({ SecretId: NASA_API_KEY_SECRET_ARN })
  );
  cachedApiKey = resp.SecretString!;
  return cachedApiKey;
}

function montarChaveS3(lat: number, lon: number): string {
  const latArredondada = lat.toFixed(2);
  const lonArredondada = lon.toFixed(2);
  return `earth_imagery/${latArredondada}_${lonArredondada}.jpg`;
}

async function jaExisteNoS3(key: string): Promise<boolean> {
  try {
    await s3.send(new HeadObjectCommand({ Bucket: IMAGES_BUCKET, Key: key }));
    return true;
  } catch {
    return false; // 404 (nao existe) ou outro erro - trata como "nao existe" e tenta buscar de novo
  }
}

async function gerarUrlAssinada(key: string): Promise<string> {
  const command = new GetObjectCommand({ Bucket: IMAGES_BUCKET, Key: key });
  return getSignedUrl(s3, command, { expiresIn: 3600 }); // 1 hora
}

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const lat = parseFloat(searchParams.get("lat") ?? "");
  const lon = parseFloat(searchParams.get("lon") ?? "");

  if (Number.isNaN(lat) || Number.isNaN(lon)) {
    return NextResponse.json(
      { error: "Parametros 'lat' e 'lon' sao obrigatorios e devem ser numeros." },
      { status: 400 }
    );
  }

  const s3Key = montarChaveS3(lat, lon);

  // 1. Cache hit - nao gasta chamada na API da NASA
  if (await jaExisteNoS3(s3Key)) {
    const url = await gerarUrlAssinada(s3Key);
    return NextResponse.json({ image_url: url, cached: true });
  }

  // 2. Cache miss - busca ao vivo na API da NASA
  try {
    const apiKey = await getNasaApiKey();
    const nasaUrl = `https://api.nasa.gov/planetary/earth/imagery?lat=${lat}&lon=${lon}&api_key=${apiKey}`;

    const nasaResponse = await fetch(nasaUrl);
    if (!nasaResponse.ok) {
      // Causa comum: nao ha imagem de satelite disponivel pra essa
      // coordenada especifica (cobertura do Landsat nao e global/continua).
      return NextResponse.json(
        { error: "Nao foi possivel obter uma imagem para essa coordenada." },
        { status: 502 }
      );
    }

    const imageBuffer = Buffer.from(await nasaResponse.arrayBuffer());

    await s3.send(
      new PutObjectCommand({
        Bucket: IMAGES_BUCKET,
        Key: s3Key,
        Body: imageBuffer,
        ContentType: "image/jpeg",
      })
    );

    await dynamo.send(
      new PutCommand({
        TableName: HISTORY_TABLE,
        Item: {
          api_name: "earth_imagery",
          fetched_at: new Date().toISOString(),
          lat,
          lon,
          image_s3_key: s3Key,
        },
      })
    );

    const url = await gerarUrlAssinada(s3Key);
    return NextResponse.json({ image_url: url, cached: false });
  } catch (error) {
    console.error("Erro no Earth Imagery:", error);
    return NextResponse.json(
      { error: "Falha ao buscar a imagem da NASA." },
      { status: 500 }
    );
  }
}