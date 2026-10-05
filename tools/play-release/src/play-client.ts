// RED stub — signatures only, behaviour arrives in the green commit.

import type { FetchFn } from "./auth";
import type { Track, TrackBody } from "./plan";

export class PlayApiError extends Error {
  readonly status: number;
  constructor(message: string, status: number) {
    super(message);
    this.name = "PlayApiError";
    this.status = status;
  }
}

/** The Play Developer API calls the release flow needs, one method each. */
export interface PlayApi {
  insertEdit(): Promise<string>;
  getTrack(editId: string, track: string): Promise<Track | undefined>;
  listListingLanguages(editId: string): Promise<string[]>;
  updateTrack(editId: string, body: TrackBody): Promise<void>;
  validate(editId: string): Promise<void>;
  commit(editId: string): Promise<void>;
  deleteEdit(editId: string): Promise<void>;
}

export class PlayClient implements PlayApi {
  constructor(
    _fetchFn: FetchFn,
    _accessToken: string,
    _packageName: string,
  ) {}

  insertEdit(): Promise<string> {
    throw new Error("not implemented");
  }
  getTrack(_editId: string, _track: string): Promise<Track | undefined> {
    throw new Error("not implemented");
  }
  listListingLanguages(_editId: string): Promise<string[]> {
    throw new Error("not implemented");
  }
  updateTrack(_editId: string, _body: TrackBody): Promise<void> {
    throw new Error("not implemented");
  }
  validate(_editId: string): Promise<void> {
    throw new Error("not implemented");
  }
  commit(_editId: string): Promise<void> {
    throw new Error("not implemented");
  }
  deleteEdit(_editId: string): Promise<void> {
    throw new Error("not implemented");
  }
}
