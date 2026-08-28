/**
 * A no-op stand-in for the `server-only` package, used by the test runner alone.
 *
 * `server-only` exists to make a build fail when a server module is pulled into
 * a client bundle, and it does that by throwing on import outside the
 * react-server condition — which includes Vitest. Aliasing it here lets the PDF
 * builder be tested for real, generating actual bytes with a real embedded
 * font, instead of being the one part of the export nothing ever executes.
 *
 * The guarantee it provides is not weakened: the alias is configured in
 * vitest.config.ts and nowhere else, so `next build` still sees the real
 * package and would still refuse a client import of lib/pdf/*.
 */
export {};
