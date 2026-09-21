import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // As imagens vêm de URLs assinadas do S3 (domínio dinâmico por região/conta),
  // então desabilitamos a otimização automática de imagem do Next em vez de
  // listar domínios manualmente - mais simples de manter.
  images: {
    unoptimized: true,
  },
};

export default nextConfig;