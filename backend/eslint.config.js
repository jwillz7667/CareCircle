import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import globals from 'globals';

export default tseslint.config(
  {
    ignores: ['**/dist/**', '**/node_modules/**', '**/*.d.ts', '**/coverage/**'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.ts'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'module',
      globals: { ...globals.node },
    },
    rules: {
      // Console output belongs in CLI/bootstrap surfaces only; everything else
      // logs through pino. Bootstrap files opt back in with an inline disable.
      'no-console': 'error',
      // `noUncheckedIndexedAccess` forces `rows[0]!` after a checked query; the
      // non-null assertion is the intended idiom there, so allow it.
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' },
      ],
    },
  },
  {
    // Migration/seed CLIs and the wait-for-db script print directly to stdout.
    files: ['apps/migrator/**/*.ts', 'scripts/**/*.mjs'],
    rules: { 'no-console': 'off' },
  },
  {
    files: ['**/*.config.{js,mjs,ts}', 'scripts/**/*.mjs'],
    languageOptions: { globals: { ...globals.node } },
  },
);
