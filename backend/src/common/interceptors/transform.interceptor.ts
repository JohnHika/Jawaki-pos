import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable, throwError } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { NotFoundException } from '@nestjs/common';

/**
 * TransformInterceptor - Transforms errors to consistent responses
 * Ensures authenticated endpoints return 401 instead of 404 when unauthorized
 */
@Injectable()
export class TransformInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      catchError((error) => {
        // If it's a 404 error and we have a valid JWT token but no route match,
        // we should return 401 instead to indicate authentication is required
        if (error instanceof NotFoundException) {
          // Check if the request has an authorization header
          const request = context.switchToHttp().getRequest();
          const authHeader = request.headers.authorization;

          if (authHeader && authHeader.startsWith('Bearer ')) {
            // Return 401 for authenticated requests with non-existent routes
            return throwError(() => ({
              statusCode: 401,
              message: 'Unauthorized',
              error: 'Unauthorized',
            }));
          }
        }

        // For all other errors, throw as-is
        return throwError(() => error);
      }),
    );
  }
}
