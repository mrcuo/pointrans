interface CounterRequest {
  limit: number;
}

interface CounterResponse {
  allowed: boolean;
  count: number;
  remaining: number;
}

export class AtomicCounter {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

    if (url.pathname === "/refund") {
      const count = await this.state.storage.transaction(async (transaction) => {
        const current = (await transaction.get<number>("count")) ?? 0;
        const next = Math.max(0, current - 1);
        await transaction.put("count", next);
        return next;
      });
      return Response.json({ count });
    }

    if (url.pathname !== "/consume") return new Response("Not Found", { status: 404 });
    const body = (await request.json()) as CounterRequest;
    if (!Number.isInteger(body.limit) || body.limit < 1 || body.limit > 10_000) {
      return new Response("Bad Request", { status: 400 });
    }

    const result = await this.state.storage.transaction<CounterResponse>(async (transaction) => {
      const current = (await transaction.get<number>("count")) ?? 0;
      if (current >= body.limit) {
        return { allowed: false, count: current, remaining: 0 };
      }
      const next = current + 1;
      await transaction.put("count", next);
      return { allowed: true, count: next, remaining: body.limit - next };
    });
    return Response.json(result);
  }
}
