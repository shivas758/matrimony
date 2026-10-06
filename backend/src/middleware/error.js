import { ApiError } from '../lib/errors.js';

export function notFoundHandler(req, res) {
  res.status(404).json({ error: 'not_found', message: `No route for ${req.method} ${req.path}` });
}

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, _req, res, _next) {
  if (err instanceof ApiError) {
    return res.status(err.status).json({
      error: err.code,
      message: err.message,
      ...(err.details ? { details: err.details } : {}),
    });
  }
  // multer file-size / count violations
  if (err && err.code === 'LIMIT_FILE_SIZE') {
    return res.status(400).json({ error: 'file_too_large', message: 'Each photo must be under 10 MB' });
  }
  if (err && err.code === 'LIMIT_FILE_COUNT') {
    return res.status(400).json({ error: 'too_many_files', message: 'Too many photos in one request' });
  }
  // A file part under any name other than the one the route expects (SPEC §3 / §9.9: `photos`).
  if (err && err.code === 'LIMIT_UNEXPECTED_FILE') {
    return res.status(400).json({ error: 'unexpected_file', message: 'Send photos in the "photos" field' });
  }
  // Any other multer limit (parts, fields, field size) is the client's request, not a server fault.
  if (err && err.name === 'MulterError') {
    return res.status(400).json({ error: 'upload_error', message: err.message });
  }
  if (err && err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'invalid_json', message: 'Request body is not valid JSON' });
  }
  console.error('[unhandled]', err);
  res.status(500).json({ error: 'server_error', message: 'Something went wrong' });
}
