import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://gzimbron.github.io",
  base: "/manita",
  i18n: {
    defaultLocale: "en",
    locales: ["en", "es"],
    routing: { prefixDefaultLocale: false },
  },
});
