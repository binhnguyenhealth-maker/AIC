const encoder = new TextEncoder();

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

function base64ToBytes(value: string): Uint8Array<ArrayBuffer> {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  let binary: string;
  try {
    binary = atob(padded);
  } catch {
    throw new Error("APPLE_TOKEN_ENCRYPTION_KEY must be valid base64");
  }
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

export function requireStrongSecret(name: string, secret: string): Uint8Array<ArrayBuffer> {
  const encoded = encoder.encode(secret);
  const bytes = new Uint8Array(encoded.byteLength);
  bytes.set(encoded);
  if (bytes.byteLength < 32) {
    throw new Error(`${name} must contain at least 32 bytes`);
  }
  return bytes;
}

export function randomToken(byteLength = 32): string {
  const bytes = crypto.getRandomValues(new Uint8Array(byteLength));
  return bytesToBase64Url(bytes);
}

export async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return bytesToBase64Url(new Uint8Array(digest));
}

export async function hmacSha256(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    requireStrongSecret("APPLE_SUBJECT_PEPPER", secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(value));
  return bytesToBase64Url(new Uint8Array(signature));
}

export function constantTimeEqual(left: string, right: string): boolean {
  const length = Math.max(left.length, right.length);
  let difference = left.length ^ right.length;
  for (let index = 0; index < length; index += 1) {
    difference |= (left.charCodeAt(index) || 0) ^ (right.charCodeAt(index) || 0);
  }
  return difference === 0;
}

async function appleEncryptionKey(secret: string): Promise<CryptoKey> {
  const bytes = base64ToBytes(secret);
  if (bytes.byteLength !== 32) {
    throw new Error("APPLE_TOKEN_ENCRYPTION_KEY must decode to exactly 32 bytes");
  }
  return crypto.subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function encryptAppleToken(
  plaintext: string,
  secret: string,
  accountId: string,
): Promise<{ ciphertext: string; nonce: string }> {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce, additionalData: encoder.encode(accountId), tagLength: 128 },
    await appleEncryptionKey(secret),
    encoder.encode(plaintext),
  );
  return {
    ciphertext: bytesToBase64Url(new Uint8Array(encrypted)),
    nonce: bytesToBase64Url(nonce),
  };
}

export async function decryptAppleToken(
  ciphertext: string,
  nonce: string,
  secret: string,
  accountId: string,
): Promise<string> {
  const decrypted = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: base64ToBytes(nonce),
      additionalData: encoder.encode(accountId),
      tagLength: 128,
    },
    await appleEncryptionKey(secret),
    base64ToBytes(ciphertext),
  );
  return new TextDecoder().decode(decrypted);
}
