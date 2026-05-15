import argon2 from 'argon2';

// OWASP Password Storage Cheat Sheet recommends Argon2id with the
// following minimums for non-FIDO secrets:
//   m = 19 MiB, t = 2, p = 1
// We over-provision (64 MiB / 3 iters / 4 lanes) so a single verify
// takes ~100ms on a modern Railway worker — costly enough to blunt
// offline cracking, cheap enough that simultaneous logins don't queue.
const ARGON2_OPTIONS = Object.freeze({
  type: argon2.argon2id,
  memoryCost: 64 * 1024,
  timeCost: 3,
  parallelism: 4,
});

export type PasswordService = {
  hash(password: string): Promise<string>;
  verify(hash: string | null | undefined, password: string): Promise<boolean>;
};

export function createPasswordService(): PasswordService {
  // Lazy-built sentinel hash so verifying a non-existent account still
  // spends the same CPU as a real verify — denies trivial user
  // enumeration via response-time analysis. Built once per process.
  let dummyHashPromise: Promise<string> | null = null;
  function dummyHash(): Promise<string> {
    dummyHashPromise ??= argon2.hash('cc:enumeration-defense:not-a-real-credential', ARGON2_OPTIONS);
    return dummyHashPromise;
  }

  return {
    async hash(password: string): Promise<string> {
      return await argon2.hash(password, ARGON2_OPTIONS);
    },

    async verify(hash: string | null | undefined, password: string): Promise<boolean> {
      const target = hash ?? (await dummyHash());
      try {
        const ok = await argon2.verify(target, password);
        return Boolean(hash) && ok;
      } catch {
        return false;
      }
    },
  };
}
