// specs/001 §13.3 — delete my family (parent). Bare 204 (specs/001 §13.3/§3.6/§11: no
// response body, so no `features` to return). Pure domain logic: no Azure/Google imports.
// The role/family gate lives here; the actual teardown is the shared
// src/domain/family/familyDeletion.ts function (also used by B18's last-parent/sole-member
// account-deletion cascade, specs/008 §4.2).

import { AppError } from "../../http/errors";
import type { Role } from "../../ports/repositories";
import { deleteFamilyFootprint, type DeleteFamilyFootprintDeps } from "./familyDeletion";

export type DeleteFamilyDeps = DeleteFamilyFootprintDeps;

export interface DeleteFamilyInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5), null if no family. */
  familyId: string | null;
  role: Role | null;
}

export async function deleteFamily(input: DeleteFamilyInput, deps: DeleteFamilyDeps): Promise<void> {
  if (!input.familyId) {
    throw new AppError("FAMILY_NOT_FOUND", "caller has no family");
  }
  if (input.role !== "parent") {
    throw new AppError("AUTH_FORBIDDEN", "only a parent may delete the family");
  }

  await deleteFamilyFootprint(input.familyId, input.uid, deps);
}
