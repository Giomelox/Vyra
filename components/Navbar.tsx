import Link from "next/link";
import { NASA_APIS } from "@/lib/nasaApis";

export default function Navbar() {
  return (
    <header className="border-b border-white/10 bg-space-900/80 backdrop-blur sticky top-0 z-10">
      <nav className="max-w-6xl mx-auto px-4 py-3 flex items-center gap-6 overflow-x-auto">
        <Link href="/" className="font-semibold text-lg whitespace-nowrap">
          Vyra
        </Link>
        {NASA_APIS.map((api) => (
          <Link
            key={api.slug}
            href={`/${api.slug}`}
            className="text-sm text-white/70 hover:text-white whitespace-nowrap"
          >
            {api.title}
          </Link>
        ))}
        <Link
          href="/earth-imagery"
          className="text-sm text-white/70 hover:text-white whitespace-nowrap"
        >
          Earth Imagery
        </Link>
      </nav>
    </header>
  );
}