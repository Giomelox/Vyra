export type NasaApiConfig = {
  slug: string; // bate com o "api_name" gravado pelas Lambdas de ingestao
  title: string;
  description: string;
  hasImage: boolean;
};

// Fonte da verdade da lista de APIs no front-end. As chaves (slug) precisam
// bater com as chaves de var.nasa_apis no Terraform (variables.tf) e com o
// API_NAME de cada handler Python - e o que conecta as tres pontas.
export const NASA_APIS: NasaApiConfig[] = [
  {
    slug: "apod",
    title: "Foto Astronômica do Dia",
    description: "A imagem ou vídeo astronômico do dia, com explicação da NASA.",
    hasImage: true,
  },
  {
    slug: "neows",
    title: "Asteroides Próximos (NeoWs)",
    description: "Asteroides que passam perto da Terra hoje: tamanho, velocidade e distância.",
    hasImage: false,
  },
  {
    slug: "donki",
    title: "Clima Espacial (DONKI)",
    description: "Ejeções de massa coronal, tempestades geomagnéticas e erupções solares recentes.",
    hasImage: false,
  },
  {
    slug: "epic",
    title: "Imagem da Terra (EPIC)",
    description: "Imagem quase em tempo real do disco cheio da Terra, vista do espaço.",
    hasImage: true,
  },
  {
    slug: "eonet",
    title: "Eventos Naturais (EONET)",
    description: "Incêndios, furacões e erupções vulcânicas acontecendo agora.",
    hasImage: false,
  },
  {
    slug: "mars_rover_photos",
    title: "Fotos dos Rovers em Marte",
    description: "As fotos mais recentes enviadas pelo rover Curiosity.",
    hasImage: true,
  },
  {
    slug: "exoplanet_archive",
    title: "Catálogo de Exoplanetas",
    description: "Os exoplanetas confirmados mais recentemente descobertos.",
    hasImage: false,
  },
  {
    slug: "ssd_cneos",
    title: "Aproximações de Asteroides (CNEOS)",
    description: "Objetos próximos da Terra e suas próximas aproximações previstas.",
    hasImage: false,
  },
  {
    slug: "techport",
    title: "Projetos de Tecnologia (TechPort)",
    description: "Projetos de pesquisa e desenvolvimento tecnológico da NASA.",
    hasImage: false,
  },
];

export function getApiConfig(slug: string): NasaApiConfig | undefined {
  return NASA_APIS.find((api) => api.slug === slug);
}