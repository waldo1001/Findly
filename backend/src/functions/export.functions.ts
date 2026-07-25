// specs/001 §13.1 `GET /api/v1/export` (specs/008 §3). Thin: parse -> authenticate -> domain
// -> response. No business logic here (excluded from mutation) EXCEPT the one thing every
// other endpoint in this codebase does NOT do: build the deliberately unenveloped, attachment
// response (§1.3's one documented envelope exception) instead of calling http/envelope's ok().

import { app, type HttpRequest, type HttpResponseInit, type InvocationContext } from "@azure/functions";
import { randomUUID } from "node:crypto";
import { authenticate } from "../http/authGuard";
import { fail } from "../http/envelope";
import { AppError } from "../http/errors";
import { toSafeErrorLog } from "../http/errorLogging";
import { exportUserData } from "../domain/export/exportUserData";
import { createTokenVerifier } from "../adapters/auth/firebaseJoseVerifier";
import { TableUserRepo } from "../adapters/tables/usersTableRepo";
import { TableFamilyRepo } from "../adapters/tables/familiesTableRepo";
import { TableDeviceRepo } from "../adapters/tables/devicesTableRepo";
import { TableLastKnownRepo } from "../adapters/tables/lastKnownTableRepo";
import { TableGroupRepo } from "../adapters/tables/groupsTableRepo";
import { TableGroupLastKnownRepo } from "../adapters/tables/groupLastKnownTableRepo";
import { TableEntitlementsRepo } from "../adapters/tables/entitlementsTableRepo";
import { TableUsageRepo } from "../adapters/tables/usageTableRepo";
import { BlobHistoryStore } from "../adapters/blobs/historyBlobStore";
import { SystemClock } from "../adapters/support/systemClock";

const tokenVerifier = createTokenVerifier();
const userRepo = new TableUserRepo();
const familyRepo = new TableFamilyRepo();
const deviceRepo = new TableDeviceRepo();
const lastKnownRepo = new TableLastKnownRepo();
const groupRepo = new TableGroupRepo();
const groupLastKnownRepo = new TableGroupLastKnownRepo();
const entitlementsRepo = new TableEntitlementsRepo();
const usageRepo = new TableUsageRepo();
const historyStore = new BlobHistoryStore();
const clock = new SystemClock();

function newRequestId(): string {
  return `r_${randomUUID().replace(/-/g, "").slice(0, 16)}`;
}

function queryToObject(request: HttpRequest): Record<string, string> {
  return Object.fromEntries(request.query.entries());
}

// RFC 2616 quoted-string escaping for the Content-Disposition filename param. `userId` is
// validated (exportQuerySchema) against Table-Storage-unsafe characters but NOT against `"`
// or `\`, so this is defense-in-depth against a crafted value breaking out of the quoted
// filename attribute — never a real concern in practice since `doc.subject.userId` is always
// either the caller's own verified uid or a value that matched an existing family member's
// stored userId (never attacker-supplied free text), but cheap to close off regardless.
function escapeQuotedString(value: string): string {
  return value.replace(/[\\"]/g, (char) => `\\${char}`);
}

app.http("exportUserData", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "v1/export",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), {
        tokenVerifier,
        userRepo,
        usageRepo,
        clock,
      });
      const doc = await exportUserData(
        { uid: auth.uid, familyId: auth.familyId, role: auth.role, query: queryToObject(request) },
        {
          userRepo,
          familyRepo,
          deviceRepo,
          lastKnownRepo,
          groupRepo,
          groupLastKnownRepo,
          historyStore,
          usageRepo,
          entitlementsRepo,
          clock,
        },
      );

      // specs/001 §1.3/§13.1 — the ONE deliberate envelope exception: no {data, features}
      // wrapper, a Content-Disposition attachment header, and the document itself as the body.
      const filename = `findly-export-${escapeQuotedString(doc.subject.userId)}-${doc.generatedAt.slice(0, 10)}.json`;
      return {
        status: 200,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Content-Disposition": `attachment; filename="${filename}"`,
        },
        body: JSON.stringify(doc),
      };
    } catch (err) {
      if (err instanceof AppError) {
        return { status: err.httpStatus, jsonBody: fail(err, requestId) };
      }
      context.error("unhandled error in exportUserData", toSafeErrorLog(err));
      const internal = new AppError("INTERNAL_ERROR", "unexpected error");
      return { status: internal.httpStatus, jsonBody: fail(internal, requestId) };
    }
  },
});
