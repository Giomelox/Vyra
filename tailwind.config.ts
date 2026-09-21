import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        space: {
          950: "#05060f",
          900: "#0b0e1a",
          800: "#131829",
        },
      },
    },
  },
  plugins: [],
};

export default config;