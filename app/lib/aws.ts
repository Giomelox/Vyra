import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand } from "@aws-sdk/lib-dynamodb";

const REGION = process.env.AWS_REGION!;

export const s3 = new S3Client({ region: REGION });
export const dynamo = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));

export async function presignedImageUrl(bucket: string, key: string): Promise<string | null> {
  if (!key) return null;
  try {
    const command = new GetObjectCommand({ Bucket: bucket, Key: key });
    return await getSignedUrl(s3, command, { expiresIn: 3600 });
  } catch {
    // Objeto pode nao existir ainda (ex: primeira execucao da Lambda
    // falhou ao baixar a imagem) - a pagina trata isso mostrando "sem imagem".
    return null;
  }
}

export async function getCachedApiItem(tableName: string, apiName: string) {
  const result = await dynamo.send(
    new GetCommand({ TableName: tableName, Key: { api_name: apiName } })
  );
  return result.Item ?? null;
}