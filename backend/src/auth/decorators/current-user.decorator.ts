import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export const CurrentUser = createParamDecorator(
  (data: string | undefined, ctx: ExecutionContext) => {
    const user = ctx.switchToHttp().getRequest().user;
    if (!data) return user;

    // JWT payloads use `sub` as the canonical user identifier. Controllers
    // historically request `@CurrentUser('id')`, so preserve that ergonomic
    // alias without ever returning the entire request user where a scalar
    // tenant/user id is required.
    if (data === 'id') return user?.id ?? user?.sub;
    return user?.[data];
  },
);
