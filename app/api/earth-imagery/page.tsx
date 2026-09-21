"use client";

import { useState, FormEvent } from "react";

export default function EarthImageryPage() {
  const [lat, setLat] = useState("");
  const [lon, setLon] = useState("");
  const [imageUrl, setImageUrl] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(false);

  async function buscarImagem(event: FormEvent) {
    event.preventDefault();
    setErro(null);
    setImageUrl(null);
    setCarregando(true);

    try {
      const resposta = await fetch(
        `/api/earth-imagery?lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lon)}`
      );
      const dados = await resposta.json();

      if (!resposta.ok) {
        setErro(dados.error ?? "Não foi possível buscar a imagem.");
        return;
      }

      setImageUrl(dados.image_url);
    } catch {
      setErro("Falha de conexão ao buscar a imagem.");
    } finally {
      setCarregando(false);
    }
  }

  return (
    <div>
      <h1 className="text-2xl font-bold mb-1">Earth Imagery</h1>
      <p className="text-white/60 mb-6">
        Informe uma coordenada e veja a imagem de satélite mais recente
        disponível para esse ponto.
      </p>

      <form onSubmit={buscarImagem} className="flex flex-wrap gap-3 mb-6">
        <input
          type="number"
          step="any"
          placeholder="Latitude"
          value={lat}
          onChange={(e) => setLat(e.target.value)}
          required
          className="bg-space-800 border border-white/10 rounded-lg px-3 py-2 w-40"
        />
        <input
          type="number"
          step="any"
          placeholder="Longitude"
          value={lon}
          onChange={(e) => setLon(e.target.value)}
          required
          className="bg-space-800 border border-white/10 rounded-lg px-3 py-2 w-40"
        />
        <button
          type="submit"
          disabled={carregando}
          className="rounded-lg bg-white text-space-950 px-4 py-2 font-medium disabled:opacity-50"
        >
          {carregando ? "Buscando..." : "Buscar imagem"}
        </button>
      </form>

      {erro && (
        <p className="text-red-400 mb-6">
          {erro} — cobertura de satélite não é global nem contínua, então
          algumas coordenadas podem não ter imagem disponível.
        </p>
      )}

      {imageUrl && (
        <div className="rounded-xl overflow-hidden border border-white/10 bg-space-800">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={imageUrl} alt={`Imagem de satélite: ${lat}, ${lon}`} className="w-full h-auto" />
        </div>
      )}
    </div>
  );
}