/** An error carrying an HTTP status and a stable machine-readable code. */
export class ApiError extends Error {
  constructor(status, code, message, details) {
    super(message || code);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

export const badRequest = (code, msg, details) => new ApiError(400, code, msg, details);
export const unauthorized = (code = 'unauthorized', msg) => new ApiError(401, code, msg);
export const forbidden = (code = 'forbidden', msg) => new ApiError(403, code, msg);
export const notFound = (code = 'not_found', msg) => new ApiError(404, code, msg);
export const conflict = (code, msg) => new ApiError(409, code, msg);

/** Wraps an async route handler so rejections reach the error middleware. */
export const asyncHandler = (fn) => (req, res, next) =>
  Promise.resolve(fn(req, res, next)).catch(next);
