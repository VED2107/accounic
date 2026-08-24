import { defineConfig } from 'vitest/config';
import { fileURLToPath } from 'node:url';

/**
 * Vitest needs the same `@/…` alias tsconfig gives the app.
 *
 * Without it the money suite cannot import the currency list, and the two
 * halves of the money path — how many minor units a currency has, and how they
 * are parsed and formatted — would be untestable together, which is exactly the
 * pair that must not drift.
 */
export default defineConfig({
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  test: {
    include: ['src/**/*.test.ts'],
  },
});
