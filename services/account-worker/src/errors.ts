export class AppError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly publicMessage: string,
  ) {
    super(code);
    this.name = "AppError";
  }
}

export function badRequest(code: string, message: string): AppError {
  return new AppError(400, code, message);
}

export function unauthorized(): AppError {
  return new AppError(401, "unauthorized", "Authentication is required.");
}

export function authenticationFailed(): AppError {
  return new AppError(401, "authentication_failed", "Authentication failed.");
}
