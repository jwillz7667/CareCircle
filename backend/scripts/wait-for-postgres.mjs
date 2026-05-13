#!/usr/bin/env node
import net from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';

const host = process.env.POSTGRES_HOST ?? 'localhost';
const port = Number(process.env.POSTGRES_PORT ?? 5433);
const deadline = Date.now() + 60_000;

async function check() {
  return new Promise((resolve) => {
    const socket = net.createConnection({ host, port });
    socket.once('connect', () => {
      socket.end();
      resolve(true);
    });
    socket.once('error', () => resolve(false));
    socket.setTimeout(1500, () => {
      socket.destroy();
      resolve(false);
    });
  });
}

while (Date.now() < deadline) {
  if (await check()) {
    console.log(`Postgres ready at ${host}:${port}`);
    process.exit(0);
  }
  await delay(1000);
}

console.error(`Timed out waiting for Postgres at ${host}:${port}`);
process.exit(1);
