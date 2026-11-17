import { en, type Dict } from "./en";
import { es } from "./es";

export type Locale = "en" | "es";
export const locales: Locale[] = ["en", "es"];
export const dictionaries: Record<Locale, Dict> = { en, es };
export const getDict = (locale: Locale): Dict => dictionaries[locale];
// Path (under the site base, no leading slash) of a locale's home page.
export const localePath = (locale: Locale) => (locale === "en" ? "" : `${locale}/`);
