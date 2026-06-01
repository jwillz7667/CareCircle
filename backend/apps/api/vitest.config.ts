import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    globals: false,
    globalSetup: ['./test/helpers/globalSetup.ts'],
    hookTimeout: 30_000,
    testTimeout: 30_000,
    pool: 'forks',
    poolOptions: {
      forks: {
        singleFork: true,
      },
    },
    fileParallelism: false,
  },
});
