/*******************************************************************************
 * Copyright (c) 2022 IBM Corporation and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License 2.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-2.0/
 *
 * SPDX-License-Identifier: EPL-2.0
 *******************************************************************************/

// ScriptEntry is the shape of each rover script returned by GET /scripts.
// Scripts are fetched at runtime from the bob-bridge service — there are no
// static imports. See hooks/useScripts.ts.

export interface ScriptEntry {
  name: string;
  description: string;
  steps: Array<{ command: string; durationMs: number }>;
}
