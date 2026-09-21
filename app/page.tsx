import { notFound } from "next/navigation";
import { getApiConfig } from "@/lib/nasaApis";
import { getCachedApiItem, presignedImageUrl } from "@/lib/aws";

// Os dados vem do DynamoDB (atualizado pela Lambda de ingestao em background),
// entao cada visita deve ler o valor mais recente - sem cache estatico do Next.
export const dynamic = "force-dynamic";

const API_DATA_TABLE = process.env.API_DATA_TABLE!;
const IMAGES_BUCKET = process.env.IMAGES_BUCKET!;

export function generateStaticParams() {
  // Gera as rotas conhecidas em build time (URLs ficam definidas de antemao);
  // o CONTEUDO de cada uma ainda e buscado dinamicamente por causa do
  // `dynamic = "force-dynamic"` acima.
  return [
    { apiSlug: "apod" },
    { apiSlug: "neows" },
    { apiSlug: "donki" },
    { apiSlug: "epic" },
    { apiSlug: "eonet" },
    { apiSlug: "mars_rover_photos" },
    { apiSlug: "exoplanet_archive" },
    { apiSlug: "ssd_cneos" },
    { apiSlug: "techport" },
  ];
}

export default async function ApiPage({
  params,
}: {
  params: Promise<{ apiSlug: string }>;
}) {
  const { apiSlug } = await params;
  const config = getApiConfig(apiSlug);
  if (!config) {
    notFound();
  }

  const item = await getCachedApiItem(API_DATA_TABLE, apiSlug);

  if (!item) {
    return (
      <div>
        <h1 className="text-2xl font-bold mb-4">{config.title}</h1>
        <p className="text-white/60">
          Ainda não há dados ingeridos para essa API. A primeira execução
          agendada ainda não rodou.
        </p>
      </div>
    );
  }

  const imageUrl = config.hasImage
    ? await presignedImageUrl(IMAGES_BUCKET, item.image_s3_key)
    : null;

  let dadosFormatados: unknown;
  try {
    dadosFormatados = JSON.parse(item.data);
  } catch {
    dadosFormatados = item.data;
  }

  return (
    <div>
      <h1 className="text-2xl font-bold mb-1">{config.title}</h1>
      <p className="text-white/60 mb-6">{config.description}</p>
      <p className="text-xs text-white/40 mb-6">
        Atualizado em: {item.updated_at}
      </p>

      {config.hasImage && (
        <div className="mb-6 rounded-xl overflow-hidden border border-white/10 bg-space-800">
          {imageUrl ? (
            // Imagem vem de uma URL assinada do S3 (dominio dinamico por
            // conta/regiao) - por isso next/image esta com unoptimized
            // no next.config.ts em vez de listar o dominio manualmente.
            // eslint-disable-next-line @next/next/no-img-element
            <img src={imageUrl} alt={config.title} className="w-full h-auto" />
          ) : (
            <div className="p-8 text-center text-white/40">
              Imagem ainda não disponível.
            </div>
          )}
        </div>
      )}

      <pre className="rounded-xl border border-white/10 bg-space-800 p-4 text-xs overflow-x-auto">
        {JSON.stringify(dadosFormatados, null, 2)}
      </pre>
    </div>
  );
}