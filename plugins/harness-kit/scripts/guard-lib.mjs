// Shared by git-guard.mjs (Bash) and brief-guard.mjs (Write, Edit, MultiEdit, NotebookEdit),
// the PreToolUse hooks that keep Claude out of the person's steps: what a scratch copy is,
// and which files are a brief's approval.
//
// A SCRATCH COPY is a folder strictly under the OS temp folder: os.tmpdir() (TMPDIR), /tmp,
// or either one's real path (on macOS /tmp is /private/tmp), with symbolic links resolved,
// so a link from the temp folder into the project is not a scratch copy (a link that exists
// when the hook runs: one the same command makes is not seen). Tests and experiments in
// throwaway clones there are left alone. A project kept under the temp folder is not
// guarded.
//
// A BRIEF'S APPROVAL is any file whose name ends in ".brief.approved"
// (.reports/<branch>.brief.approved, brief-lib.sh). Only approve-brief.sh, run by the person
// in their own terminal, writes it; Claude never does, in the real working tree.
import { realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";

// PATH with every existing part's symbolic links resolved (a path that does not exist yet
// keeps its missing tail as written).
export const realish = (path) => {
  const normal = resolve(path);
  try {
    return realpathSync(normal);
  } catch {
    const parent = dirname(normal);
    return parent === normal ? normal : join(realish(parent), basename(normal));
  }
};

export const TEMP_ROOTS = [...new Set([tmpdir(), "/tmp"].flatMap((root) => [resolve(root), realish(root)]))];

// True when DIR (a path; null means a folder the caller could not work out) is a scratch copy.
export const isScratch = (dir) => dir !== null && TEMP_ROOTS.some((root) => realish(dir).startsWith(`${root}/`));

// True when NAME, a file name or a path, names a brief's approval.
export const isApproval = (name) => /\.brief\.approved$/.test(name);

export const APPROVAL_REASON =
  "it is a brief's approval (.reports/<branch>.brief.approved), which only approve-brief.sh writes, run by the person in their own terminal " +
  "after reading the brief. Change the brief if it needs changing, and put approve-brief.sh in the report's \"Your commands\". " +
  "To read an approval, use the Read tool.";
