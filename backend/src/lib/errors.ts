export class AppError extends Error {
  public readonly code: string;
  public readonly statusCode: number;
  public readonly details?: Record<string, any>;

  constructor(code: string, message: string, statusCode = 400, details?: Record<string, any>) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.statusCode = statusCode;
    this.details = details;
  }
}

export class ValidationError extends AppError {
  constructor(message: string, details?: Record<string, any>) {
    super('VALIDATION_ERROR', message, 400, details);
  }
}

export class UnauthenticatedError extends AppError {
  constructor(message = 'Authentication required') {
    super('UNAUTHENTICATED', message, 401);
  }
}

export class ForbiddenError extends AppError {
  constructor(message = 'Access forbidden') {
    super('FORBIDDEN', message, 403);
  }
}

export class NotFoundError extends AppError {
  constructor(message = 'Resource not found') {
    super('NOT_FOUND', message, 404);
  }
}

export class ConflictError extends AppError {
  constructor(message = 'Conflict detected') {
    super('CONFLICT', message, 409);
  }
}

export class SettlementOutdatedError extends AppError {
  constructor(message = 'Amount is no longer valid') {
    super('SETTLEMENT_OUTDATED', message, 409);
  }
}

export class UnsettledBalanceError extends AppError {
  constructor(message = 'Cannot leave or remove member with unsettled balance') {
    super('UNSETTLED_BALANCE', message, 400);
  }
}

export class NothingDueError extends AppError {
  constructor(message = 'No amount due anymore') {
    super('NOTHING_DUE', message, 400);
  }
}

