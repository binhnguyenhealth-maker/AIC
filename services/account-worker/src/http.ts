import { AppError, badRequest, unauthorized } from "./errors";

const MAX_BODY_BYTES = 16 * 1024;

const RESPONSE_HEADERS: Record<string, string> = {
  "Cache-Control": "no-store, max-age=0",
  "Content-Type": "application/json; charset=utf-8",
  "Pragma": "no-cache",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: RESPONSE_HEADERS });
}

export function emptyResponse(status = 204): Response {
  const headers = new Headers(RESPONSE_HEADERS);
  headers.delete("Content-Type");
  return new Response(null, { status, headers });
}

export async function readJsonObject(request: Request): Promise<Record<string, unknown>> {
  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  if (!/^application\/json(?:\s*;|$)/u.test(contentType)) {
    throw new AppError(415, "unsupported_media_type", "Content-Type must be application/json.");
  }

  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    await request.body?.cancel("request body exceeds limit");
    throw new AppError(413, "request_too_large", "Request body is too large.");
  }

  const reader = request.body?.getReader();
  if (!reader) throw badRequest("invalid_json", "Request body must be valid JSON.");
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    totalBytes += value.byteLength;
    if (totalBytes > MAX_BODY_BYTES) {
      await reader.cancel("request body exceeds limit");
      throw new AppError(413, "request_too_large", "Request body is too large.");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw badRequest("invalid_json", "Request body must be valid UTF-8 JSON.");
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text) as unknown;
  } catch {
    throw badRequest("invalid_json", "Request body must be valid JSON.");
  }

  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw badRequest("invalid_json", "Request body must be a JSON object.");
  }
  return parsed as Record<string, unknown>;
}

export function requireString(
  body: Record<string, unknown>,
  field: string,
  options: { min: number; max: number },
): string {
  const value = body[field];
  if (typeof value !== "string" || value.length < options.min || value.length > options.max) {
    throw badRequest("invalid_request", `${field} is invalid.`);
  }
  return value;
}

export function optionalString(
  body: Record<string, unknown>,
  field: string,
  max: number,
): string | undefined {
  const value = body[field];
  if (value === undefined) return undefined;
  if (typeof value !== "string" || value.length > max) {
    throw badRequest("invalid_request", `${field} is invalid.`);
  }
  return value;
}

export function rejectUnknownFields(body: Record<string, unknown>, allowed: readonly string[]): void {
  const allowedSet = new Set(allowed);
  if (Object.keys(body).some((field) => !allowedSet.has(field))) {
    throw badRequest("invalid_request", "Request contains unsupported fields.");
  }
}

export function bearerToken(request: Request): string {
  const authorization = request.headers.get("authorization");
  if (!authorization) throw unauthorized();
  const match = /^Bearer ([A-Za-z0-9._~-]+)$/u.exec(authorization);
  if (!match?.[1]) throw unauthorized();
  return match[1];
}
