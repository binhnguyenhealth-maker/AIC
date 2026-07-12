import { encryptAppleToken } from "./crypto";

export interface PreparedAppleRevocation {
  id: string;
  ciphertext: string;
  nonce: string;
  createdAt: number;
  nextAttemptAt: number;
}

export async function prepareAppleRevocation(
  refreshToken: string,
  encryptionKey: string,
  now: number,
): Promise<PreparedAppleRevocation> {
  const id = crypto.randomUUID();
  const encrypted = await encryptAppleToken(refreshToken, encryptionKey, id);
  const jitter = 60 + (crypto.getRandomValues(new Uint16Array(1))[0] ?? 0) % 241;
  return {
    id,
    ciphertext: encrypted.ciphertext,
    nonce: encrypted.nonce,
    createdAt: Math.floor((now - 1) / 3600) * 3600,
    nextAttemptAt: now + jitter,
  };
}
