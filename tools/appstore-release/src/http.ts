/**
 * Thin App Store Connect HTTP client (built-in fetch only).
 *
 * Two safety properties are enforced here, not left to callers:
 *  - DRY_RUN => GET only. Any other verb throws {@link DryRunViolationError} before the network is touched.
 *  - The bearer token is only ever sent to the App Store Connect origin: pagination links on another
 *    host are refused, and neither the token nor request headers appear in any error message.
 */

export const ASC_BASE_URL = "https://api.appstoreconnect.apple.com";
const MAX_PAGES = 10;
const DEFAULT_TIMEOUT_MS = 30_000;

export interface JsonApiResource {
  id: string;
  type: string;
  attributes?: Record<string, unknown>;
  relationships?: Record<string, { data?: unknown; links?: unknown } | undefined>;
}

export interface JsonApiDoc<T = JsonApiResource> {
  data: T;
  included?: JsonApiResource[];
  links?: { next?: string; self?: string };
}

export interface AscErrorItem {
  status?: string;
  code?: string;
  title?: string;
  detail?: string;
}

export class AscApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly errors: AscErrorItem[],
  ) {
    super(message);
    this.name = "AscApiError";
  }
}

export class DryRunViolationError extends Error {
  constructor(method: string, path: string) {
    super(`DRY_RUN is on: refusing ${method.toUpperCase()} ${path} (dry runs may only send GET requests).`);
    this.name = "DryRunViolationError";
  }
}

export interface AscClientOptions {
  token: () => string;
  dryRun: boolean;
  fetch?: typeof fetch;
  baseUrl?: string;
  timeoutMs?: number;
}

export type Query = Record<string, string>;

export class AscClient {
  private readonly doFetch: typeof fetch;
  private readonly baseUrl: string;

  constructor(private readonly opts: AscClientOptions) {
    this.doFetch = opts.fetch ?? fetch;
    this.baseUrl = opts.baseUrl ?? ASC_BASE_URL;
  }

  get dryRun(): boolean {
    return this.opts.dryRun;
  }

  async get<T = JsonApiDoc>(path: string, query?: Query): Promise<T> {
    return (await this.request("GET", path, { query })) as T;
  }

  /** GET that maps 404 to `null` (an absent optional relationship). Other errors still throw. */
  async getOptional<T = JsonApiDoc>(path: string, query?: Query): Promise<T | null> {
    try {
      return await this.get<T>(path, query);
    } catch (e) {
      if (e instanceof AscApiError && e.status === 404) return null;
      throw e;
    }
  }

  /** GET a collection, following `links.next` (same origin only) up to a bounded number of pages. */
  async getAll<T = JsonApiResource>(path: string, query?: Query): Promise<{ data: T[]; included: JsonApiResource[] }> {
    const data: T[] = [];
    const included: JsonApiResource[] = [];
    let page = await this.get<JsonApiDoc<T[]>>(path, query);
    for (let n = 1; ; n++) {
      data.push(...(page.data ?? []));
      included.push(...(page.included ?? []));
      const next = page.links?.next;
      if (!next) break;
      if (n >= MAX_PAGES) throw new Error(`GET ${path}: more than ${MAX_PAGES} pages of results, refusing to continue.`);
      const url = new URL(next);
      if (url.origin !== new URL(this.baseUrl).origin) {
        throw new Error(`GET ${path}: pagination link points at an unexpected host; refusing to send credentials there.`);
      }
      page = (await this.requestUrl("GET", url, path, undefined)) as JsonApiDoc<T[]>;
    }
    return { data, included };
  }

  post<T = JsonApiDoc>(path: string, body: unknown): Promise<T> {
    return this.request("POST", path, { body }) as Promise<T>;
  }

  patch<T = JsonApiDoc | undefined>(path: string, body: unknown): Promise<T> {
    return this.request("PATCH", path, { body }) as Promise<T>;
  }

  delete(path: string): Promise<undefined> {
    return this.request("DELETE", path) as Promise<undefined>;
  }

  async request(method: string, path: string, opts: { query?: Query; body?: unknown } = {}): Promise<unknown> {
    if (method.toUpperCase() !== "GET" && this.opts.dryRun) throw new DryRunViolationError(method, path);
    const url = new URL(path, this.baseUrl);
    for (const [k, v] of Object.entries(opts.query ?? {})) url.searchParams.set(k, v);
    return this.requestUrl(method, url, path, opts.body);
  }

  private async requestUrl(method: string, url: URL, label: string, body: unknown): Promise<unknown> {
    const verb = method.toUpperCase();
    if (verb !== "GET" && this.opts.dryRun) throw new DryRunViolationError(verb, label);
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.opts.token()}`,
      Accept: "application/json",
    };
    const init: RequestInit = { method: verb, headers, signal: AbortSignal.timeout(this.opts.timeoutMs ?? DEFAULT_TIMEOUT_MS) };
    if (body !== undefined) {
      headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(body);
    }

    let res: Response;
    try {
      res = await this.doFetch(url, init);
    } catch (e) {
      // Only the error's name/code: its message can quote request headers.
      const err = e as { name?: string; cause?: { code?: string } };
      throw new Error(`${verb} ${label} failed: network error (${err.cause?.code ?? err.name ?? "unknown"}).`);
    }

    const text = await res.text();
    let parsed: unknown;
    if (text !== "") {
      try {
        parsed = JSON.parse(text);
      } catch {
        parsed = undefined;
      }
    }

    if (!res.ok) {
      const errors = extractErrors(parsed);
      const details = errors.map((e) => e.detail ?? e.title ?? e.code).filter((d): d is string => !!d);
      throw new AscApiError(
        `${verb} ${label} failed: HTTP ${res.status}: ${details.length > 0 ? details.join(" | ") : "no error details in the response"}`,
        res.status,
        errors,
      );
    }
    if (text !== "" && parsed === undefined) {
      throw new Error(`${verb} ${label}: HTTP ${res.status} with a response that is not valid JSON.`);
    }
    return parsed;
  }
}

function extractErrors(parsed: unknown): AscErrorItem[] {
  const errors = (parsed as { errors?: unknown } | undefined)?.errors;
  if (!Array.isArray(errors)) return [];
  return errors
    .filter((e): e is Record<string, unknown> => typeof e === "object" && e !== null)
    .map((e) => ({
      status: typeof e.status === "string" ? e.status : undefined,
      code: typeof e.code === "string" ? e.code : undefined,
      title: typeof e.title === "string" ? e.title : undefined,
      detail: typeof e.detail === "string" ? e.detail : undefined,
    }));
}
