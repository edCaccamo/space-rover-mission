/*******************************************************************************
 * Copyright (c) 2022 IBM Corporation and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License 2.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-2.0/
 *
 * SPDX-License-Identifier: EPL-2.0
 *******************************************************************************/

// Static registry of rover scripts for the Free Roam mode dropdown.
//
// Bob's authoring workflow:
//   1. Write the script JSON to specs/scripts/<kebab-case-name>.json
//   2. Copy the same JSON to services/client/src/specs/scripts/<kebab-case-name>.json
//   3. Add an import and entry below so the script appears in the dropdown

export interface ScriptEntry {
  name: string;
  description: string;
  steps: Array<{ command: string; durationMs: number }>;
}

export const scripts: ScriptEntry[] = [];
