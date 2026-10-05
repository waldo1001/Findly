// RED stub — signatures only, behaviour arrives in the green commit.

export const PLAY_SCOPE = "https://www.googleapis.com/auth/androidpublisher";

export type FetchFn = (url: string, init?: RequestInit) => Promise<Response>;

export interface ServiceAccount {
  clientEmail: string;
  privateKey: string;
  tokenUri: string;
}

export function parseServiceAccount(_json: string | undefined): ServiceAccount {
  throw new Error("not implemented");
}

export function buildJwt(_sa: ServiceAccount, _nowSeconds: number): string {
  throw new Error("not implemented");
}

export async function fetchAccessToken(_fetchFn: FetchFn, _sa: ServiceAccount, _nowSeconds: number): Promise<string> {
  throw new Error("not implemented");
}
