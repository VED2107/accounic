import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { FlatCompat } from '@eslint/eslintrc';

/**
 * ESLint flat config (v1.11.0).
 *
 * `npm run lint` had been broken for the life of this project: the script ran
 * `next lint`, which Next 15 deprecates and Next 16 removes, and there was no
 * ESLint configuration for it to find either way. Every lint invocation ended
 * in a prompt or an error, so nothing was ever linted — typecheck and the test
 * suite were doing all the work, and neither of them catches an unused import
 * or a hook dependency that is quietly wrong.
 *
 * `eslint-config-next` still ships as eslintrc-style shareable configs, so
 * FlatCompat is what bridges them into flat config. That is the documented
 * migration path, not a workaround.
 *
 * The rule set is deliberately the Next defaults plus nothing. A lint config
 * that disagrees with the framework's own is a config people learn to ignore.
 */
const compat = new FlatCompat({
  baseDirectory: dirname(fileURLToPath(import.meta.url)),
});

const config = [
  {
    ignores: ['.next/**', 'node_modules/**', 'next-env.d.ts', 'public/**'],
  },
  ...compat.extends('next/core-web-vitals', 'next/typescript'),
  {
    rules: {
      // The codebase uses `_`-prefixed names for deliberately unused bindings
      // (a caught error nobody reads, a positional argument that has to be
      // there). Without this the convention itself is a lint error.
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
        },
      ],
    },
  },
];

export default config;
