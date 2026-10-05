/** A scriptable stand-in for global `fetch`, recording every call. Shared by the client and runner tests. */

export interface RecordedCall {
  method: string;
  /** Full URL as sent. */
  url: string;
  /** Path + query exactly as sent, e.g. `/v1/builds?filter%5Bapp%5D=1`. */
  pathAndQuery: string;
  /** Decoded query parameters. */
  query: Record<string, string>;
  headers: Record<string, string>;
  body: unknown;
  /** `init.redirect` as passed to fetch. */
  redirect: RequestInit["redirect"];
}

export interface StubResponse {
  status?: number;
  /** JSON-serialised unless it is a string; `undefined` => empty body. */
  body?: unknown;
  headers?: Record<string, string>;
}

export type Route = (call: RecordedCall) => StubResponse | undefined;

export function createStubFetch(routes: Route[] = []): {
  fetch: typeof fetch;
  calls: RecordedCall[];
  /** `METHOD /path` (no query) per call, in order. */
  sequence(): string[];
} {
  const calls: RecordedCall[] = [];
  const stub = (async (input: Parameters<typeof fetch>[0], init?: RequestInit): Promise<Response> => {
    const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
    const query: Record<string, string> = {};
    url.searchParams.forEach((v, k) => {
      query[k] = v;
    });
    const headers: Record<string, string> = {};
    new Headers(init?.headers).forEach((v, k) => {
      headers[k.toLowerCase()] = v;
    });
    const rawBody = init?.body;
    const call: RecordedCall = {
      method: (init?.method ?? "GET").toUpperCase(),
      url: url.href,
      pathAndQuery: url.pathname + url.search,
      query,
      headers,
      body: typeof rawBody === "string" ? JSON.parse(rawBody) : undefined,
      redirect: init?.redirect,
    };
    calls.push(call);
    for (const route of routes) {
      const res = route(call);
      if (res) {
        const status = res.status ?? 200;
        const text = res.body === undefined ? "" : typeof res.body === "string" ? res.body : JSON.stringify(res.body);
        return new Response(status === 204 ? null : text, {
          status,
          headers: { "content-type": "application/vnd.api+json", ...(res.headers ?? {}) },
        });
      }
    }
    throw new Error(`stub fetch: no route for ${call.method} ${call.pathAndQuery}`);
  }) as typeof fetch;
  return {
    fetch: stub,
    calls,
    sequence: () => calls.map((c) => `${c.method} ${new URL(c.url).pathname}`),
  };
}

/** Route helper: match method + exact path (query ignored). */
export function on(method: string, path: string, res: StubResponse | ((c: RecordedCall) => StubResponse)): Route {
  return (call) => {
    if (call.method !== method.toUpperCase()) return undefined;
    if (new URL(call.url).pathname !== path) return undefined;
    return typeof res === "function" ? res(call) : res;
  };
}
